import SwiftUI

// MARK: - Pixel Pet View

/// Renders an 8x8 pixel art pet as a SwiftUI grid of small rounded rectangles.
/// Color is determined by the current session status.
struct PixelPetView: View {
    let grid: [[Bool]]
    let status: SessionStatus
    let species: PetSpecies
    var size: CGFloat = 32

    /// Per-pixel size derived from overall view size.
    private var pixelSize: CGFloat { size / 8 }

    /// Resolves the fill color from the session status.
    private var fillColor: Color {
        status.color
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { col in
                        let filled = row < grid.count
                            && col < grid[row].count
                            && grid[row][col]
                        RoundedRectangle(cornerRadius: pixelSize * 0.2)
                            .fill(filled ? fillColor : Color.clear)
                            .frame(width: pixelSize, height: pixelSize)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.3), value: status)
    }
}

#if DEBUG
struct PixelPetView_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            ForEach(PetSpecies.allCases, id: \.self) { species in
                VStack {
                    PixelPetView(
                        grid: species.frame1,
                        status: .working,
                        species: species,
                        size: 64
                    )
                    Text(species.rawValue)
                        .font(.caption2)
                }
            }
        }
        .padding()
        .background(.black)
        .previewLayout(.sizeThatFits)
    }
}
#endif
