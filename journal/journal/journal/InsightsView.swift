import SwiftUI
import Charts

struct InsightsView: View {
    @Environment(JournalStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    statsGrid
                    if !monthlyData.isEmpty {
                        chartSection
                    }
                }
                .padding(24)
            }
        }
        .frame(minWidth: 640, minHeight: 560)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Insights")
                    .font(.title2.weight(.semibold))
                Text("\(store.entries.count) entries across \(uniqueDays) days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 12
        ) {
            StatCard(label: "Entries", value: "\(store.entries.count)", accent: settings.accentColor)
            StatCard(label: "Days journaled", value: "\(uniqueDays)", accent: settings.accentColor)
            StatCard(label: "Words written", value: totalWords.formatted(), accent: settings.accentColor)
            StatCard(label: "Avg / entry", value: "\(avgWords)", accent: settings.accentColor)
            StatCard(label: "Current streak", value: "\(currentStreak) d", accent: settings.accentColor)
            StatCard(label: "Longest streak", value: "\(longestStreak) d", accent: settings.accentColor)
        }
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Words per month")
                .font(.headline)
            Chart(monthlyData) { row in
                BarMark(
                    x: .value("Month", row.month, unit: .month),
                    y: .value("Words", row.wordCount)
                )
                .foregroundStyle(settings.accentColor)
                .cornerRadius(2)
            }
            .frame(height: 220)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: chartMonthStride)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
                }
            }
        }
    }

    private var uniqueDays: Int {
        let cal = Calendar.current
        let days = Set(store.entries.map { cal.startOfDay(for: $0.created) })
        return days.count
    }

    private var totalWords: Int {
        store.entries.reduce(0) { sum, entry in
            sum + wordCount(entry.body)
        }
    }

    private var avgWords: Int {
        guard !store.entries.isEmpty else { return 0 }
        return totalWords / store.entries.count
    }

    private var currentStreak: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = Set(store.entries.map { cal.startOfDay(for: $0.created) })
        var streak = 0
        var cursor = today
        while days.contains(cursor) {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    private var longestStreak: Int {
        let cal = Calendar.current
        let days = Set(store.entries.map { cal.startOfDay(for: $0.created) })
        guard !days.isEmpty else { return 0 }
        let sorted = days.sorted()
        var best = 1
        var current = 1
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            if let next = cal.date(byAdding: .day, value: 1, to: prev),
               cal.isDate(next, inSameDayAs: curr) {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }

    private var monthlyData: [MonthData] {
        let cal = Calendar.current
        var buckets: [Date: Int] = [:]
        for entry in store.entries {
            let comps = cal.dateComponents([.year, .month], from: entry.created)
            guard let monthStart = cal.date(from: comps) else { continue }
            buckets[monthStart, default: 0] += wordCount(entry.body)
        }
        return buckets
            .map { MonthData(month: $0.key, wordCount: $0.value) }
            .sorted { $0.month < $1.month }
    }

    private var chartMonthStride: Int {
        let count = monthlyData.count
        if count <= 12 { return 1 }
        if count <= 36 { return 3 }
        if count <= 72 { return 6 }
        return 12
    }

    private func wordCount(_ s: String) -> Int {
        s.split(whereSeparator: { $0.isWhitespace }).count
    }
}

private struct MonthData: Identifiable {
    let id = UUID()
    let month: Date
    let wordCount: Int
}

private struct StatCard: View {
    let label: String
    let value: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.10))
        )
    }
}
