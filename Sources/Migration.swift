// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 soerenpopoeren
// Shifty – use a Shimano Di2 to shift in Zwift and MyWhoosh. See LICENSE and CREDITS.md.

import Foundation

/// Shifty's bundle identifier changed from "local.shifty.di2bridge" to "io.github.soerenpopoeren.shifty".
/// On the first start with the new identifier, take over the settings of the old one (button mapping,
/// gears, language, Di2, device ID …), so nothing has to be set up again.
enum Migration {
    private static let oldDomain = "local.shifty.di2bridge"
    private static var done = false

    static func run() {
        guard !done else { return }
        done = true
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "migratedFromOldIdentifier"),
              let old = UserDefaults.standard.persistentDomain(forName: oldDomain), !old.isEmpty else { return }
        for (key, value) in old where defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: "migratedFromOldIdentifier")
    }
}
