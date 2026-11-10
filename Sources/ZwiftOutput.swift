// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 soerenpopoeren
// Shifty – use a Shimano Di2 to shift in Zwift and MyWhoosh. See LICENSE and CREDITS.md.

import Foundation
import Network

/// Zwift: Shifty presents itself on the local network as a Zwift Ride controller.
///
/// Transport is Wahoo "Direct Connect" (DirCon): Bonjour service "_wahoo-fitness-tnp._tcp" with a
/// TCP protocol that mirrors BLE GATT (discover services/characteristics, read, write,
/// notifications). Zwift (Mac, iPad, Apple TV …) finds the device on its pairing screen.
///
/// Zwift only lists Direct Connect devices that offer a fitness service, so next to the controller
/// service Shifty also offers a Cycling Power service (0x1818, always 0 W). Pick it once as power source in Zwift (this pairs the controller), then switch
/// the power source back to the real trainer.
///
/// Zwift Ride protocol on top:
///   Zwift writes "RideOn" to 0003 → we answer "RideOn" on 0004.
///   Button presses go out as [0x23, protobuf{1: buttonMap}] on 0002.
///   buttonMap is inverted: bit = 0 means pressed.
final class ZwiftOutput: ObservableObject {
    @Published var enabled = false { didSet { enabled ? server.start() : stop() } }
    @Published var clients = 0
    @Published var handshakeDone = false

    var log: ((String) -> Void)?

    typealias Button = ZwiftProtocol.Button

    // MARK: UUIDs (16 bytes, big endian)

    private static func zwiftUUID(_ n: UInt8) -> [UInt8] {
        [0x00, 0x00, 0x00, n, 0x19, 0xCA, 0x46, 0x51, 0x86, 0xE5, 0xFA, 0x29, 0xDC, 0xDD, 0x09, 0xD1]
    }
    private static func bleUUID(_ short: UInt16) -> [UInt8] {
        [0x00, 0x00, UInt8(short >> 8), UInt8(short & 0xFF),
         0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB]
    }

    private static let controllerService = bleUUID(0xFC82) // like a real Zwift Click v2
    private static let asyncChar = zwiftUUID(0x02)   // notify: button presses
    private static let syncRxChar = zwiftUUID(0x03)  // write: commands from Zwift
    private static let syncTxChar = zwiftUUID(0x04)  // notify/indicate: responses
    private static let powerService = bleUUID(0x1818)
    private static let powerMeasurement = bleUUID(0x2A63)
    private static let rideOn: [UInt8] = Array("RideOn".utf8)
    private static let controllerNotification: UInt8 = 0x23

    private struct Char { let uuid: [UInt8]; let props: UInt8; var value: [UInt8] = [] }
    private struct Service { let uuid: [UInt8]; let chars: [Char] }

    // props: 0x01 read, 0x02 write, 0x04 notify, 0x08 indicate
    private static let services: [Service] = [
        Service(uuid: powerService, chars: [
            Char(uuid: powerMeasurement, props: 0x04),
            Char(uuid: bleUUID(0x2A65), props: 0x01, value: [0x08, 0x00, 0x00, 0x00]), // feature
            Char(uuid: bleUUID(0x2A5D), props: 0x01, value: [0x0D]),                   // sensor location: rear hub
        ]),
        Service(uuid: controllerService, chars: [
            Char(uuid: asyncChar, props: 0x04),
            Char(uuid: syncRxChar, props: 0x02),
            Char(uuid: syncTxChar, props: 0x04 | 0x08),
        ]),
    ]
    private static var allChars: [Char] { services.flatMap(\.chars) }

    private let server: BonjourServer
    private var buffers: [ObjectIdentifier: [UInt8]] = [:]
    private var keepAlive: Timer?
    private var powerTimer: Timer?

    init() {
        server = BonjourServer(
            serviceType: "_wahoo-fitness-tnp._tcp",
            name: "Shifty Di2",
            txt: [
                "ble-service-uuids": "00001818-0000-1000-8000-00805F9B34FB,0000FC82-0000-1000-8000-00805F9B34FB",
                "mac-address": Identity.shared.macString,
                "serial-number": "SHIFTY-" + Identity.shared.deviceID.suffix(6).uppercased(),
            ],
            preferredPort: 36866)
        server.onClientsChanged = { [weak self] n in
            guard let self else { return }
            self.clients = n
            if n == 0 { self.handshakeDone = false; self.keepAlive?.invalidate(); self.powerTimer?.invalidate() }
        }
        server.onData = { [weak self] conn, bytes in self?.receive(conn, bytes) }
        server.log = { [weak self] in self?.log?($0) }
    }

