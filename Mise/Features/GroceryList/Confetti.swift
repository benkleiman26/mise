import SwiftUI

/// For the moment the last thing on the list gets ticked off.
///
/// Drawn rather than brought in: it is forty lines of rectangles falling, and
/// a dependency for that would be a dependency to keep working for the next
/// ten years of iOS releases.
///
/// Silent, brief and untappable. It sits over a screen somebody is probably
/// still holding in a shop.
struct Confetti: View {
    private struct Piece: Identifiable {
        let id = UUID()
        let across: CGFloat
        let colour: Color
        let delay: Double
        let spin: Double
        let drift: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    private static let palette: [Color] = [.green, .mint, .orange, .pink, .purple, .yellow, .blue]

    @State private var pieces: [Piece] = []
    @State private var falling = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                ForEach(pieces) { piece in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(piece.colour)
                        .frame(width: piece.width, height: piece.height)
                        .position(x: geometry.size.width * piece.across, y: -24)
                        .offset(
                            x: falling ? piece.drift : 0,
                            y: falling ? geometry.size.height + 90 : 0
                        )
                        .rotationEffect(.degrees(falling ? piece.spin : 0))
                        .animation(.easeIn(duration: 2.4).delay(piece.delay), value: falling)
                }
            }
        }
        // Over a list somebody is still using.
        .allowsHitTesting(false)
        .onAppear {
            pieces = (0..<70).map { _ in
                Piece(
                    across: .random(in: 0...1),
                    colour: Self.palette.randomElement() ?? .green,
                    delay: .random(in: 0...0.5),
                    spin: .random(in: 180...900),
                    drift: .random(in: -70...70),
                    width: .random(in: 5...9),
                    height: .random(in: 9...15)
                )
            }
            // One frame at the top before they move, or they are created
            // already fallen and nothing animates.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(20))
                falling = true
            }
        }
    }
}

#Preview {
    Confetti()
}
