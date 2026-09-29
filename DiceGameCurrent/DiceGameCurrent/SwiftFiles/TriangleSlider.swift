import SwiftUI

/// Right triangle rising from a point at the left up to full height at the
/// right — the wedge shape a volume ramp uses instead of a bar, so louder
/// literally reads as "taller" at a glance.
private struct VolumeWedge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Triangular volume slider: a wedge that fills left-to-right with `tint`
/// as `value` rises, "0"/"100%" labeled at the wedge's own ends — replaces
/// the stock SwiftUI Slider in Settings to match the game's own look.
///
/// No rounded "Volume"-style label pill: it was previously positioned with
/// `.overlay` plus `.offset`, which moves rendered content without
/// enlarging the frame it's measured against — that let the pill's
/// rendered position drift outside this view's own reported layout height
/// and overlap the wedge above it and whatever control sat below it in the
/// Settings form. Rather than re-fit it into the plain sequential layout
/// that replaced that positioning, it's removed outright, per request —
/// the section header above each slider (e.g. "Music Volume") already
/// says what it controls.
///
/// The whole wedge is one drag target rather than a knob-on-a-track: with
/// no visible thumb in the reference art, dragging anywhere sets the value
/// straight to that horizontal position.
struct TriangleSlider: View {
    @Binding var value: Double // 0...1
    var tint: Color

    private let wedgeHeight: CGFloat = 40

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .bottomLeading) {
                    VolumeWedge()
                        .fill(Color.secondary.opacity(0.25))

                    // Draw the SAME full-size wedge every time (so its
                    // diagonal edge always has the correct slope, matching
                    // the track), then reveal only its left `value`
                    // fraction by constraining and clipping the container —
                    // the standard fill-bar technique, adapted so the
                    // "bar" is a diagonal wedge instead of a rectangle.
                    VolumeWedge()
                        .fill(tint)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
                        .frame(width: geo.size.width * value, alignment: .leading)
                        .clipped()
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let fraction = Double(drag.location.x / max(geo.size.width, 1))
                            value = min(max(fraction, 0), 1)
                        }
                )
            }
            .frame(height: wedgeHeight)

            HStack {
                Text("0")
                Spacer()
                Text("100%")
            }
            .font(.poppins(11))
            .foregroundStyle(.secondary)
        }
    }
}
