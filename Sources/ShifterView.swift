// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 soerenpopoeren
// Shifty – use a Shimano Di2 to shift in Zwift and MyWhoosh. See LICENSE and CREDITS.md.

import AppKit
import SwiftUI

/// The three buttons of a road shifter, as E-TUBE names them.
enum ShifterButton: String, CaseIterable {
    case a = "A", x = "X", y = "Y"

    var title: String {
        switch self {
        case .a: return t(.buttonTop)
        case .x: return t(.leverMain)
        case .y: return t(.leverSmall)
        }
    }

    /// Where the leader line starts, relative to the drawing of the right-hand shifter.
    var anchor: CGPoint {
        switch self {
        case .a: return CGPoint(x: 0.855, y: 0.065)
        case .x: return CGPoint(x: 0.575, y: 0.60)
        case .y: return CGPoint(x: 0.40, y: 0.72)
        }
    }

    /// Vertical position of the label row (0…1).
    var rowY: CGFloat {
        switch self {
        case .a: return 0.07
        case .x: return 0.52
        case .y: return 0.88
        }
    }
}

/// One part of the shifter drawing (Assets/shifter.svg, converted to ShifterShapes.swift).
/// Drawn for the right hand; the left one is mirrored.
private struct ShifterPart: Shape {
    enum Part: Hashable { case hood, hoodShade, buttonA, leverX, leverY }
    let part: Part

    func path(in r: CGRect) -> Path {
        let vb = ShifterShapes.viewBox
        let s = min(r.width / vb.width, r.height / vb.height)
        let ox = r.midX - vb.width * s / 2, oy = r.midY - vb.height * s / 2
        let p: (CGFloat, CGFloat) -> CGPoint = { CGPoint(x: ox + $0 * s, y: oy + $1 * s) }
        switch part {
        case .hood: return ShifterShapes.hood(p)
        case .hoodShade: return ShifterShapes.ebene4(p)
        case .buttonA: return ShifterShapes.buttonA(p)
        case .leverX: return ShifterShapes.leverX(p)
        case .leverY: return ShifterShapes.leverY(p)
        }
    }
}

/// One card with both shifters side by side: labels outside, drawings in the middle.
struct ShiftersCard: View {
    @EnvironmentObject var bridge: Bridge

    /// Drawing size (aspect ratio of the SVG) and layout of the label rows.
    private let drawH: CGFloat = 120
    private var drawW: CGFloat { drawH * ShifterShapes.viewBox.width / ShifterShapes.viewBox.height }
    private let top: CGFloat = 14
    private let height: CGFloat = 176
    private let gap: CGFloat = 48
    /// Center of each label row (A, X, Y from top to bottom).
    private func rowCenter(_ b: ShifterButton) -> CGFloat {
        switch b {
        case .a: return 22
        case .x: return 88
        case .y: return 152
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(t(.left)).font(.system(size: 14, weight: .semibold))
                Spacer()
                Text(t(.right)).font(.system(size: 14, weight: .semibold))
            }
            TimelineView(.periodic(from: .now, by: 0.05)) { ctx in
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        side("L", width: geo.size.width, now: ctx.date)
                        side("R", width: geo.size.width, now: ctx.date)
                    }
                }
            }
            .frame(height: height)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glossy(cornerRadius: 18)
    }

    private func key(_ side: String, _ b: ShifterButton) -> String { "\(side).\(b.rawValue)" }

    private func isLit(_ side: String, _ b: ShifterButton, _ now: Date) -> Bool {
        guard let ch = bridge.buttonChannels[key(side, b)], let last = bridge.di2.lastPress[ch] else { return false }
        return now.timeIntervalSince(last) < 0.45
    }

    @ViewBuilder
    private func side(_ side: String, width w: CGFloat, now: Date) -> some View {
        let isLeft = side == "L"
        // Both drawings sit in the middle, the left one mirrored, horns pointing outwards
        let drawX = isLeft ? w / 2 - gap / 2 - drawW : w / 2 + gap / 2
        let labelW = w / 2 - gap / 2 - drawW - 18
        let labelX = isLeft ? 0 : w - labelW

        // Leader lines
        Path { path in
            for b in ShifterButton.allCases {
                let ax = isLeft ? 1 - b.anchor.x : b.anchor.x
                let start = CGPoint(x: drawX + ax * drawW, y: top + b.anchor.y * drawH)
                let y = rowCenter(b)
                let endX = isLeft ? labelW + 4 : w - labelW - 4
                let bendX = isLeft ? endX + 6 : endX - 6
                path.move(to: start)
                path.addLine(to: CGPoint(x: bendX, y: y))
                path.addLine(to: CGPoint(x: endX, y: y))
            }
        }
        .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, lineCap: .round))

        drawing(side, now: now)
            .frame(width: drawW, height: drawH)
            .scaleEffect(x: isLeft ? -1 : 1, y: 1)
            .offset(x: drawX, y: top)

        ForEach(ShifterButton.allCases, id: \.self) { b in
            ButtonRow(key: key(side, b), button: b, lit: isLit(side, b, now), alignTrailing: isLeft)
                .frame(width: labelW, alignment: isLeft ? .trailing : .leading)
                .offset(x: labelX, y: rowCenter(b) - 22)
        }
    }

    /// All outlines share one width and are drawn as a single layer that is made semi-transparent
    /// as a whole – so where two outlines overlap they don't add up and look thicker.
    private static let lineStyle = StrokeStyle(lineWidth: 0.9, lineCap: .round, lineJoin: .round)

    private func drawing(_ side: String, now: Date) -> some View {
        ZStack {
            // Fills (and the glow of a pressed part), in the order of the SVG
            ShifterPart(part: .hood).fill(Color.secondary.opacity(0.10))
            fill(.leverX, base: 0.22, lit: isLit(side, .x, now))
            fill(.leverY, base: 0.45, lit: isLit(side, .y, now))
            fill(.buttonA, base: 0.22, lit: isLit(side, .a, now))
            ShifterPart(part: .hoodShade).fill(Color.secondary.opacity(0.06))

            // All outlines as one layer on top, so they stay visible over the glow
            ZStack {
                ForEach([ShifterPart.Part.leverX, .leverY, .buttonA, .hoodShade, .hood], id: \.self) { p in
                    ShifterPart(part: p).stroke(Color.primary, style: Self.lineStyle)
                }
            }
            .compositingGroup()
            .opacity(0.6)
        }
    }

    /// Fill of a part. When lit: Shimano cyan with a glow.
    private func fill(_ p: ShifterPart.Part, base: Double, lit: Bool) -> some View {
        ShifterPart(part: p)
            .fill(lit ? AnyShapeStyle(LinearGradient(colors: [.shimanoLight, .shimano], startPoint: .top, endPoint: .bottom))
                      : AnyShapeStyle(Color.secondary.opacity(base)))
            .shadow(color: lit ? Color.shimano.opacity(0.9) : .clear, radius: lit ? 9 : 0)
            .animation(.easeOut(duration: 0.15), value: lit)
    }
}

