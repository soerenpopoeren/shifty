// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 soerenpopoeren
// Shifty – use a Shimano Di2 to shift in Zwift and MyWhoosh. See LICENSE and CREDITS.md.

import Foundation
import Network

/// MyWhoosh via the open OpenBikeControl protocol (mDNS + TCP).
/// Specification: https://github.com/OpenBikeControl/openbikecontrol-protocol (MIT)
///
/// MyWhoosh finds the "_openbikecontrol._tcp" service on the local network and connects.
/// Works for MyWhoosh on this Mac as well as on an iPad/iPhone in the same Wi-Fi.
final class MyWhooshOutput: ObservableObject {
    @Published var enabled = false { didSet { enabled ? server.start() : server.stop() } }
    @Published var clients = 0
    @Published var appInfo: String?

    var log: ((String) -> Void)?
    var onAppInfo: (() -> Void)?

    private let server: BonjourServer
    private var statusTimer: Timer?

    enum Button: UInt8 { case shiftUp = 0x01, shiftDown = 0x02, steerLeft = 0x18, steerRight = 0x19 }

    init() {
        // MyWhoosh matches the Bonjour instance name against the host name. So the service is named
        // exactly like the Mac on the network, otherwise it may be ignored silently.
        let host = BonjourServer.localHostName
        server = BonjourServer(
            serviceType: "_openbikecontrol._tcp",
            name: host,
            txt: [
                "version": "1",
                "id": Identity.shared.deviceID,
                "name": "Shifty Di2",
                "service-uuids": "d273f680-d548-419d-b9d1-fa0472345229",
                "manufacturer": "Shifty",
                "model": "Di2 Bridge",
            ])
        server.onClientsChanged = { [weak self] n in self?.clients = n }
        server.onConnect = { [weak self] conn in
            // Device status: no battery value, ready
            self?.server.send([0x02, 0xFF, 0x01], to: conn)
        }
        server.onData = { [weak self] _, bytes in self?.handleIncoming(bytes) }
        server.log = { [weak self] in self?.log?($0) }

        statusTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, self.clients > 0 else { return }
            self.server.send([0x02, 0xFF, 0x01])
        }
    }

    /// Relative shifting. Note: MyWhoosh 5.7 lists "Gear Set" (0x03) as supported but ignores it,
    /// so Shifty only uses Shift Up / Shift Down.
    func press(_ button: Button) {
        guard enabled, clients > 0 else { return }
        server.send([0x01, button.rawValue, 0x01])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.server.send([0x01, button.rawValue, 0x00])
        }
    }

    private func handleIncoming(_ bytes: [UInt8]) {
        guard let type = bytes.first else { return }
        switch type {
        case 0x04: // app info
            var i = 2
            func str() -> String {
                guard i < bytes.count else { return "" }
                let len = Int(bytes[i]); i += 1
                let end = min(i + len, bytes.count)
                defer { i = end }
                return String(decoding: bytes[i..<end], as: UTF8.self)
            }
            let app = str(), ver = str()
            var ids: [UInt8] = []
            if i < bytes.count {
                let n = Int(bytes[i]); i += 1
                ids = Array(bytes[i..<min(i + n, bytes.count)])
            }
            appInfo = "\(app) \(ver)"
            // A count of 0 means "all buttons supported" according to the specification
            log?("MyWhoosh connected: \(app) \(ver), buttons: "
                + (ids.isEmpty ? "all" : ids.map { String(format: "%02X", $0) }.joined(separator: " ")))
            onAppInfo?()
        case 0x00:
            break // keep-alive from MyWhoosh (every ~4 s)
        case 0x03:
            break // haptic command – the Di2 can't vibrate
        default:
            log?("MyWhoosh → \(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))")
        }
    }
}

/// Stable random device ID (like a MAC address) that survives restarts.
final class Identity {
    static let shared = Identity()
    let mac: [UInt8]

    private init() {
        Migration.run() // keep the device ID of the old bundle identifier (Zwift remembers it)
        if let saved = UserDefaults.standard.array(forKey: "shiftyMac") as? [Int], saved.count == 6 {
            mac = saved.map { UInt8($0) }
        } else {
            var m = (0..<6).map { _ in UInt8.random(in: 0...255) }
            m[0] = (m[0] | 0x02) & 0xFE // locally administered, unicast
            UserDefaults.standard.set(m.map { Int($0) }, forKey: "shiftyMac")
            mac = m
        }
    }

    var deviceID: String { mac.map { String(format: "%02x", $0) }.joined() }
    var macString: String { mac.map { String(format: "%02X", $0) }.joined(separator: ":") }
}
