import Charts
import SwiftUI

enum CostStatFormatter {
    private static let usdFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "en_US")
        f.currencyCode = "USD"
        f.currencySymbol = "$"
        f.usesGroupingSeparator = true
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000_000...:
            let v = Double(n) / 1_000_000_000
            return "\(formatted(v))B"
        case 1_000_000...:
            let v = Double(n) / 1_000_000
            return "\(formatted(v))M"
        case 1_000...:
            let v = Double(n) / 1_000
            return "\(formatted(v))K"
        default:
            return "\(n)"
        }
    }

    static func usd(_ amount: Double) -> String {
        usdFormatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }

    private static func formatted(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v))
            : String(format: "%.1f", v)
    }
}

@MainActor
struct CostDashboardView: View {
    let store: CostHistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let report = store.report {
                statsGrid(report)
                chart(report)
                Text("est. API value · not billed on subscription")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if report.entries.contains(where: { $0.requestCount > 0 && $0.pricedFraction < 1 }) {
                    Text("Some models lack pricing — cost is partial")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            } else if store.isScanning {
                ProgressView("Scanning usage…").font(.caption)
            } else {
                Text("No cost history yet").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func statsGrid(_ r: DailyCostReport) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 8) {
            GridRow {
                stat("Today", CostStatFormatter.usd(r.todayCostUSD))
                stat("30d cost", CostStatFormatter.usd(r.windowCostUSD))
            }
            GridRow {
                stat("30d tokens", CostStatFormatter.tokens(r.windowTokens))
                stat("Latest tokens", CostStatFormatter.tokens(r.latestTokens))
            }
        }
        if let top = r.topModel {
            Text("Top model: \(top)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold))
        }
    }

    @ViewBuilder private func chart(_ r: DailyCostReport) -> some View {
        let maxCost = r.entries.map(\.costUSD).max() ?? 0
        Chart(r.entries) { e in
            BarMark(x: .value("Day", e.date, unit: .day), y: .value("Cost", e.costUSD))
                .foregroundStyle(
                    e.costUSD >= maxCost && maxCost > 0
                        ? Color(nsColor: .systemYellow)
                        : Color.secondary.opacity(0.7)
                )
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 90)
    }
}
