// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 soerenpopoeren
// Shifty – use a Shimano Di2 to shift in Zwift and MyWhoosh. See LICENSE and CREDITS.md.

import AppKit
import SwiftUI

/// Settings window in the same glass look as the menu bar window.
struct SettingsView: View {
    @EnvironmentObject var bridge: Bridge
    @ObservedObject private var loc = Localizer.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                gearCard
                mappingCards
                LogCard()
            }
            .padding(.horizontal, 24)
            .padding(.top, 34) // room for the window buttons
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(SettingsBackground())
        .navigationTitle(t(.settingsTitle))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 58, height: 58)
                .padding(-6)
                .shadow(color: Color.shimano.opacity(0.25), radius: 10, y: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("Shifty").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Shimano Di2 → Zwift · MyWhoosh")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Text(t(.version, Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?") + " · Beta")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer()
            Di2StatusPill()
            Menu {
                Picker(t(.language), selection: $loc.language) {
                    ForEach(Language.allCases) { Text($0.nativeName).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label(loc.language == .system ? t(.systemLanguage) : loc.language.nativeName, systemImage: "globe")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .glossy(cornerRadius: 14)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            .help(t(.language))
        }
    }

    // MARK: Button mapping

    private var mappingCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                SectionLabel(title: t(.mapping), symbol: "slider.horizontal.3")
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .help(t(.mappingFooter))
            }
            ShiftersCard()
            HStack(alignment: .top, spacing: 12) {
                holdTile
                miniTile
            }
        }
    }

    private var holdTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "repeat").foregroundStyle(Color.shimano)
                Text(t(.holdRepeat)).font(.system(size: 13, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                Toggle("", isOn: $bridge.repeatOnHold).toggleStyle(.switch).labelsHidden().tint(Color.shimano)
            }
            Text(t(.holdHelp)).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glossy(cornerRadius: 16)
    }

    /// Floating mini display: on/off, and below it how transparent its glass background is.
    private var miniTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "pip").foregroundStyle(Color.shimano)
                Text(t(.miniDisplay)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                Toggle("", isOn: $bridge.showMini).toggleStyle(.switch).labelsHidden().tint(Color.shimano)
            }
            Text(t(.transparency)).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Slider(value: $bridge.miniTransparency, in: 0...1).tint(Color.shimano)
                Text("\(Int((bridge.miniTransparency * 100).rounded())) %")
                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                    .lineLimit(1).fixedSize()
                    .frame(width: 40, alignment: .trailing)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glossy(cornerRadius: 16)
    }

    // MARK: Gear

    /// One flat row: gear, bar, -/+, sync buttons and a "?" with the explanation.
    private var gearCard: some View {
        SettingsCard(title: t(.gear), symbol: "gearshape.2") {
            HStack(spacing: 12) {
                GearReel(gear: bridge.gear, maxGear: bridge.maxGear, height: 34)
                    .frame(width: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(t(.ofMax, "\(bridge.maxGear)"))
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    GearBars(gear: bridge.gear, maxGear: bridge.maxGear).frame(height: 10)
                }
                .frame(minWidth: 120)
                RoundIconButton(symbol: "minus", size: 28) { bridge.setGear(bridge.gear - 1) }
                RoundIconButton(symbol: "plus", size: 28) { bridge.setGear(bridge.gear + 1) }
                SyncButton(app: "zwift", fallback: "Z", enabled: bridge.zwiftConnected && !bridge.syncing)
                SyncButton(app: "mywhoosh", fallback: "MW", enabled: bridge.mywhoosh.clients > 0 && !bridge.syncing)
                if bridge.syncing { ProgressView().controlSize(.small) }
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                    .help(t(.syncHelp))
            }
        }
    }
}

/// Small Di2 status in the header: green dot + name when connected. Click for search/connect/disconnect.
private struct Di2StatusPill: View {
    @EnvironmentObject var bridge: Bridge
    @ObservedObject private var loc = Localizer.shared

    var body: some View {
        let di2 = bridge.di2
        let on = di2.connectedName != nil
        Menu {
            Text(loc.t(di2.status))
            Divider()
            if on {
                Button(t(.disconnect)) { di2.disconnect() }
            } else {
                Button(di2.scanning ? t(.stop) : t(.search)) { di2.scanning ? di2.stopScan() : di2.startScan() }
                    .disabled(!di2.bluetoothReady)
                ForEach(di2.found) { f in
                    Button("\(t(.connect)): \(f.name)") { di2.connect(f.id) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(on ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                    .shadow(color: on ? Color.green.opacity(0.7) : .clear, radius: 3)
                Text(di2.connectedName ?? t(.noDi2)).font(.system(size: 12, weight: .medium)).lineLimit(1)
                if di2.scanning { ProgressView().controlSize(.mini) }
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .glossy(cornerRadius: 14)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(loc.t(di2.status))
    }
}

// MARK: - Building blocks

/// Soft cyan glow behind the content, so the glass cards have something to refract.
private struct SettingsBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(colors: [Color.shimano.opacity(0.16), .clear], center: .topLeading,
                           startRadius: 0, endRadius: 420)
            RadialGradient(colors: [Color.shimanoLight.opacity(0.10), .clear], center: .bottomTrailing,
                           startRadius: 0, endRadius: 480)
        }
        .ignoresSafeArea()
    }
}

private struct SectionLabel: View {
    let title: String
    let symbol: String
    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 4)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: title, symbol: symbol)
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glossy(cornerRadius: 18)
        }
    }
}

