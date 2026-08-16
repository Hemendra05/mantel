import SwiftUI

struct QuotaPanel: View {
    let model: QuotaModel

    private let mono = Font.system(size: 11, design: .monospaced)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            accountCard
            usageCard
            footer
        }
        .padding(12)
        .frame(width: 320)
    }

    private var accountCard: some View {
        card {
            HStack(alignment: .firstTextBaseline) {
                Text("ACCOUNT").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary).kerning(0.5)
                Spacer()
                if model.status.loggedIn {
                    Text(model.planLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
            }

            Text(model.accountLabel)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1).truncationMode(.middle)
                .foregroundStyle(model.status.loggedIn ? .primary : .secondary)

            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(mono).foregroundStyle(.orange)
            }

            if model.status.loggedIn {
                row("org", model.orgLabel)
                row("auth", model.status.authMethod ?? "—")
                row("api", model.status.apiProvider ?? "—")
            }
        }
    }

    private var usageCard: some View {
        card {
            Text("USAGE LIMITS").font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary).kerning(0.5)
            Text("Not exposed by any supported local interface.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Text("Run /usage inside Claude Code to see session and weekly limits.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(QuotaFmt.relative(model.lastUpdated))
            if model.refreshing {
                ProgressView().controlSize(.mini).scaleEffect(0.7)
            }
            Spacer()
            Button("Refresh") { model.refresh() }
                .buttonStyle(.plain).foregroundStyle(.secondary).focusEffectDisabled()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain).foregroundStyle(.secondary).focusEffectDisabled()
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 2)
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value).font(.system(size: 10, design: .monospaced))
                .lineLimit(1).truncationMode(.tail)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }
}
