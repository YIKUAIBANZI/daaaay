import SwiftUI
import AppKit
import DayCore

struct ScrollTimePicker: View {
    let label: String
    @Binding var value: String
    @State private var hour = 9
    @State private var minute = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Text(label).font(.headline).foregroundStyle(DaylightTheme.ink)
            HStack(spacing: 8) {
                column("小时", values: Array(0...23), selection: $hour)
                Text(":").font(.title2).foregroundStyle(DaylightTheme.slate)
                column("分钟", values: Array(stride(from: 0, through: 55, by: 5)), selection: $minute)
            }
            Text("滚动选择 · ↑ ↓ 微调 · 翻页键快调 · 可直接输入")
                .font(.caption).foregroundStyle(DaylightTheme.slate)
            Button { commit(); dismiss() } label: {
                Text("使用 \(String(format: "%02d:%02d", hour, minute))").frame(minHeight: DaylightTheme.primaryHeight)
            }
                .accessibilityLabel("使用\(label) \(hour)点\(minute)分")
        }
        .padding(20).background(DaylightTheme.surface)
        .onAppear {
            let parts = value.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 { hour = parts[0]; minute = min(55, ((parts[1] + 2) / 5) * 5) }
        }
    }

    private func column(_ title: String, values: [Int], selection: Binding<Int>) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(DaylightTheme.slate)
            TimeWheel(values: values, selection: Binding(get: { selection.wrappedValue }, set: {
                selection.wrappedValue = $0
                commit()
            }), label: "\(label)\(title)", spokenValue: "\(label) \(hour) 点 \(minute) 分")
                .frame(width: 84, height: 160)
        }
    }

    private func commit() { value = String(format: "%02d:%02d", hour, minute) }
}

private struct TimeWheel: NSViewRepresentable {
    let values: [Int]
    @Binding var selection: Int
    let label: String
    let spokenValue: String

    func makeNSView(context: Context) -> TimeWheelView { TimeWheelView(frame: .zero) }
    func updateNSView(_ view: TimeWheelView, context: Context) {
        view.values = values; view.selected = selection
        view.onSelect = { selection = $0 }
        view.spokenValue = spokenValue
        view.setAccessibilityLabel(label)
        view.needsDisplay = true
    }
}

/// A focusable AppKit wheel keeps keyboard and precise trackpad behavior consistent on macOS 13.
final class TimeWheelView: NSView {
    var values: [Int] = Array(0...23)
    var selected = 0
    var onSelect: ((Int) -> Void)?
    var spokenValue: String?
    private var scrollRemainder: CGFloat = 0
    private var typed = ""
    private var typedAt = Date.distantPast
    private let rowHeight = CGFloat(DaylightTokens.minimumTarget)
    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
    override func resignFirstResponder() -> Bool { typed = ""; needsDisplay = true; return true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill(); bounds.fill()
        let center = NSRect(x: 2, y: bounds.midY - rowHeight / 2, width: bounds.width - 4, height: rowHeight)
        NSColor(Color(hex: DaylightTokens.actionHex)).withAlphaComponent(0.09).setFill()
        NSBezierPath(roundedRect: center, xRadius: 8, yRadius: 8).fill()
        let index = values.firstIndex(of: selected) ?? values.indices.min(by: { abs(values[$0] - selected) < abs(values[$1] - selected) }) ?? 0
        for offset in -2...2 {
            let i = index + offset
            guard values.indices.contains(i) else { continue }
            let text = String(format: "%02d", values[i]) as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: offset == 0 ? 19 : 16, weight: offset == 0 ? .semibold : .regular),
                .foregroundColor: NSColor(Color(hex: offset == 0 ? DaylightTokens.inkHex : DaylightTokens.slateHex))
            ]
            let size = text.size(withAttributes: attrs)
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                 y: bounds.midY + CGFloat(offset) * rowHeight - size.height / 2), withAttributes: attrs)
        }
        if window?.firstResponder === self {
            NSColor(Color(hex: DaylightTokens.actionHex)).setStroke()
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9)
            outline.lineWidth = 2; outline.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let offset = Int(floor((point.y - bounds.midY + rowHeight / 2) / rowHeight))
        step(offset)
    }

    override func scrollWheel(with event: NSEvent) {
        consumeScroll(delta: event.scrollingDeltaY, precise: event.hasPreciseScrollingDeltas)
    }

    func consumeScroll(delta: CGFloat, precise: Bool) {
        typed = ""
        scrollRemainder -= delta
        let threshold: CGFloat = precise ? 12 : 1
        let rows = Int(scrollRemainder / threshold)
        if rows != 0 { scrollRemainder -= CGFloat(rows) * threshold; step(rows) }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126: typed = ""; step(-1)
        case 125: typed = ""; step(1)
        case 116: typed = ""; step(-5)
        case 121: typed = ""; step(5)
        case 48:
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
        default:
            guard let characters = event.characters, !characters.isEmpty,
                  characters.allSatisfy({ $0.isASCII && $0.isNumber }),
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
                super.keyDown(with: event); return
            }
            if Date().timeIntervalSince(typedAt) > 1 || typed.count >= 2 { typed = "" }
            typed += characters; typedAt = Date()
            guard let number = Int(typed), number <= (values.count == 12 ? 59 : 23) else {
                typed = ""; NSSound.beep(); return
            }
            // Typed minutes use the same five-minute vocabulary as the wheel; 58/59 clamp to 55
            // so direct input cannot silently move the hour or date.
            let normalized = values.count == 12 ? min(55, ((number + 2) / 5) * 5) : number
            select(normalized)
        }
    }

    private func step(_ rows: Int) {
        guard !values.isEmpty else { return }
        let index = values.firstIndex(of: selected) ?? values.indices.min(by: { abs(values[$0] - selected) < abs(values[$1] - selected) }) ?? 0
        select(values[min(values.count - 1, max(0, index + rows))])
    }
    private func select(_ value: Int) {
        selected = value; onSelect?(value); needsDisplay = true
        NSAccessibility.post(element: self, notification: .valueChanged)
    }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .incrementor }
    override func accessibilityValue() -> Any? { spokenValue ?? String(format: "%02d", selected) }
    override func accessibilityPerformIncrement() -> Bool { step(1); return true }
    override func accessibilityPerformDecrement() -> Bool { step(-1); return true }
}