/// One button's label: letter, name, D-Fly channel and the channel's action.
private struct ButtonRow: View {
    @EnvironmentObject var bridge: Bridge
    let key: String
    let button: ShifterButton
    let lit: Bool
    let alignTrailing: Bool

    var body: some View {
        let channel = bridge.buttonChannels[key]
        let learningThis = bridge.learning == key
        VStack(alignment: alignTrailing ? .trailing : .leading, spacing: 4) {
            HStack(spacing: 5) {
                if alignTrailing {
                    Text(button.title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    letter
                } else {
                    letter
                    Text(button.title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            if learningThis {
                HStack(spacing: 6) {
                    Text(t(.pressNow)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.shimano)
                    Button(t(.cancel)) { bridge.learning = nil }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .lineLimit(1).minimumScaleFactor(0.8)
            } else {
                HStack(spacing: 5) {
                    ChannelMenu(key: key, channel: channel)
                    if let channel { ActionMenu(channel: channel, compact: true) }
                }
            }
        }
        .frame(height: 44)
    }

    private var letter: some View {
        Text(button.rawValue)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(lit ? Color.white : Color.secondary)
            .frame(width: 16, height: 16)
            .background(Circle().fill(lit ? AnyShapeStyle(Color.shimano) : AnyShapeStyle(Color.secondary.opacity(0.15))))
            .shadow(color: lit ? Color.shimano.opacity(0.8) : .clear, radius: 6)
    }

}

/// Menu to set a button's D-Fly channel, or to learn it.
private struct ChannelMenu: View {
    @EnvironmentObject var bridge: Bridge
    let key: String
    let channel: Int?

    var body: some View {
        Menu {
            Button { bridge.learning = key } label: { Label(t(.learn), systemImage: "hand.tap") }
            Divider()
            ForEach(1...4, id: \.self) { ch in
                Button { bridge.assign(ch, to: key) } label: {
                    if channel == ch { Label("D-Fly Ch \(ch)", systemImage: "checkmark") } else { Text("D-Fly Ch \(ch)") }
                }
            }
            Divider()
            Button(t(.notDfly)) { bridge.assign(nil, to: key) }
        } label: {
            Text(channel.map { "Ch \($0)" } ?? "–")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(channel == nil ? Color.secondary : Color.shimano)
                .frame(minWidth: 30)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(channel == nil ? Color.secondary.opacity(0.12) : Color.shimano.opacity(0.14)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
