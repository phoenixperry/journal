import SwiftUI

struct CalendarSidebarView: View {
    @Environment(JournalStore.self) private var store
    let onSelect: (JournalEntry) -> Void

    @State private var selectedDay: Date?
    @State private var showOnThisDay = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    weekdayHeader
                        .padding(.horizontal, 4)
                    ForEach(visibleMonths, id: \.self) { month in
                        monthGrid(for: month)
                            .id(month)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
            }
            .onAppear {
                if let current = currentMonthAnchor() {
                    DispatchQueue.main.async {
                        proxy.scrollTo(current, anchor: .bottom)
                    }
                }
            }
        }
        .sheet(isPresented: $showOnThisDay) {
            if let day = selectedDay {
                OnThisDayView(date: day) { entry in
                    showOnThisDay = false
                    onSelect(entry)
                }
            }
        }
    }

    private var weekdayHeader: some View {
        let cal = Calendar.current
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let firstWeekdayIdx = cal.firstWeekday - 1
        return HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { i in
                Text(symbols[(firstWeekdayIdx + i) % 7])
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func monthGrid(for month: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(month, format: .dateTime.month(.wide).year())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.leading, 2)

            VStack(spacing: 2) {
                ForEach(monthRows(for: month).indices, id: \.self) { idx in
                    HStack(spacing: 2) {
                        ForEach(monthRows(for: month)[idx], id: \.self) { date in
                            dayCell(date: date, currentMonth: month)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(date: Date, currentMonth: Date) -> some View {
        let cal = Calendar.current
        let inMonth = cal.isDate(date, equalTo: currentMonth, toGranularity: .month)
        let count = entryCount(on: date)
        let isSelected = selectedDay.map { cal.isDate($0, inSameDayAs: date) } ?? false
        let isToday = cal.isDateInToday(date)

        DayCell(
            day: cal.component(.day, from: date),
            inCurrentMonth: inMonth,
            entryCount: count,
            isSelected: isSelected,
            isToday: isToday
        )
        .onTapGesture {
            selectedDay = date
            if count > 0 || hasOtherYearEntries(on: date) {
                showOnThisDay = true
            }
        }
    }

    private var visibleMonths: [Date] {
        let cal = Calendar.current
        let now = Date()
        let earliest = store.entries.last?.created ?? now
        guard let startMonth = cal.date(from: cal.dateComponents([.year, .month], from: earliest)),
              let endMonth = cal.date(from: cal.dateComponents([.year, .month], from: now)) else {
            return []
        }

        var months: [Date] = []
        var cursor = startMonth
        while cursor <= endMonth {
            months.append(cursor)
            guard let next = cal.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return months
    }

    private func currentMonthAnchor() -> Date? {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        return cal.date(from: comps)
    }

    private func monthRows(for month: Date) -> [[Date]] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: month) else { return [] }
        let firstDay = interval.start
        let firstWeekday = cal.component(.weekday, from: firstDay)
        let daysFromStart = (firstWeekday - cal.firstWeekday + 7) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -daysFromStart, to: firstDay) else {
            return []
        }

        var rows: [[Date]] = []
        for week in 0..<6 {
            var row: [Date] = []
            for day in 0..<7 {
                if let date = cal.date(byAdding: .day, value: week * 7 + day, to: gridStart) {
                    row.append(date)
                }
            }
            rows.append(row)
        }
        return rows
    }

    private func entryCount(on date: Date) -> Int {
        let cal = Calendar.current
        return store.entries.filter { cal.isDate($0.created, inSameDayAs: date) }.count
    }

    private func hasOtherYearEntries(on date: Date) -> Bool {
        let cal = Calendar.current
        let target = cal.dateComponents([.month, .day], from: date)
        return store.entries.contains { entry in
            let c = cal.dateComponents([.month, .day], from: entry.created)
            return c.month == target.month && c.day == target.day
        }
    }
}

private struct DayCell: View {
    @Environment(AppSettings.self) private var settings
    let day: Int
    let inCurrentMonth: Bool
    let entryCount: Int
    let isSelected: Bool
    let isToday: Bool

    var body: some View {
        Text("\(day)")
            .font(.caption)
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
    }

    private var textColor: Color {
        inCurrentMonth ? Color.primary : Color.secondary.opacity(0.3)
    }

    private var backgroundColor: Color {
        guard entryCount > 0 else { return .clear }
        let intensity = min(Double(entryCount) / 4.0, 1.0)
        return settings.accentColor.opacity(0.18 + intensity * 0.45)
    }

    private var borderColor: Color {
        if isSelected { return settings.accentColor }
        if isToday { return settings.accentColor.opacity(0.55) }
        return .clear
    }

    private var borderWidth: CGFloat {
        isSelected ? 1.8 : (isToday ? 1.0 : 0)
    }
}
