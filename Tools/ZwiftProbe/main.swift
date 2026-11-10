// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 soerenpopoeren
//
// Zwift controller probe – developer tool, not part of the app.
// Connects to real Zwift controllers (Click, Play, Ride) like Zwift does, performs the "RideOn"
// handshake, asks the same GET requests Zwift asks and logs everything to ~/Library/Logs/ZwiftProbe.log.
// Used to learn what a real controller answers, so Shifty can answer the same.
//
// Build & run: Tools/ZwiftProbe/run.sh   (quit Zwift first – a controller allows only one connection)

import CoreBluetooth
import Foundation

let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/ZwiftProbe.log")
let runSeconds: TimeInterval = 120
let zwiftManufacturer: UInt16 = 0x094A
let handshake: [UInt8] = Array("RideOn".utf8) + [0x02, 0x04] // what Zwift sends
let getRequests: [Int] = [0, 16, 520]

func log(_ s: String) {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
    let line = "\(f.string(from: Date()))  \(s)\n"
    print(line, terminator: "")
    if let h = try? FileHandle(forWritingTo: logURL) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
    else { try? line.data(using: .utf8)!.write(to: logURL) }
}
func hex(_ d: Data?) -> String { (d ?? Data()).map { String(format: "%02X", $0) }.joined(separator: " ") }
func varint(_ value: UInt64) -> [UInt8] {
    var v = value, out: [UInt8] = []
    repeat { var b = UInt8(v & 0x7F); v >>= 7; if v != 0 { b |= 0x80 }; out.append(b) } while v != 0
    return out
}

final class Probe: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var central: CBCentralManager!
    var devices: [UUID: CBPeripheral] = [:]
    var rx: [UUID: CBCharacteristic] = [:]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    static func isZwift(name: String?, adv: [String: Any]) -> Bool {
        if let n = name?.uppercased(), n.contains("SHIFTY") { return false } // our own emulator
        if let m = adv[CBAdvertisementDataManufacturerDataKey] as? Data, m.count >= 2,
           UInt16(m[0]) | UInt16(m[1]) << 8 == zwiftManufacturer { return true }
        let services = adv[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        if services.contains(CBUUID(string: "FC82")) || services.contains(CBUUID(string: "00000001-19CA-4651-86E5-FA29DCDD09D1")) { return true }
        let n = (name ?? "").lowercased()
        return n.contains("zwift") || n.contains("click") || n.contains("play") || n.contains("ride")
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        guard c.state == .poweredOn else { log("Bluetooth state \(c.state.rawValue)"); return }
        log("Scanning for Zwift controllers … press a button on them to wake them up")
        c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData adv: [String: Any], rssi: NSNumber) {
        let name = p.name ?? adv[CBAdvertisementDataLocalNameKey] as? String
        guard devices[p.identifier] == nil, Self.isZwift(name: name, adv: adv) else { return }
        devices[p.identifier] = p
        log("FOUND \(name ?? "?") rssi \(rssi)")
        for (k, v) in adv {
            if let d = v as? Data { log("  adv \(k): \(hex(d))") }
            else if let d = v as? [CBUUID: Data] { for (u, x) in d { log("  adv \(k) \(u): \(hex(x))") } }
            else { log("  adv \(k): \(v)") }
        }
        p.delegate = self
        c.connect(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        log("CONNECTED \(p.name ?? "?")")
        p.discoverServices(nil)
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        log("connect failed \(p.name ?? "?"): \(error?.localizedDescription ?? "?")")
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        log("DISCONNECTED \(p.name ?? "?") \(error?.localizedDescription ?? "")")
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { log("  service \(s.uuid.uuidString)"); p.discoverCharacteristics(nil, for: s) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for c in s.characteristics ?? [] {
            log("    char \(c.uuid.uuidString) props 0x\(String(c.properties.rawValue, radix: 16))")
            if c.properties.contains(.read) { p.readValue(for: c) }
            if c.properties.contains(.notify) || c.properties.contains(.indicate) { p.setNotifyValue(true, for: c) }
            if c.uuid == CBUUID(string: "00000003-19CA-4651-86E5-FA29DCDD09D1") { rx[p.identifier] = c }
        }
        if let c = rx[p.identifier], s.characteristics?.contains(c) == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.startHandshake(p) }
        }
    }

    func write(_ p: CBPeripheral, _ bytes: [UInt8]) {
        guard let c = rx[p.identifier] else { return }
        let type: CBCharacteristicWriteType = c.properties.contains(.write) ? .withResponse : .withoutResponse
        log("  → WRITE \(hex(Data(bytes)))")
        p.writeValue(Data(bytes), for: c, type: type)
    }

    func startHandshake(_ p: CBPeripheral) {
        write(p, handshake)
        for (i, id) in getRequests.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + Double(i) * 1.0) {
                self.write(p, [0x00, 0x08] + varint(UInt64(id)))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            log("Handshake and GET requests sent. Now press each button once (shift up/down, etc.).")
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        log("  ← \(c.uuid.uuidString.prefix(8)) \(hex(c.value))  \(String(decoding: (c.value ?? Data()).filter { $0 >= 32 && $0 < 127 }, as: UTF8.self))")
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        if let error { log("  write error: \(error.localizedDescription)") }
    }
}

try? FileManager.default.removeItem(at: logURL)
log("ZwiftProbe – running for \(Int(runSeconds)) s")
let probe = Probe()
DispatchQueue.main.asyncAfter(deadline: .now() + runSeconds) { log("Done."); exit(0) }
RunLoop.main.run()
