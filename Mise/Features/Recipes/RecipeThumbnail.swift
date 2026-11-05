import SwiftUI

/// A recipe's photo, or something that does not look broken without one.
///
/// Most of the owner's 382 imported recipes have a rescued photo. The built in
/// ones have none at all, and NYT's pictures are the Times's and were never
/// downloaded, so the empty case is the common case rather than the edge.
/// It is a filled shape with the recipe's initial, not a grey box with a
/// broken image icon.
struct RecipeThumbnail: View {
    let recipe: Recipe
    var side: CGFloat = 56

    var body: some View {
        Group {
            if let data = recipe.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let address = recipe.imageURL {
                // No bytes but an address: the recipe came over the wire from
                // the other phone, which does not send pictures, or its
                // download failed at import. Either way the picture is one
                // request away and the placeholder is a worse answer.
                AsyncImage(url: address) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            // Steady per recipe rather than random, so a recipe keeps the same
            // colour every time the list is drawn.
            Color(hue: hue, saturation: 0.35, brightness: 0.82)
            Text(initial)
                .font(.system(size: side * 0.4, weight: .semibold, design: .serif))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var initial: String {
        String(recipe.title.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    private var hue: Double {
        let sum = recipe.title.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Double(sum % 360) / 360
    }
}
