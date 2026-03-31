import SwiftUI

struct CategoryHeaderView: View {
    let category: PRCategory
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: PRTheme.icon(for: category))
                .foregroundStyle(PRTheme.accent(for: category))
            Text(category.displayName)
                .font(.headline)
                .foregroundStyle(.primary)
            Text("\(count)")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(PRTheme.accent(for: category).opacity(0.15))
                .clipShape(Capsule())
                .foregroundStyle(PRTheme.accent(for: category))
            Spacer()
        }
    }
}
