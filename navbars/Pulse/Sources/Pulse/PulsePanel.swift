import SwiftUI

struct PulsePanel: View {
    let model: PulseModel

    private let mono = Font.system(size: 11, design: .monospaced)
    private let label = Font.system(size: 11)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cpuCard
            memoryCard
            processCard
            footer
        }
        .padding(12)
        .frame(width: 360)
    }

    // MARK: - CPU

    private var cpuCard: some View {
        let cpu = model.snapshot.cpu
        return card {
            sectionHead("CPU", value: Fmt.percent(cpu.busy))

            Sparkline(samples: model.cpuHistory)
                .frame(height: 40)

            CoreGrid(values: cpu.perCore)
                .frame(height: 18)

            HStack(spacing: 8) {
                swatch("user", Fmt.percent(cpu.user), Palette.step(0))
                swatch("sys", Fmt.percent(cpu.system), Palette.step(2))
                Spacer(minLength: 0)
                Text(coreDescription).font(mono).foregroundStyle(.tertiary)
            }

            let load = model.snapshot.loadAverage
            Text(String(format: "load  %.2f  %.2f  %.2f", load.0, load.1, load.2))
                .font(mono).foregroundStyle(.tertiary)
        }
    }

    private var coreDescription: String {
        let snap = model.snapshot
        guard snap.perfCores > 0, snap.effCores > 0 else { return "\(snap.coreCount) cores" }
        return "\(snap.perfCores)P + \(snap.effCores)E"
    }

    // MARK: - Memory

    private var memoryCard: some View {
        let mem = model.snapshot.memory
        return card {
            sectionHead("MEMORY", value: "\(Fmt.bytes(mem.used)) / \(Fmt.bytes(mem.total))")

            SegmentBar(segments: [
                .init(bytes: mem.app, color: Palette.step(0)),
                .init(bytes: mem.wired, color: Palette.step(1)),
                .init(bytes: mem.compressed, color: Palette.step(2)),
                .init(bytes: mem.other, color: Palette.step(3)),
                .init(bytes: mem.cached, color: Palette.inactive),
            ], total: mem.total)
            .frame(height: 8)

            HStack(spacing: 10) {
                swatch("app", Fmt.compact(mem.app), Palette.step(0))
                swatch("wired", Fmt.compact(mem.wired), Palette.step(1))
                swatch("comp", Fmt.compact(mem.compressed), Palette.step(2))
                swatch("other", Fmt.compact(mem.other), Palette.step(3))
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                swatch("cached", Fmt.compact(mem.cached), Palette.inactive)
                Text("swap \(Fmt.compact(mem.swapUsed))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Text(Fmt.pressure(mem.pressureLevel))
                    .font(mono)
                    .foregroundStyle(Palette.pressure(mem.pressureLevel))
            }
        }
    }

    // MARK: - Processes

    private var processCard: some View {
        card {
            HStack(alignment: .top, spacing: 14) {
                processColumn("TOP CPU", rows: model.topByCPU) {
                    String(format: "%.0f%%", $0.cpu)
                }
                processColumn("TOP MEMORY", rows: model.topByMemory) {
                    Fmt.bytes($0.rss)
                }
            }
        }
    }

    private func processColumn(_ title: String,
                              rows: [ProcessRow],
                              value: @escaping (ProcessRow) -> String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary).kerning(0.5)
            if rows.isEmpty {
                Text("sampling…").font(mono).foregroundStyle(.quaternary)
            }
            ForEach(rows) { row in
                HStack(spacing: 5) {
                    Text(row.name).font(label).lineLimit(1).truncationMode(.tail)
                    // Rows are often the same binary; pid disambiguates them.
                    Text("\(row.pid)").font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Spacer(minLength: 4)
                    Text(value(row)).font(mono).foregroundStyle(.secondary)
                }
                .help("pid \(row.pid) · \(row.name)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Chrome

    private var footer: some View {
        HStack(spacing: 8) {
            Text("up \(Fmt.uptime(model.snapshot.uptime))")
            Text("·")
            Text(String(format: "%.1fs", model.interval))
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .focusEffectDisabled()
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 2)
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7, content: content)
            .padding(10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }

    private func sectionHead(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary).kerning(0.5)
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
    }

    private func swatch(_ name: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 6, height: 6)
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 10, design: .monospaced))
        }
        // Values must never wrap mid-unit, which squashes the whole legend row.
        .lineLimit(1)
        .fixedSize()
    }
}

// MARK: - Palette

/// One accent stepped by opacity rather than a spectrum of hues — legible in the
/// segmented bar without turning the panel into a rainbow.
private enum Palette {
    static func step(_ index: Int) -> Color {
        Color.accentColor.opacity([1.0, 0.66, 0.44, 0.26][min(index, 3)])
    }

    static let inactive = Color.primary.opacity(0.14)

    static func pressure(_ level: Int32) -> Color {
        switch level {
        case 2: .orange
        case 4: .red
        default: Color.primary.opacity(0.45)
        }
    }
}

// MARK: - Charts

private struct Sparkline: View {
    let samples: [Double]

    var body: some View {
        Canvas { context, size in
            for fraction in [0.5] {
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: size.height * fraction))
                grid.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
                context.stroke(grid, with: .color(.primary.opacity(0.08)),
                               style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
            }

            guard samples.count > 1 else { return }
            let step = size.width / CGFloat(StatusItemRenderer.historyLength - 1)
            let offset = size.width - step * CGFloat(samples.count - 1)
            func point(_ i: Int) -> CGPoint {
                CGPoint(x: offset + step * CGFloat(i),
                        y: size.height * (1 - min(max(samples[i], 0), 1)))
            }

            var line = Path()
            line.move(to: point(0))
            for i in 1..<samples.count { line.addLine(to: point(i)) }

            var fill = line
            fill.addLine(to: CGPoint(x: point(samples.count - 1).x, y: size.height))
            fill.addLine(to: CGPoint(x: offset, y: size.height))
            fill.closeSubpath()

            context.fill(fill, with: .linearGradient(
                Gradient(colors: [.accentColor.opacity(0.30), .accentColor.opacity(0.02)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(.accentColor),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            let head = point(samples.count - 1)
            context.fill(Path(ellipseIn: CGRect(x: head.x - 2, y: head.y - 2, width: 4, height: 4)),
                         with: .color(.accentColor))
        }
    }
}

private struct CoreGrid: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    let clamped = min(max(value, 0), 1)
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2.5).fill(.primary.opacity(0.07))
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(Color.accentColor.opacity(0.4 + 0.45 * clamped))
                            .frame(height: max(2.5, geo.size.height * clamped))
                    }
                    .help("core \(index) · \(Fmt.percent(clamped))")
                }
            }
        }
    }
}

private struct SegmentBar: View {
    struct Segment: Identifiable {
        let id = UUID()
        let bytes: UInt64
        let color: Color
    }

    let segments: [Segment]
    let total: UInt64

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: width(segment.bytes, in: geo.size.width))
                }
                Spacer(minLength: 0)
            }
            .background(.primary.opacity(0.06))
            .clipShape(Capsule())
        }
    }

    private func width(_ bytes: UInt64, in available: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        return max(0, available * CGFloat(Double(bytes) / Double(total)))
    }
}
