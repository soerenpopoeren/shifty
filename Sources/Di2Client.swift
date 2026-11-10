// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 soerenpopoeren
// Shifty – use a Shimano Di2 to shift in Zwift and MyWhoosh. See LICENSE and CREDITS.md.

import CoreBluetooth
import Foundation

/// Connects to a Shimano Di2 over Bluetooth LE (12-speed wireless: rear derailleur "RDR…";
/// 11-speed: EW-WU111 wireless unit) and reads the D-Fly channels.
///
/// Protocol (D-Fly service 18EF, characteristic 2AC2, indications), see CREDITS.md:
///   byte 0    = running report number
///   byte 1…n  = one byte per D-Fly channel. Every press changes the channel's value.
///   The first report after connecting only shows the initial state.
///   Press type (observed on an RD-R8150; Shimano describes D-Fly as supporting single press,
///   hold and double press): exactly one of the bits 0x10 / 0x20 / 0x40 is set
///   (0x10 = single, 0x40 = double, 0x20 = hold), the lower 4 bits count up.
///   Without one of these bits the button counts as released.
final class Di2Client: NSObject, ObservableObject {
    enum PressKind: String { case short, long, double, released }

    static let dflyService = CBUUID(string: "000018EF-5348-494D-414E-4F5F424C4500")
    static let configService = CBUUID(string: "000018FF-5348-494D-414E-4F5F424C4500")
    static let dflyChannelChar = CBUUID(string: "00002AC2-5348-494D-414E-4F5F424C4500")

    struct Found: Identifiable, Hashable {
        let id: UUID
        let name: String
        let rssi: Int
    }

    @Published var bluetoothReady = false
    @Published var scanning = false
    @Published var found: [Found] = []
    @Published var connectedName: String?
    @Published var status = LText(.stNotConnected)
    /// Time of the last press per channel (for the indicator lights).
    @Published var lastPress: [Int: Date] = [:]

    /// (channel 1…4, press type)
    var onPress: ((Int, PressKind) -> Void)?
    var log: ((String) -> Void)?

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var lastValues: [Int: UInt8] = [:]
    private var lastKinds: [Int: PressKind] = [:]
    private var initialized = false
    private var wantConnected = false

    private let savedKey = "lastDi2Identifier"

