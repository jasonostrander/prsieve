import SwiftUI

struct PromptTestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            promptEditor
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 720, height: 720)
    }

    private var promptEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Ownership Context")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Edits autosave · ⌘R to re-run")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            TextEditor(text: $viewModel.settings.codeownerContext)
                .font(.body.monospaced())
                .frame(height: 140)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.25))
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .disabled(viewModel.isRunningPromptTest)
                .opacity(viewModel.isRunningPromptTest ? 0.6 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Prompt Test")
                    .font(.headline)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.isRunningPromptTest, let progress = viewModel.promptTestProgress {
                ProgressView(value: Double(progress.completed), total: Double(max(progress.total, 1)))
                    .frame(width: 140)
                Text("\(progress.completed)/\(progress.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var headerSubtitle: String {
        if let err = viewModel.promptTestError {
            return err
        }
        if viewModel.isRunningPromptTest {
            return "Categorizing your open PRs against the current prompt…"
        }
        let changed = viewModel.promptTestResults.filter(\.changed).count
        let total = viewModel.promptTestResults.count
        if total == 0 {
            return "Tap Run to score your open PRs with the current prompt."
        }
        return "\(total) PR\(total == 1 ? "" : "s") scored · \(changed) would change category"
    }

    @ViewBuilder
    private var content: some View {
        if let err = viewModel.promptTestError {
            errorState(err)
        } else if viewModel.promptTestResults.isEmpty && viewModel.isRunningPromptTest {
            emptyRunningState
        } else if viewModel.promptTestResults.isEmpty {
            emptyIdleState
        } else {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.promptTestResults) { result in
                        PromptTestRow(result: result)
                    }
                }
                .padding(16)
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var emptyRunningState: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Running…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyIdleState: some View {
        ContentUnavailableView {
            Label("No results yet", systemImage: "text.magnifyingglass")
        } description: {
            Text("Run the prompt against your currently visible PRs to see how each would be categorized.")
        }
    }

    private var footer: some View {
        HStack {
            if viewModel.isRunningPromptTest {
                Button("Cancel") { viewModel.cancelPromptTest() }
            } else {
                Button("Run") { viewModel.startPromptTest() }
                    .keyboardShortcut("r", modifiers: .command)
                    .buttonStyle(.borderedProminent)
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct PromptTestRow: View {
    let result: PromptTestResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(result.pr.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(2)
                    if result.changed {
                        Text("Changed")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Text(result.pr.repoFullName)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("#\(result.pr.number)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(result.pr.author)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(result.newReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.top, 2)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    categoryPill(result.originalCategory, dim: true)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    categoryPill(result.newCategory, dim: false)
                }
                Link(destination: result.pr.htmlURL) {
                    HStack(spacing: 3) {
                        Text("Open")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .frame(width: 180, alignment: .trailing)
        }
        .padding(10)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var rowBackground: Color {
        result.changed ? Color.orange.opacity(0.06) : Color.secondary.opacity(0.06)
    }

    private func categoryPill(_ category: PRCategory, dim: Bool) -> some View {
        Text(category.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(categoryColor(category).opacity(dim ? 0.10 : 0.20))
            .foregroundStyle(dim ? AnyShapeStyle(.secondary) : AnyShapeStyle(categoryColor(category)))
            .clipShape(Capsule())
    }

    private func categoryColor(_ category: PRCategory) -> Color {
        switch category {
        case .priority: return .red
        case .low: return .blue
        case .noise: return .gray
        }
    }
}
