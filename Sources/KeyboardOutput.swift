// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 soerenpopoeren
// Shifty – use a Shimano Di2 to shift in Zwift and MyWhoosh. See LICENSE and CREDITS.md.

import AppKit
import ApplicationServices

/// Fallback for MyWhoosh on this Mac: simulates the keys I (easier) and K (harder).
/// Requires the "Accessibility" permission.
final class KeyboardOutput: ObservableObject {
    @Published var enabled = false { didSet { if enabled { requestPermission() } } }
    @Published var trusted = AXIsProcessTrusted()

    var log: ((String) -> Void)?

    static let keyI: CGKeyCode = 34
    static let keyK: CGKeyCode = 40

    func requestPermission() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(opts)
    }

    func tap(_ key: CGKeyCode) {
        guard enabled else { return }
        trusted = AXIsProcessTrusted()
        guard trusted else {
            log?("Keyboard: Accessibility permission missing")
            return
        }
        let src = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false) else { return }

        // If MyWhoosh is running, send the key straight to it – then it doesn't have to be in front.
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            ($0.localizedName ?? "").localizedCaseInsensitiveContains("mywhoosh")
                || ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains("mywhoosh")
        }) {
            down.postToPid(app.processIdentifier)
            usleep(30_000)
            up.postToPid(app.processIdentifier)
        } else {
            down.post(tap: .cghidEventTap)
            usleep(30_000)
            up.post(tap: .cghidEventTap)
        }
    }
}
