import KDCalendar
import SwiftUI

/// The SwiftUI wrapper with a two-way selection binding, the three selection modes and a month
/// title driven by the scroll callback.
struct SwiftUIDemoView: View {

    @State private var selection: [Date] = []
    @State private var month: Date = Date()
    @State private var mode: CalendarView.SelectionMode = .range

    private let range: ClosedRange<Date> = {
        let calendar = Calendar.current
        return calendar.date(byAdding: .month, value: -1, to: Date())!...calendar.date(
            byAdding: .month, value: 3, to: Date())!
    }()

    private var style: CalendarView.Style {
        var style = CalendarView.Style.default
        style.cellShape = .round
        style.cellSelectedColor = .tintColor
        style.cellSelectedTextColor = .white
        style.cellSelectedBorderWidth = 0
        style.cellColorToday = UIColor.tintColor.withAlphaComponent(0.2)
        style.cellEventColor = .tintColor
        return style
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                KDCalendarView(range: range, selection: $selection)
                    .calendarStyle(style)
                    .selectionMode(mode)
                    .events(SampleEvents.around())
                    .displayDate(Date())
                    .onScrollToMonth { month = $0 }
                    .aspectRatio(1, contentMode: .fit)

                Picker("Selection", selection: $mode) {
                    Text("Single").tag(CalendarView.SelectionMode.single)
                    Text("Multiple").tag(CalendarView.SelectionMode.multiple)
                    Text("Range").tag(CalendarView.SelectionMode.range)
                }
                .pickerStyle(.segmented)

                HStack {
                    Button("Select this week") {
                        let calendar = Calendar.current
                        let week = calendar.dateInterval(of: .weekOfYear, for: Date())!
                        var day = week.start
                        var days: [Date] = []
                        while day < week.end {
                            days.append(day)
                            day = calendar.date(byAdding: .day, value: 1, to: day)!
                        }
                        selection = days
                    }
                    Spacer()
                    Button("Clear") { selection = [] }
                }
                .buttonStyle(.bordered)

                List(selection.sorted(), id: \.self) { date in
                    Text(date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                }
                .listStyle(.plain)
            }
            .padding(.horizontal)
            .navigationTitle(month.formatted(.dateTime.month(.wide).year()))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    SwiftUIDemoView()
}