/// Capsule button; "prominent" is filled with Shimano cyan.
struct PillButton: View {
    let title: String
    var prominent = false
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .background {
                    if prominent {
                        Capsule().fill(LinearGradient(colors: [.shimanoLight, .shimano], startPoint: .top, endPoint: .bottom))
                    }
                }
                .background { if !prominent { Capsule().fill(Color.secondary.opacity(0.12)) } }
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
    }
}

private struct RoundIconButton: View {
    let symbol: String
    var size: CGFloat = 34
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .frame(width: size, height: size)
                .glossy(cornerRadius: size / 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct ActionMenu: View {
    @EnvironmentObject var bridge: Bridge
    let channel: Int
    /// Compact: smaller, without the chevron (used next to the shifter drawing).
    var compact = false

    var body: some View {
        let action = bridge.mapping[channel] ?? Action.none
        Menu {
            ForEach(Action.allCases) { a in
                Button { bridge.mapping[channel] = a } label: { Label(a.title, systemImage: Self.symbol(a)) }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: Self.symbol(action))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(action == .none ? Color.secondary : Color.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(action == .none ? AnyShapeStyle(Color.secondary.opacity(0.15))
                                                              : AnyShapeStyle(LinearGradient(colors: [.shimanoLight, .shimano],
                                                                                            startPoint: .top, endPoint: .bottom))))
                Text(Self.short(action)).font(.system(size: compact ? 11 : 12, weight: .medium)).lineLimit(1)
                if !compact {
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 4).padding(.trailing, compact ? 8 : 10).padding(.vertical, compact ? 3 : 4)
            .background(Capsule().fill(Color.secondary.opacity(0.1)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    static func symbol(_ a: Action) -> String {
        switch a {
        case .none: return "circle.dashed"
        case .shiftUp: return "plus"
        case .shiftDown: return "minus"
        case .uturn: return "arrow.uturn.left"
        }
    }

    static func short(_ a: Action) -> String {
        switch a {
        case .none: return t(.nothing)
        case .shiftUp: return t(.harder)
        case .shiftDown: return t(.easier)
        case .uturn: return t(.actionUturn)
        }
    }
}

private struct SyncButton: View {
    @EnvironmentObject var bridge: Bridge
    let app: String
    let fallback: String
    let enabled: Bool

    var body: some View {
        Button { bridge.sync(app) } label: {
            HStack(spacing: 6) {
                LogoView(key: app, fallback: fallback, size: 18)
                Text(Bridge.appName(app)).font(.system(size: 11, weight: .semibold))
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10)).foregroundStyle(Color.shimano)
            }
            .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 4)
            .background(Capsule().fill(Color.secondary.opacity(0.1)))
            .contentShape(Capsule())
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(t(.syncWith, Bridge.appName(app)))
    }
}

/// Lights up briefly in cyan when the channel's button was pressed.
struct ChannelLamp: View {
    let last: Date?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { ctx in
            let lit = last.map { ctx.date.timeIntervalSince($0) < 0.4 } ?? false
            Circle()
                .fill(lit ? Color.shimano : Color.secondary.opacity(0.25))
                .frame(width: 10, height: 10)
                .shadow(color: lit ? Color.shimano.opacity(0.9) : .clear, radius: 5)
        }
    }
}

/// Collapsible log with copy and "show in Finder".
private struct LogCard: View {
    @EnvironmentObject var bridge: Bridge
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { withAnimation(.easeInOut(duration: 0.2)) { open.toggle() } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(open ? 90 : 0))
                        SectionLabel(title: t(.logTitle), symbol: "doc.text.magnifyingglass")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                if open {
                    PillButton(title: t(.copy)) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(bridge.logLines.joined(separator: "\n"), forType: .string)
                    }
                    PillButton(title: t(.showInFinder)) {
                        NSWorkspace.shared.activateFileViewerSelecting([Bridge.logFile])
                    }
                }
            }
            if open {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(bridge.logLines.enumerated()), id: \.offset) { i, line in
                                Text(line).font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.secondary).textSelection(.enabled).id(i)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 160)
                    .glossy(cornerRadius: 14)
                    .onAppear { if let n = bridge.logLines.indices.last { proxy.scrollTo(n, anchor: .bottom) } }
                    .onChange(of: bridge.logLines.count) { _, n in
                        if n > 0 { proxy.scrollTo(n - 1, anchor: .bottom) }
                    }
                }
                .transition(.opacity)
            }
        }
    }
}
