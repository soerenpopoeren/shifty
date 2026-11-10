// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 soerenpopoeren
// Shifty – use a Shimano Di2 to shift in Zwift and MyWhoosh. See LICENSE and CREDITS.md.

import Combine
import Foundation
import IOKit.pwr_mgt

enum Action: String, CaseIterable, Identifiable, Codable {
    case none, shiftUp, shiftDown, uturn
    var id: String { rawValue }

    /// Shown in the button mapping picker.
    var title: String {
        let l = Localizer.shared
        switch self {
        case .none: return l.t(.actionNone)
        case .shiftUp: return l.t(.actionShiftUp)
        case .shiftDown: return l.t(.actionShiftDown)
        case .uturn: return l.t(.actionUturn)
        }
    }
}

/// Connects the Di2 to all enabled outputs.
final class Bridge: ObservableObject {
    let di2 = Di2Client()
    let zwift = ZwiftOutput()
    let mywhoosh = MyWhooshOutput()
    let keyboard = KeyboardOutput()

    @Published var mapping: [Int: Action] {
        didSet { UserDefaults.standard.set(mapping.map { "\($0.key)=\($0.value.rawValue)" }, forKey: "mapping") }
    }
    @Published var repeatOnHold = true { didSet { UserDefaults.standard.set(repeatOnHold, forKey: "repeatOnHold") } }
    /// Which D-Fly channel each physical button sends, as set in E-TUBE ("L.A", "R.X", …).
    /// Only used for the shifter drawing; actions stay per channel.
    @Published var buttonChannels: [String: Int] {
        didSet { UserDefaults.standard.set(buttonChannels, forKey: "buttonChannels") }
    }
    /// Button waiting to be learned: the next D-Fly press assigns its channel to it.
    @Published var learning: String?
    @Published var logLines: [String] = []
    /// Virtual gear as counted by Shifty (1…maxGear). Remembered per app.
    @Published var gear = 12 {
        didSet { UserDefaults.standard.set(gear, forKey: "gear.\(currentApp)") }
    }
    /// The app the gear is currently counted for ("zwift" / "mywhoosh").
    private(set) var currentApp = "zwift"
    /// Is a sync running (all the way down, then up)?
    @Published var syncing = false
    private var syncQueue: [Action] = []
    /// Zwift has 24 virtual gears, MyWhoosh 30. Follows the most recently connected app.
    @Published var maxGear = 24
    /// For lighting up plus/minus: direction and time of the last shift.
    @Published var lastShift: (up: Bool, at: Date)?
    @Published var showMini = false {
        didSet { UserDefaults.standard.set(showMini, forKey: "showMini"); onShowMiniChanged?(showMini) }
    }
    var onShowMiniChanged: ((Bool) -> Void)?
    /// How see-through the glass background of the mini display is (0 = solid glass, 1 = maximum).
    /// The content always stays fully visible.
    @Published var miniTransparency: Double = 0 {
        didSet { UserDefaults.standard.set(miniTransparency, forKey: "miniTransparency") }
    }
    /// Even at 100 % a hint of glass stays, so the display keeps its shape.
    var miniBackgroundOpacity: Double { 1 - 0.9 * miniTransparency }