    private func stop() {
        keepAlive?.invalidate()
        powerTimer?.invalidate()
        server.stop()
        handshakeDone = false
    }

    // MARK: Sending buttons

    func press(_ button: Button) {
        guard enabled, clients > 0 else { return }
        sendButtons(button.rawValue)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in self?.sendButtons(0) }
    }

    private func sendButtons(_ pressedMask: UInt32) {
        let map = ~pressedMask
        notify(Self.asyncChar, [Self.controllerNotification, 0x08] + varint(UInt64(map)))
    }

    private func varint(_ value: UInt64) -> [UInt8] {
        var v = value, out: [UInt8] = []
        repeat {
            var b = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { b |= 0x80 }
            out.append(b)
        } while v != 0
        return out
    }

    private func notify(_ uuid: [UInt8], _ data: [UInt8]) {
        server.send(packet(id: 0x06, seq: 0, resp: 0, payload: uuid + data))
    }

    // MARK: DirCon

    private func packet(id: UInt8, seq: UInt8, resp: UInt8, payload: [UInt8]) -> [UInt8] {
        [0x01, id, seq, resp, UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)] + payload
    }

    private func receive(_ conn: NWConnection, _ bytes: [UInt8]) {
        let key = ObjectIdentifier(conn)
        var buf = (buffers[key] ?? []) + bytes
        while buf.count >= 6 {
            let len = Int(buf[4]) << 8 | Int(buf[5])
            guard buf.count >= 6 + len else { break }
            let msg = Array(buf[0..<(6 + len)])
            buf.removeFirst(6 + len)
            handle(conn, id: msg[1], seq: msg[2], payload: Array(msg[6...]))
        }
        buffers[key] = buf
    }

    private func handle(_ conn: NWConnection, id: UInt8, seq: UInt8, payload: [UInt8]) {
        func reply(_ resp: UInt8 = 0, _ p: [UInt8] = []) {
            server.send(packet(id: id, seq: seq, resp: resp, payload: resp == 0 ? p : []), to: conn)
        }
        let uuid = payload.count >= 16 ? Array(payload[0..<16]) : []
        let data = payload.count > 16 ? Array(payload[16...]) : []

        switch id {
        case 0x01: // discover services
            reply(0, Self.services.flatMap(\.uuid))
        case 0x02: // discover characteristics
            guard let svc = Self.services.first(where: { $0.uuid == uuid }) else { return reply(0x03) }
            reply(0, svc.uuid + svc.chars.flatMap { $0.uuid + [$0.props] })
        case 0x03: // read
            guard let c = Self.allChars.first(where: { $0.uuid == uuid }) else { return reply(0x04) }
            reply(0, uuid + c.value)
        case 0x04: // write
            guard Self.allChars.contains(where: { $0.uuid == uuid }) else { return reply(0x04) }
            reply(0, uuid)
            onWrite(uuid, data)
        case 0x05: // enable/disable notifications
            guard Self.allChars.contains(where: { $0.uuid == uuid }) else { return reply(0x04) }
            reply(0, uuid)
            if uuid == Self.powerMeasurement { startPower(data.first == 1) }
        case 0x07: // echo / keep-alive
            reply()
        default:
            reply(0x01)
        }
    }

    /// While Zwift listens to the power service, report 0 W once per second.
    private func startPower(_ on: Bool) {
        powerTimer?.invalidate()
        guard on else { return }
        log?("Zwift subscribed to power (0 W) – switch the power source back to your trainer")
        powerTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.clients > 0 else { return }
            self.notify(Self.powerMeasurement, [0x00, 0x00, 0x00, 0x00]) // flags, power (sint16)
        }
    }

    private func onWrite(_ uuid: [UInt8], _ data: [UInt8]) {
        guard uuid == Self.syncRxChar else { return }
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        if data.starts(with: Self.rideOn) {
            log?("Zwift handshake received (\(hex)) → RideOn")
            notify(Self.syncTxChar, ZwiftProtocol.rideOnResponse)
            handshakeDone = true
            startKeepAlive()
        } else if data.first == 0x00 {
            // GET request: [0x00, protobuf{1: object id}]. Without an answer Zwift drops us after ~1 min.
            let id = ZwiftProtocol.getRequestID(data) ?? -1
            log?("Zwift → GET object \(id) (\(hex))")
            if let answer = ZwiftProtocol.getResponse(for: id) { notify(Self.syncTxChar, answer) }
        } else {
            log?("Zwift → 0003: \(hex)")
        }
    }

    /// Zwift drops a controller after ~30 s of silence, so we send "nothing pressed" every 5 s.
    private func startKeepAlive() {
        keepAlive?.invalidate()
        keepAlive = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.clients > 0 else { return }
            self.sendButtons(0)
        }
    }
}
