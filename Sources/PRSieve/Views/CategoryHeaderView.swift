import SwiftUI

struct CategoryHeaderView: View {
    let category: PRCategory
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(category.displayName)
                .font(.headline)
            Text("\(count)")
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.15))
                .clipShape(Capsule())
                .foregroundStyle(color)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        switch category {
        case .mustReview: "exclamationmark.triangle.fill"
        case .shouldKnow: "eye.fill"
        case .fyi: "info.circle"
        }
    }

    private var color: Color {
        switch category {
        case .mustReview: .red
        case .shouldKnow: .orange
        case .fyi: .blue
        }
    }
}
