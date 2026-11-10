// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 soerenpopoeren
// Shifty – use a Shimano Di2 to shift in Zwift and MyWhoosh. See LICENSE and CREDITS.md.

import Foundation

/// Zwift controller protocol (as spoken by a Zwift Click v2), used by the Wi-Fi (DirCon) output.
/// Sources: see CREDITS.md (swiftcontrol / BikeControl GPL versions, qdomyos-zwift) and our own
/// measurement of a real Zwift Click v2 pair (Tools/ZwiftProbe).
enum ZwiftProtocol {
    /// Button bits as a real Zwift Click v2 sends them (measured with Tools/ZwiftProbe; same table as
    /// swiftcontrol's ride_notification.dart). Left shifter = easier, right shifter = harder.
    enum Button: UInt32 {
        case steerLeft = 0x1, openActionBar = 0x2, steerRight = 0x4, uturn = 0x8
        case a = 0x10, b = 0x20, y = 0x40, z = 0x80
        case shiftUpLeft = 0x100, shiftDownLeft = 0x200
        case shiftUpRight = 0x1000, shiftDownRight = 0x2000
        case powerUpLeft = 0x400, powerUpRight = 0x4000
    }

    static let rideOn: [UInt8] = Array("RideOn".utf8)
    /// A real Zwift Click v2 answers the handshake with "RideOn" + 02 03.
    static let rideOnResponse: [UInt8] = rideOn + [0x02, 0x03]
    /// Device type as reported by Zwift Click v2: 0x0A and 0x0B (one per side).
    static let deviceType: UInt64 = 0x0A
    static let controllerNotification: UInt8 = 0x23
    static let getResponse: UInt8 = 0x3C

    /// [0x23, protobuf{1: buttonMap}]. The map is inverted: bit = 0 means pressed.
    static func buttons(_ pressedMask: UInt32) -> [UInt8] {
        [controllerNotification] + field(1, varint: UInt64(~pressedMask))
    }

    /// GET request from Zwift: [0x00, protobuf{1: object id}] → object id, or nil.
    static func getRequestID(_ data: [UInt8]) -> Int? {
        guard data.first == 0x00, data.count >= 3, data[1] == 0x08 else { return nil }
        return Int(readVarint(Array(data[2...])))
    }

    /// GET_RESPONSE (0x3C). Object 0 is the device information, built exactly like the answer of a
    /// real Zwift Click v2 (measured with Tools/ZwiftProbe); other objects get no answer, like on the
    /// real device.
    static func getResponse(for id: Int) -> [UInt8]? {
        guard id == 0 else { return nil }
        let content: [UInt8] =
            field(1, varint: 515)
            + field(2, bytes: [0x00, 0x00, 0x01, 0x01])                // software version
            + field(3, bytes: Array("Zwift Click".utf8))               // device name
            + field(6, bytes: Array(serial.utf8))
            + field(7, bytes: Array("B.0".utf8))                       // hardware version
            + field(8, bytes: field(1, varint: 2) + field(2, varint: 1))
            + field(9, varint: 1)
            + field(10, varint: deviceType)
            + field(11, bytes: Array(serialShort.utf8))
        return [getResponse] + field(1, varint: UInt64(id)) + field(2, bytes: field(1, bytes: content))
    }

    /// Serial like a real Click: "<type>-<12 hex digits>".
    static var serial: String { String(format: "%02X-", deviceType) + serialShort }
    static var serialShort: String { ("5348494654" + Identity.shared.deviceID).suffix(12).uppercased() }

    // MARK: Protobuf helpers

    static func varint(_ value: UInt64) -> [UInt8] {
        var v = value, out: [UInt8] = []
        repeat {
            var b = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { b |= 0x80 }
            out.append(b)
        } while v != 0
        return out
    }

    static func readVarint(_ b: [UInt8]) -> UInt64 {
        var v: UInt64 = 0, shift: UInt64 = 0
        for byte in b {
            v |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { break }
            shift += 7
        }
        return v
    }

    static func field(_ n: UInt64, varint v: UInt64) -> [UInt8] { varint(n << 3) + varint(v) }
    static func field(_ n: UInt64, bytes b: [UInt8]) -> [UInt8] { varint(n << 3 | 2) + varint(UInt64(b.count)) + b }

    static func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
}
