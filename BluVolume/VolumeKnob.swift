import SwiftUI
import UIKit

/// A rotary volume knob. You turn it by moving your finger around its centre;
/// the full volume range takes several rotations, so small steps are easy.
struct VolumeKnob: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    /// Degrees of rotation per percent of volume.
    var degreesPerStep: Double
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var lastAngle: Double?
    @State private var isDragging = false
    @State private var lastHapticLevel: Int?
    @State private var wasAtLimit = false
    @State private var haptics = KnobHaptics()

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let ringWidth = size * 0.035

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: ringWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(isDragging ? nil : .easeOut(duration: 0.25), value: fraction)

                KnobFace(rotation: .degrees(value * degreesPerStep), isActive: isDragging)
                    .padding(ringWidth * 2.2)
                    .animation(isDragging ? nil : .easeOut(duration: 0.25), value: value)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(dragGesture(center: center, size: size))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(value.rounded())) procent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value.rounded() + 1, range.upperBound)
            case .decrement: value = max(value.rounded() - 1, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (value - range.lowerBound) / span
    }

    private func dragGesture(center: CGPoint, size: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                if !isDragging {
                    isDragging = true
                    lastHapticLevel = Int(value.rounded())
                    haptics.prepare()
                    onEditingChanged(true)
                }

                let dx = gesture.location.x - center.x
                let dy = gesture.location.y - center.y
                // Near the centre the angle jumps wildly; ignore that zone.
                guard hypot(dx, dy) > size * 0.12 else {
                    lastAngle = nil
                    return
                }

                // Screen y points down, so atan2 grows clockwise: clockwise = louder.
                let angle = atan2(dy, dx) * 180 / .pi
                defer { lastAngle = angle }
                guard let last = lastAngle else { return }

                var delta = angle - last
                if delta > 180 { delta -= 360 } else if delta < -180 { delta += 360 }

                let change = KnobSensitivity.volumeDelta(
                    forDegrees: delta, currentVolume: value, degreesPerStep: degreesPerStep)
                let newValue = min(max(value + change, range.lowerBound), range.upperBound)

                let newLevel = Int(newValue.rounded())
                if newLevel != lastHapticLevel {
                    haptics.tick()
                    lastHapticLevel = newLevel
                }
                let atLimit = newValue <= range.lowerBound || newValue >= range.upperBound
                if atLimit && !wasAtLimit { haptics.limit() }
                wasAtLimit = atLimit

                value = newValue
            }
            .onEnded { _ in
                lastAngle = nil
                isDragging = false
                wasAtLimit = false
                onEditingChanged(false)
            }
    }
}

/// The physical-looking knob: a dark disc with knurled edge and an indicator dot.
private struct KnobFace: View {
    var rotation: Angle
    var isActive: Bool

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.10)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.6), radius: d * 0.05, y: d * 0.03)

                // Knurled edge: these rotate with the knob, so even a tiny turn is visible.
                ZStack {
                    ForEach(0..<60, id: \.self) { i in
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                            .frame(width: max(1.5, d * 0.006), height: d * 0.05)
                            .offset(y: -d * 0.445)
                            .rotationEffect(.degrees(Double(i) * 6))
                    }
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: d * 0.055, height: d * 0.055)
                        .shadow(color: Color.accentColor.opacity(isActive ? 0.9 : 0.4), radius: d * 0.02)
                        .offset(y: -d * 0.34)
                }
                .rotationEffect(rotation)

                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.24)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: d * 0.56, height: d * 0.56)
                    .overlay(Circle().stroke(Color.white.opacity(0.06), lineWidth: 1))
            }
            .frame(width: d, height: d)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Holds the feedback generators so they survive view re-renders.
private final class KnobHaptics {
    private let selection = UISelectionFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .rigid)

    func prepare() {
        selection.prepare()
        impact.prepare()
    }

    /// One click per percent, like a detented hi-fi knob.
    func tick() {
        selection.selectionChanged()
        selection.prepare()
    }

    /// A firmer bump when you hit 0 % or the volume cap.
    func limit() {
        impact.impactOccurred()
        impact.prepare()
    }
}