    private var repeatTimers: [Int: Timer] = [:]
    private var bag = Set<AnyCancellable>()
    private let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    init() {
        Migration.run()
        // Default: left lever (channels 1+2) easier, right lever (channels 3+4) harder
        var m: [Int: Action] = [1: .shiftDown, 2: .shiftDown, 3: .shiftUp, 4: .shiftUp]
        for entry in UserDefaults.standard.stringArray(forKey: "mapping") ?? [] {
            let parts = entry.split(separator: "=")
            if parts.count == 2, let ch = Int(parts[0]), let a = Action(rawValue: String(parts[1])) { m[ch] = a }
        }
        mapping = m
        // Default: the top buttons, as recommended in the README (left Ch 1, right Ch 3)
        buttonChannels = UserDefaults.standard.dictionary(forKey: "buttonChannels") as? [String: Int]
            ?? ["L.A": 1, "R.A": 3]
        if UserDefaults.standard.object(forKey: "repeatOnHold") != nil {
            repeatOnHold = UserDefaults.standard.bool(forKey: "repeatOnHold")
        }

        let logger: (String) -> Void = { [weak self] in self?.log($0) }
        di2.log = logger
        zwift.log = logger
        mywhoosh.log = logger
        keyboard.log = logger
        di2.onPress = { [weak self] ch, kind in self?.handle(channel: ch, kind: kind) }

        // Forward changes of the sub-objects (and the language) to the UI
        for p in [di2.objectWillChange, zwift.objectWillChange, mywhoosh.objectWillChange,
                  keyboard.objectWillChange, Localizer.shared.objectWillChange] {
            p.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        }

        // Outputs as last time
        let d = UserDefaults.standard
        zwift.enabled = d.object(forKey: "out.zwift") == nil ? true : d.bool(forKey: "out.zwift")
        mywhoosh.enabled = d.object(forKey: "out.mywhoosh") == nil ? true : d.bool(forKey: "out.mywhoosh")
        keyboard.enabled = d.bool(forKey: "out.keyboard")
        zwift.$enabled.dropFirst().sink { d.set($0, forKey: "out.zwift") }.store(in: &bag)
        mywhoosh.$enabled.dropFirst().sink { d.set($0, forKey: "out.mywhoosh") }.store(in: &bag)
        keyboard.$enabled.dropFirst().sink { d.set($0, forKey: "out.keyboard") }.store(in: &bag)
        showMini = d.bool(forKey: "showMini")
        miniTransparency = min(max(d.double(forKey: "miniTransparency"), 0), 1)

        // When an app connects, switch the number of gears
        zwift.$handshakeDone.removeDuplicates().filter { $0 }
            .sink { [weak self] _ in self?.useGears(24, app: "zwift") }.store(in: &bag)
        mywhoosh.$clients.map { $0 > 0 }.removeDuplicates().filter { $0 }
            .sink { [weak self] _ in self?.useGears(30, app: "mywhoosh") }.store(in: &bag)
        keyboard.$enabled.removeDuplicates().filter { $0 }
            .sink { [weak self] _ in
                guard let self, !self.zwift.handshakeDone, self.mywhoosh.clients == 0 else { return }
                self.useGears(30, app: "mywhoosh")
            }.store(in: &bag)

        // Sync on the first connection after Shifty starts. Not on a reconnect in the middle
        // of a ride – otherwise the rider would suddenly be shifted through all gears.
        mywhoosh.onAppInfo = { [weak self] in
            guard let self, !self.autoSynced.contains("mywhoosh") else { return }
            self.autoSynced.insert("mywhoosh")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.sync("mywhoosh") }
        }
        // Zwift starts every ride in gear 8 and ignores shift commands while it is still setting up the
        // controller, so instead of shifting through all gears Shifty simply starts counting at 8.
        // A short drop-out in the middle of a ride (< 2 min) keeps the current gear.
        zwift.$handshakeDone.dropFirst().removeDuplicates() // ignore the initial "not connected"
            .sink { [weak self] connected in
                guard let self else { return }
                if !connected {
                    self.lastZwiftDisconnect = Date()
                    self.zwiftHint = .none
                    return
                }
                // Until the first shift: remind the rider of the last pairing step
                if self.zwiftHint != .active { self.zwiftHint = .finishSetup }
                let gap = self.lastZwiftDisconnect.map { Date().timeIntervalSince($0) } ?? .infinity
                if gap > 120 {
                    self.gear = Self.zwiftStartGear
                    self.log("Zwift: new ride, Zwift starts in gear \(Self.zwiftStartGear)")
                }
            }.store(in: &bag)