    override init() {
        super.init()
        #if SNAPSHOT
        return // preview renderer: no Bluetooth at all (no permission prompt)
        #endif
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func startScan() {
        guard central.state == .poweredOn else { return }
        found = []
        scanning = true
        status = LText(.stScanning)
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    func stopScan() {
        central.stopScan()
        scanning = false
    }

    func connect(_ id: UUID) {
        guard let p = peripherals[id] ?? central.retrievePeripherals(withIdentifiers: [id]).first else { return }
        stopScan()
        wantConnected = true
        peripheral = p
        p.delegate = self
        status = LText(.stConnecting, p.name ?? "Di2")
        UserDefaults.standard.set(id.uuidString, forKey: savedKey)
        central.connect(p)
    }

    func disconnect() {
        wantConnected = false
        if let p = peripheral { central.cancelPeripheralConnection(p) }
    }

    private static func looksLikeDi2(name: String?, services: [CBUUID]) -> Bool {
        if services.contains(dflyService) || services.contains(configService) { return true }
        guard let n = name?.uppercased() else { return false }
        return n.hasPrefix("RDR") || n.hasPrefix("EWWU") || n.hasPrefix("RD-R")
    }

    // MARK: D-Fly decoding

    private func handle(_ bytes: [UInt8]) {
        guard bytes.count > 1 else { return }
        let channels = Array(bytes.dropFirst())

        // Initial state: the first report after connecting triggers nothing. Exception: a channel
        // already shows the first press of this connection (counter = 1), then it was a real press.
        if !initialized {
            initialized = true
            var fresh = false
            for (i, v) in channels.enumerated() {
                lastKinds[i] = .released
                if Self.kind(of: v) != .released && v & 0x0F == 1 {
                    fresh = true
                } else {
                    lastValues[i] = v
                }
            }
            if !fresh { return }
        }

        for (i, v) in channels.enumerated() where lastValues[i] != v {
            lastValues[i] = v
            let ch = i + 1
            let kind = Self.kind(of: v)
            // While a button is held, more reports may arrive – that is not a new press.
            if kind == .short && lastKinds[i] == .long { continue }
            lastKinds[i] = kind
            if kind != .released { lastPress[ch] = Date() }
            log?(String(format: "Di2 D-Fly channel %d: %@ (0x%02X)", ch, kind.rawValue, v))
            onPress?(ch, kind)
        }
    }

    /// Press type: exactly one of the bits 0x10/0x20/0x40 must be set, otherwise the button counts as released.
    static func kind(of v: UInt8) -> PressKind {
        switch v & 0x70 {
        case 0x10: return .short
        case 0x20: return .long
        case 0x40: return .double
        default: return .released
        }
    }
}

extension Di2Client: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothReady = central.state == .poweredOn
        switch central.state {
        case .poweredOn:
            status = LText(.stBluetoothReady)
            // Reconnect to the last used Di2 automatically
            if let s = UserDefaults.standard.string(forKey: savedKey), let id = UUID(uuidString: s),
               let p = central.retrievePeripherals(withIdentifiers: [id]).first {
                peripherals[id] = p
                connect(id)
            } else {
                startScan()
            }
        case .unauthorized: status = LText(.stBluetoothUnauthorized)
        case .poweredOff: status = LText(.stBluetoothOff)
        default: status = LText(.stBluetoothUnavailable)
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String
        guard Self.looksLikeDi2(name: name, services: services) else { return }
        peripherals[peripheral.identifier] = peripheral
        if !found.contains(where: { $0.id == peripheral.identifier }) {
            found.append(Found(id: peripheral.identifier, name: name ?? "Di2", rssi: RSSI.intValue))
            log?("Di2 found: \(name ?? "?")")
            // Exactly one found -> connect right away
            if found.count == 1 && peripheral.state == .disconnected && self.peripheral == nil {
                connect(peripheral.identifier)
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = LText(.stReadingServices)
        initialized = false
        connectedName = peripheral.name ?? "Di2"
        log?("Bluetooth connected: \(connectedName!)")
        peripheral.discoverServices([Self.dflyService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        let reason = error?.localizedDescription ?? "?"
        status = LText(.stConnectFailed, reason)
        log?("Di2 connection failed: \(reason)")
        retry(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connectedName = nil
        status = LText(.stDisconnected)
        log?("Di2 disconnected\(error.map { ": \($0.localizedDescription)" } ?? "")")
        retry(peripheral)
    }

    private func retry(_ p: CBPeripheral) {
        guard wantConnected else { return }
        // The Di2 likes to fall asleep: a pending connect makes CoreBluetooth reconnect as soon as it wakes up.
        status = LText(.stWaitingForDi2)
        central.connect(p)
    }
}

extension Di2Client: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = peripheral.services?.first(where: { $0.uuid == Self.dflyService }) else {
            status = LText(.stNoDfly)
            log?("D-Fly service not found")
            return
        }
        peripheral.discoverCharacteristics([Self.dflyChannelChar], for: s)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let c = service.characteristics?.first(where: { $0.uuid == Self.dflyChannelChar }) else {
            status = LText(.stNoChannels)
            log?("D-Fly channel characteristic not found")
            return
        }
        peripheral.setNotifyValue(true, for: c)
        peripheral.readValue(for: c)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            status = LText(.stSubscribeFailed, error.localizedDescription)
            log?("Subscribing to D-Fly failed: \(error.localizedDescription)")
        } else {
            status = LText(.stReady)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.dflyChannelChar, let data = characteristic.value else { return }
        handle([UInt8](data))
    }
}
