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
            HStack(alignment: .firstTextBaseline) {
                Text("USAGE LIMITS").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary).kerning(0.5)
                Spacer()
                if model.refreshing && model.usage.limits.isEmpty {
                    Text("reading…").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }

            if model.usage.limits.isEmpty {
                Text(model.usageError ?? "—")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(model.usage.limits) { limit in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(limit.label).font(.system(size: 11))
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 6)
                        Text("\(limit.percent)%")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .monospacedDigit()
                    }
                    Meter(fraction: limit.fraction).frame(height: 6)
                    if let resets = limit.resets {
                        Text("resets \(resets)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
            }
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

    private struct Meter: View {
        let fraction: Double

        // Amber past 75%, red past 90% — inside the panel only; the menu bar glyph
        // stays monochrome.
        private var tint: Color {
            switch fraction {
            case ..<0.75: .accentColor
            case ..<0.90: .orange
            default: .red
            }
        }

        var body: some View {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.primary.opacity(0.10))
                    Capsule().fill(tint)
                        .frame(width: max(3, geo.size.width * min(max(fraction, 0), 1)))
                }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }
}
