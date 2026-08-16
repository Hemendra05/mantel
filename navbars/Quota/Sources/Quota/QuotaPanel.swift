import SwiftUI

struct QuotaPanel: View {
    let model: QuotaModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5).padding(.vertical, 11)
            limits
            Divider().opacity(0.5).padding(.vertical, 11)
            account
            footer.padding(.top, 10)
        }
        .padding(14)
        .frame(width: 292)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            RingGauge(session: model.usage.session?.fraction,
                      week: model.usage.week?.fraction,
                      signedIn: model.status.loggedIn)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text("Claude").font(.system(size: 13, weight: .semibold))
                Text(model.status.loggedIn ? "subscription" : "signed out")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }

            Spacer(minLength: 4)

            if model.status.loggedIn {
                Text(model.planLabel)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .kerning(0.4)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.16), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.30)))
            }
        }
    }

    // MARK: - Limits

    private var limits: some View {
        VStack(alignment: .leading, spacing: 13) {
            if model.usage.limits.isEmpty {
                HStack(spacing: 6) {
                    if model.refreshing {
                        ProgressView().controlSize(.mini).scaleEffect(0.65)
                    }
                    Text(model.refreshing ? "reading limits…" : (model.usageError ?? "—"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(height: 34)
            }

            ForEach(model.usage.limits) { limit in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(limit.title)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 4)
                        HStack(alignment: .firstTextBaseline, spacing: 1) {
                            Text("\(limit.percent)")
                                .font(.system(size: 17, weight: .medium, design: .rounded))
                                .monospacedDigit()
                            Text("%").font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Meter(fraction: limit.fraction)
                        .frame(height: 5)
                    if let reset = limit.shortReset {
                        Text("resets \(reset)")
                            .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .help(limit.resets ?? "")
                    }
                }
            }
        }
    }

    // MARK: - Account

    private var account: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.accountLabel)
                .font(.system(size: 11))
                .lineLimit(1).truncationMode(.middle)
                .help(model.status.email ?? "")
            HStack(spacing: 5) {
                ForEach(accountFacts, id: \.self) { fact in
                    Text(fact)
                    if fact != accountFacts.last {
                        Text("·").foregroundStyle(.quaternary)
                    }
                }
            }
            .font(.system(size: 9.5)).foregroundStyle(.tertiary)
            .lineLimit(1)
        }
    }

    private var accountFacts: [String] {
        guard model.status.loggedIn else { return [] }
        return [model.orgLabel, model.status.authMethod, model.status.apiProvider]
            .compactMap { $0 }
            .filter { $0 != "—" && !$0.isEmpty }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            if let error = model.error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 8)).foregroundStyle(.orange)
                Text(error)
            } else {
                Text(QuotaFmt.relative(model.lastUpdated))
            }
            if model.refreshing && !model.usage.limits.isEmpty {
                ProgressView().controlSize(.mini).scaleEffect(0.55)
            }
            Spacer()
            action("Refresh") { model.refresh() }
            action("Quit") { NSApplication.shared.terminate(nil) }
        }
        .font(.system(size: 9.5))
        .foregroundStyle(.tertiary)
    }

    private func action(_ title: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(title).font(.system(size: 9.5, weight: .medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .focusEffectDisabled()
    }
}

// MARK: - Components

private struct Meter: View {
    let fraction: Double

    // Amber past 75%, red past 90% — panel only; the menu bar glyph stays monochrome.
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
                Capsule().fill(.primary.opacity(0.09))
                Capsule()
                    .fill(LinearGradient(
                        colors: [tint.opacity(0.75), tint],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
    }
}

/// The panel echo of the menu bar glyph: outer arc is the session, inner is the week.
private struct RingGauge: View {
    let session: Double?
    let week: Double?
    let signedIn: Bool

    var body: some View {
        Canvas { context, size in
            let line = size.width * 0.115
            let outer = size.width / 2 - line / 2
            let inner = outer - line - size.width * 0.10
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            func arc(_ radius: CGFloat, _ fraction: Double?, _ tint: Color) {
                var track = Path()
                track.addArc(center: center, radius: radius,
                             startAngle: .zero, endAngle: .degrees(360), clockwise: false)
                context.stroke(track, with: .color(.primary.opacity(0.10)),
                               style: StrokeStyle(lineWidth: line))

                guard let fraction, fraction > 0.005 else { return }
                var path = Path()
                path.addArc(center: center, radius: radius,
                            startAngle: .degrees(-90),
                            endAngle: .degrees(-90 + 360 * min(fraction, 1)),
                            clockwise: false)
                context.stroke(path, with: .color(tint),
                               style: StrokeStyle(lineWidth: line, lineCap: .round))
            }

            guard signedIn else {
                var dashed = Path()
                dashed.addArc(center: center, radius: outer, startAngle: .zero,
                              endAngle: .degrees(360), clockwise: false)
                context.stroke(dashed, with: .color(.secondary),
                               style: StrokeStyle(lineWidth: line, dash: [2, 2.4]))
                return
            }

            arc(outer, session, sessionTint)
            arc(inner, week, .accentColor.opacity(0.55))
        }
    }

    private var sessionTint: Color {
        switch session ?? 0 {
        case ..<0.75: .accentColor
        case ..<0.90: .orange
        default: .red
        }
    }
}