        // Keep the Mac awake while the Di2 or a training app is connected (Bluetooth stops in sleep)
        objectWillChange.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateKeepAwake() } }
            .store(in: &bag)

        let saved = d.integer(forKey: "gear.zwift")
        gear = saved > 0 ? saved : 12
    }

    static let zwiftStartGear = 8

    /// Guidance in the menu bar window while Zwift is being set up.
    enum ZwiftHint { case none, finishSetup, active }
    @Published var zwiftHint: ZwiftHint = .none

    private var lastZwiftDisconnect: Date?

    // MARK: Keep awake

    private var sleepAssertion: IOPMAssertionID = 0

    private func updateKeepAwake() {
        let active = di2.connectedName != nil || zwiftConnected || mywhoosh.clients > 0
        if active, sleepAssertion == 0 {
            var id: IOPMAssertionID = 0
            let ok = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Shifty: Di2 / training app connected" as CFString, &id)
            if ok == kIOReturnSuccess {
                sleepAssertion = id
                log("Keeping the Mac awake while connected")
            }
        } else if !active, sleepAssertion != 0 {
            IOPMAssertionRelease(sleepAssertion)
            sleepAssertion = 0
            log("Mac may sleep again")
        }
    }

    private func useGears(_ n: Int, app: String) {
        currentApp = app
        maxGear = n
        let saved = UserDefaults.standard.integer(forKey: "gear.\(app)")
        gear = (1...n).contains(saved) ? saved : n / 2
        log("\(Self.appName(app)): \(n) gears, gear \(gear)")
    }

    static func appName(_ app: String) -> String { app == "zwift" ? "Zwift" : "MyWhoosh" }

    /// Only change Shifty's counter (when it doesn't match the game).
    func setGear(_ g: Int) {
        gear = min(max(1, g), maxGear)
    }

    /// Apps that were already synced automatically since Shifty started.
    private var autoSynced: Set<String> = []
    private var syncTarget = ""

    /// Zwift connected (via Wi-Fi / Direct Connect).
    var zwiftConnected: Bool { zwift.handshakeDone }

    func isConnected(_ app: String) -> Bool {
        app == "zwift" ? zwiftConnected : mywhoosh.clients > 0
    }

    /// Zwift and MyWhoosh don't report their gear. So: shift all the way down (the game stops
    /// at gear 1), then up to Shifty's gear. Afterwards both match.
    func sync(_ app: String) {
        guard isConnected(app), !syncing else { return }
        let n = app == "zwift" ? 24 : 30
        if currentApp != app { useGears(n, app: app) }
        let goal = min(max(gear, 1), n)
        syncQueue = Array(repeating: .shiftDown, count: n) + Array(repeating: .shiftUp, count: goal - 1)
        syncTarget = app
        syncing = true
        log("\(Self.appName(app)) sync: down to 1, then up to \(goal)")
        stepSync()
    }

    private func stepSync() {
        guard !syncQueue.isEmpty, isConnected(syncTarget) else {
            if syncing { log("Sync done: gear \(gear)") }
            syncing = false
            return
        }
        let a = syncQueue.removeFirst()
        if syncTarget == "zwift" {
            zwift.press(a == .shiftUp ? .shiftUpRight : .shiftUpLeft)
        } else {
            mywhoosh.press(a == .shiftUp ? .shiftUp : .shiftDown)
        }
        gear = a == .shiftUp ? min(gear + 1, maxGear) : max(gear - 1, 1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in self?.stepSync() }
    }

    /// The log is always English so it can be shared in bug reports.
    func log(_ s: String) {
        logLines.append("\(timeFmt.string(from: Date()))  \(s)")
        if logLines.count > 300 { logLines.removeFirst(logLines.count - 300) }
        // Also written to ~/Library/Logs/Shifty.log (helps with troubleshooting)
        if let data = (logLines.last! + "\n").data(using: .utf8) {
            if let h = try? FileHandle(forWritingTo: Self.logFile) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: Self.logFile)
            }
        }
    }

    static let logFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Shifty.log")

    /// Assigns a channel to a button (or removes it with nil). A channel belongs to one button only.
    func assign(_ channel: Int?, to button: String) {
        var map = buttonChannels
        if let channel { map = map.filter { $0.value != channel } }
        map[button] = channel
        buttonChannels = map
    }

    private func handle(channel: Int, kind: Di2Client.PressKind) {
        // Learning mode: the press only tells us which channel the button sends.
        if let button = learning {
            if kind != .released {
                assign(channel, to: button)
                learning = nil
                log("Learned: button \(button) sends D-Fly channel \(channel)")
            }
            return
        }
        let action = mapping[channel] ?? Action.none
        switch kind {
        case .short, .double:
            stopRepeat(channel)
            perform(action)
        case .long:
            stopRepeat(channel)
            perform(action)
            if repeatOnHold, action == .shiftUp || action == .shiftDown {
                // Hold = keep shifting until released
                repeatTimers[channel] = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                    self?.perform(action)
                }
            }
        case .released:
            stopRepeat(channel)
        }
    }

    private func stopRepeat(_ ch: Int) {
        repeatTimers[ch]?.invalidate()
        repeatTimers[ch] = nil
    }

    func perform(_ action: Action) {
        guard action != .none, !syncing else { return }
        // First shift after Zwift connected: setup is done, confirm briefly
        if zwiftHint == .finishSetup, zwiftConnected {
            zwiftHint = .active
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                if self?.zwiftHint == .active { self?.zwiftHint = .none }
            }
        }
        switch action {
        case .shiftUp:
            gear = min(gear + 1, maxGear)
            lastShift = (true, Date())
            zwift.press(.shiftUpRight)
            mywhoosh.press(.shiftUp)
            keyboard.tap(KeyboardOutput.keyK)
        case .shiftDown:
            gear = max(gear - 1, 1)
            lastShift = (false, Date())
            zwift.press(.shiftUpLeft)
            mywhoosh.press(.shiftDown)
            keyboard.tap(KeyboardOutput.keyI)
        case .uturn:
            zwift.press(.uturn) // Zwift only
        case .none:
            break
        }
        log("→ \(action.rawValue)")
    }
}
