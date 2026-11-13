import SwiftUI

/// The circular completion control: a hairline ring that fills and draws a
/// checkmark when completed, or fills its right half while in progress.
struct Checkbox: View {
    let isOn: Bool
    var isInProgress = false
    let isHighlighted: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(strokeColor, lineWidth: 1.25)
                    .opacity(isOn ? 0 : 1)
                HalfCircleShape()
                    .fill(Theme.checkboxFill)
                    .padding(3)
                    .opacity(isInProgress && !isOn ? 1 : 0)
                Circle()
                    .fill(Theme.checkboxFill)
                    .scaleEffect(isOn ? 1 : 0.6)
                    .opacity(isOn ? 1 : 0)
                CheckmarkShape()
                    .trim(from: 0, to: isOn ? 1 : 0)
                    .stroke(Theme.checkmark, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 8.5, height: 6.5)
                    .offset(y: 0.25)
            }
            .frame(width: Theme.checkboxSize, height: Theme.checkboxSize)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: isOn)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isInProgress)
            .padding(4) // comfortable hit target without changing the drawn size
            .contentShape(Circle().inset(by: -2))
        }
        .buttonStyle(.plain)
        .padding(-4)
        .onHover { isHovering = $0 }
        .accessibilityLabel(isOn ? "Mark incomplete" : "Complete")
    }

    private var strokeColor: Color {
        isHovering || isHighlighted ? Theme.checkboxStrokeHover : Theme.checkboxStroke
    }
}

/// The right half of a circle, for the in-progress state.
struct HalfCircleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addArc(center: center, radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        path.closeSubpath()
        return path
    }
}

struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.36, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
