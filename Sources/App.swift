// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 soerenpopoeren
// Shifty – use a Shimano Di2 to shift in Zwift and MyWhoosh. See LICENSE and CREDITS.md.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Color {
    /// Shimano cyan
    static let shimano = Color(red: 0.0, green: 0.60, blue: 0.85)
    static let shimanoLight = Color(red: 0.18, green: 0.76, blue: 0.95)
}

#if !SNAPSHOT
@main
#endif
struct ShiftyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environmentObject(delegate.bridge)
                .environmentObject(delegate.logos)
        } label: {
            MenuBarLabel().environmentObject(delegate.bridge)
        }
        .menuBarExtraStyle(.window)

        Window("Shifty", id: "settings") {
            SettingsView()
                .environmentObject(delegate.bridge)
                .environmentObject(delegate.logos)
                .frame(minWidth: 640, idealWidth: 640, minHeight: 560, idealHeight: 820)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let bridge = Bridge()
    let logos = LogoStore()
    private var mini: MiniWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        mini = MiniWindowController(bridge: bridge, logos: logos)
        bridge.onShowMiniChanged = { [weak self] in $0 ? self?.mini?.show() : self?.mini?.hide() }
        if bridge.showMini { mini?.show() }
    }
}

// MARK: - Menu bar

struct MenuBarLabel: View {
    @EnvironmentObject var bridge: Bridge
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: bridge.di2.connectedName != nil ? "bicycle" : "bicycle.circle")
            Text("\(bridge.gear)").monospacedDigit()
        }
    }
}

struct MenuPanel: View {
    @EnvironmentObject var bridge: Bridge
    @EnvironmentObject var logos: LogoStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.bottom, 4)

            GearReel(gear: bridge.gear, maxGear: bridge.maxGear, height: 96)
                .contextMenu {
                    if bridge.zwiftConnected {
                        Button(t(.syncWithToGear, "Zwift", "\(bridge.gear)")) { bridge.sync("zwift") }
                    }
                    if bridge.mywhoosh.clients > 0 {
                        Button(t(.syncWithToGear, "MyWhoosh", "\(bridge.gear)")) { bridge.sync("mywhoosh") }
                    }
                    Button(t(.setMiddle)) { bridge.setGear(bridge.maxGear / 2) }
                    Button(t(.setGearOne)) { bridge.setGear(1) }
                }
                .overlay(alignment: .bottom) {
                    if bridge.syncing {
                        Label(t(.syncing), systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.shimano)
                    }
                }
            GearBars(gear: bridge.gear, maxGear: bridge.maxGear)
                .frame(height: 22)
                .padding(.top, 4)
                .padding(.bottom, 16)

            HStack(spacing: 10) {
                ShiftButton(up: false)
                ShiftButton(up: true)
            }
            .padding(.bottom, 18)

            ZwiftHintBanner()

            Divider().opacity(0.5)

            HStack(alignment: .top, spacing: 0) {
                AppTile(key: "zwift", fallback: "Z",
                        enabled: Binding(get: { bridge.zwift.enabled }, set: { bridge.zwift.enabled = $0 }),
                        connected: bridge.zwiftConnected,
                        status: bridge.zwiftConnected ? t(.connected)
                            : bridge.zwift.enabled ? (bridge.zwift.clients > 0 ? t(.pairing) : t(.waiting)) : t(.off))
                    .overlay(alignment: .top) { ZwiftGuideButton().offset(x: 24, y: -6) }
                AppTile(key: "mywhoosh", fallback: "MW",
                        enabled: Binding(get: { bridge.mywhoosh.enabled }, set: { bridge.mywhoosh.enabled = $0 }),
                        connected: bridge.mywhoosh.clients > 0,
                        status: bridge.mywhoosh.clients > 0 ? t(.connected) : bridge.mywhoosh.enabled ? t(.waiting) : t(.off))
                AppTile(key: "keyboard", fallback: nil, symbol: "keyboard",
                        enabled: Binding(get: { bridge.keyboard.enabled }, set: { bridge.keyboard.enabled = $0 }),
                        connected: bridge.keyboard.enabled && bridge.keyboard.trusted,
                        status: !bridge.keyboard.enabled ? t(.off) : bridge.keyboard.trusted ? t(.active) : t(.permissionMissing))
            }
            .padding(.top, 14)
        }
        .padding(18)
        .frame(width: 310)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 26, height: 26)
                .padding(-3) // the icon has the macOS margin built in
            Circle()
                .fill(bridge.di2.connectedName != nil ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 8, height: 8)
                .shadow(color: bridge.di2.connectedName != nil ? Color.green.opacity(0.7) : .clear, radius: 4)
            VStack(alignment: .leading, spacing: 0) {
                Text(bridge.di2.connectedName ?? t(.noDi2)).font(.system(size: 13, weight: .semibold))
                if bridge.di2.connectedName == nil {
                    Text(Localizer.shared.t(bridge.di2.status)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            IconButton(symbol: bridge.showMini ? "pip.fill" : "pip", help: t(.miniDisplay)) { bridge.showMini.toggle() }
            IconButton(symbol: SettingsWindow.isOpen ? "gearshape.fill" : "gearshape", help: t(.settings)) {
                // The gear toggles: a second click closes the settings again
                if let window = SettingsWindow.window, window.isVisible {
                    window.close()
                } else {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            IconButton(symbol: "power", help: t(.quit)) { NSApp.terminate(nil) }
        }
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Zwift guidance

/// Small "?" on the Zwift tile: the three pairing steps.
struct ZwiftGuideButton: View {
    @State private var open = false
    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: "questionmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 15, height: 15)
                .background(Circle().fill(Color.shimano))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(t(.zwiftHowTo)).font(.system(size: 13, weight: .semibold))
                ForEach(Array([L.zwiftStep1, .zwiftStep2, .zwiftStep3].enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(i + 1)")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 18, height: 18).background(Circle().fill(Color.shimano))
                        Text(t(step)).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text(t(.zwiftWhy)).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 260)
        }
    }
}

/// Hint while Zwift is being set up, and a short confirmation once shifting works.
struct ZwiftHintBanner: View {
    @EnvironmentObject var bridge: Bridge
    var body: some View {
        Group {
            switch bridge.zwiftHint {
            case .finishSetup:
                banner(t(.hintFinish), symbol: "arrow.uturn.backward.circle", color: .orange)
            case .active:
                banner(t(.hintActive), symbol: "checkmark.circle.fill", color: .green)
            case .none:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: bridge.zwiftHint)
    }

    private func banner(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text).font(.system(size: 11, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color.opacity(0.14)))
        .padding(.bottom, 14)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Gear display

/// Gear display like a slot machine: every digit has its own reel.
/// From 13 to 14 only the ones digit rolls, the 1 stays put.
struct GearReel: View {
    let gear: Int
    let maxGear: Int
    let height: CGFloat

    var body: some View {
        HStack(spacing: -height * 0.06) {
            if gear >= 10 {
                DigitReel(digit: gear / 10, height: height)
                    .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
            DigitReel(digit: gear % 10, height: height)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
        // Glow only after clipping, otherwise you see boxes around the digits
        .compositingGroup()
        .shadow(color: Color.shimano.opacity(0.3), radius: 8, y: 3)
        .animation(.spring(response: 0.42, dampingFraction: 0.75), value: gear >= 10)
    }
}

/// A single digit reel 0–9 that always turns the shortest way
/// (from 9 to 0 it rolls forward over the edge instead of back through all digits).
struct DigitReel: View {
    let digit: Int
    let height: CGFloat

    private static let cycles = 6
    @State private var position: Int = 0
    @State private var ready = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<(Self.cycles * 10), id: \.self) { i in
                Text("\(i % 10)")
                    .font(.system(size: height * 0.86, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(height: height)
            }
        }
        .foregroundStyle(LinearGradient(colors: [.shimanoLight, .shimano], startPoint: .top, endPoint: .bottom))
        .offset(y: -CGFloat(position) * height)
        .frame(width: height * 0.56, height: height, alignment: .top)
        .clipped()
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.2),
                                     .init(color: .black, location: 0.8), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .onAppear {
            position = Self.cycles / 2 * 10 + digit
            ready = true
        }
        .onChange(of: digit) { old, new in
            guard ready else { return }
            var step = (new - old + 10) % 10
            if step > 5 { step -= 10 }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { position += step }
            // If the reel drifts too close to its end, quietly reset it to the middle
            if position < 15 || position > Self.cycles * 10 - 15 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { position = Self.cycles / 2 * 10 + new }
                }
            }
        }
    }
}

struct GearBars: View {
    let gear: Int
    let maxGear: Int
    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 2.5
            let w = max(2, (geo.size.width - spacing * CGFloat(maxGear - 1)) / CGFloat(maxGear))
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(1...max(maxGear, 1), id: \.self) { i in
                    Capsule()
                        .fill(i <= gear ? AnyShapeStyle(LinearGradient(colors: [.shimanoLight, .shimano],
                                                                         startPoint: .top, endPoint: .bottom))
                                        : AnyShapeStyle(Color.secondary.opacity(0.2)))
                        .frame(width: w, height: geo.size.height * (0.3 + 0.7 * CGFloat(i) / CGFloat(maxGear)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(.easeOut(duration: 0.25), value: gear)
    }
}

// MARK: - Plus / minus

struct ShiftButton: View {
    @EnvironmentObject var bridge: Bridge
    let up: Bool
    @State private var lit = false

    var body: some View {
        Button { bridge.perform(up ? .shiftUp : .shiftDown) } label: {
            Image(systemName: up ? "plus" : "minus")
                .font(.system(size: 22, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(lit ? Color.white : Color.primary)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(lit ? AnyShapeStyle(LinearGradient(colors: [.shimanoLight, .shimano],
                                                                 startPoint: .top, endPoint: .bottom))
                                  : AnyShapeStyle(.clear))
                }
                .glossy(cornerRadius: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(up ? t(.harder) : t(.easier))
        .onChange(of: bridge.lastShift?.at) { _, _ in
            guard bridge.lastShift?.up == up else { return }
            withAnimation(.easeOut(duration: 0.08)) { lit = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                withAnimation(.easeIn(duration: 0.25)) { lit = false }
            }
        }
    }
}

// MARK: - App tiles

struct AppTile: View {
    @EnvironmentObject var logos: LogoStore
    let key: String
    let fallback: String?
    var symbol: String? = nil
    @Binding var enabled: Bool
    let connected: Bool
    let status: String
    @State private var dropHover = false

    var body: some View {
        VStack(spacing: 8) {
            LogoView(key: key, fallback: fallback, symbol: symbol, size: 52)
                .overlay {
                    if dropHover {
                        RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(Color.shimano, lineWidth: 2)
                    }
                }
                .onDrop(of: [.fileURL, .image], isTargeted: $dropHover) { providers in
                    logos.accept(providers, for: key)
                }
                .help(symbol == nil ? t(.dropLogo) : "")
                .saturation(connected ? 1 : 0.15)
                .opacity(connected ? 1 : 0.55)

            Toggle("", isOn: $enabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(connected ? .green : .gray)

            Text(status)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(connected ? Color.green : Color.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

struct LogoView: View {
    @EnvironmentObject var logos: LogoStore
    let key: String
    let fallback: String?
    var symbol: String? = nil
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
        ZStack {
            if let img = logos.images[key] {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            } else if let symbol {
                Image(systemName: symbol).font(.system(size: size * 0.46, weight: .regular)).foregroundStyle(.primary)
            } else {
                Text(fallback ?? "?").font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .glossy(cornerRadius: size * 0.25)
    }
}

/// Logos: first an image the user dropped in, otherwise the icon of the installed app.
final class LogoStore: ObservableObject {
    @Published var images: [String: NSImage] = [:]

    private static let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shifty", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private static let installed: [String: [String]] = [
        "zwift": ["Zwift.app", "Zwift Launcher.app", "ZwiftLauncher.app"],
        "mywhoosh": ["MyWhoosh.app", "MyWhoosh Indoor Cycling App.app"],
    ]

    init() {
        for key in ["zwift", "mywhoosh"] { load(key) }
    }

    private func file(_ key: String) -> URL { Self.dir.appendingPathComponent("logo-\(key).png") }

    private func load(_ key: String) {
        if let img = NSImage(contentsOf: file(key)) {
            images[key] = img
            return
        }
        let roots = ["/Applications", NSHomeDirectory() + "/Applications"]
        for root in roots {
            for name in Self.installed[key] ?? [] {
                let path = root + "/" + name
                if FileManager.default.fileExists(atPath: path) {
                    images[key] = NSWorkspace.shared.icon(forFile: path)
                    return
                }
            }
        }
    }

    func accept(_ providers: [NSItemProvider], for key: String) -> Bool {
        guard let p = providers.first else { return false }
        if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                // .app bundle -> its icon, otherwise the image file
                let img = url.pathExtension == "app" ? NSWorkspace.shared.icon(forFile: url.path) : NSImage(contentsOf: url)
                if let img { DispatchQueue.main.async { self.save(img, key) } }
            }
            return true
        }
        _ = p.loadObject(ofClass: NSImage.self) { img, _ in
            if let img = img as? NSImage { DispatchQueue.main.async { self.save(img, key) } }
        }
        return true
    }

    private func save(_ img: NSImage, _ key: String) {
        images[key] = img
        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: file(key))
        }
    }

    func reset(_ key: String) {
        try? FileManager.default.removeItem(at: file(key))
        images[key] = nil
        load(key)
    }
}

// MARK: - Glass look

enum GlassStyle {
    /// Only for preview images: real Liquid Glass is not drawn when rendering to a file.
    static var forceFallback = false
}

extension View {
    /// Glossy glass surface: real Liquid Glass on macOS 26, otherwise material + highlight edge.
    @ViewBuilder func glossy(cornerRadius r: CGFloat) -> some View {
        if #available(macOS 26.0, *), !GlassStyle.forceFallback {
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: r, style: .continuous))
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: r, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: r, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.05)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
        }
    }
}

// MARK: - Floating mini display (widget replacement)

/// Finds the settings window (SwiftUI names it after the scene id "settings").
enum SettingsWindow {
    static var window: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("settings") == true }
    }
    static var isOpen: Bool { window?.isVisible == true }
}

final class MiniWindowController {
    private let panel: NSPanel
    private var opacityObserver: Any?

    init(bridge: Bridge, logos: LogoStore) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 170, height: 170),
                        styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        // Also above Zwift/MyWhoosh in full screen and on all desktops
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = NSHostingView(rootView: MiniView().environmentObject(bridge).environmentObject(logos))
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        panel.contentView = host
        panel.setFrameAutosaveName("ShiftyMini")
        if panel.frame.origin == .zero, let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 200, y: screen.visibleFrame.maxY - 200))
        }
    }

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }
}

struct MiniView: View {
    @EnvironmentObject var bridge: Bridge

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(t(.gear)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Circle().fill(bridge.di2.connectedName != nil ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
            }
            GearReel(gear: bridge.gear, maxGear: bridge.maxGear, height: 74)
            GearBars(gear: bridge.gear, maxGear: bridge.maxGear).frame(height: 12)
            HStack(spacing: 6) {
                appDot("Z", bridge.zwiftConnected)
                appDot("MW", bridge.mywhoosh.clients > 0)
                Spacer()
                Text("\(bridge.gear)/\(bridge.maxGear)").font(.system(size: 10)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 150, height: 150)
        // Only the glass background fades; number, bar and dots stay fully visible
        .background {
            Color.clear
                .glossy(cornerRadius: 26)
                .opacity(bridge.miniBackgroundOpacity)
        }
        .padding(10)
        .contextMenu {
            Button(t(.hideMini)) { bridge.showMini = false }
        }
    }

    private func appDot(_ label: String, _ on: Bool) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(on ? Color.white : Color.secondary)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(on ? Color.green : Color.secondary.opacity(0.18)))
    }
}

