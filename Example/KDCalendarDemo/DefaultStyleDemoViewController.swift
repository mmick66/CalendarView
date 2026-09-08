import KDCalendar
import UIKit

/// The default style, untouched: dynamic colours for dark mode, fonts that follow Dynamic Type,
/// vertical paging, multiple selection, adjacent days and the calendar's own first weekday.
final class DefaultStyleDemoViewController: UIViewController {

    private let calendarView = CalendarView(frame: .zero)
    private let selectionLabel = UILabel()
    private let monthLabel = UILabel()
    private var hasAppeared = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Default style"
        view.backgroundColor = .systemBackground

        var style = CalendarView.Style.default
        style.firstWeekday = .automatic
        style.showAdjacentDays = true
        style.cellShape = .round
        calendarView.style = style
        calendarView.direction = .vertical
        calendarView.multipleSelectionEnable = true
        calendarView.dataSource = self
        calendarView.delegate = self

        buildLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasAppeared else { return }
        hasAppeared = true
        calendarView.events = SampleEvents.around()
        calendarView.setDisplayDate(Date())
        for offset in [2, 3, 4] {
            calendarView.selectDate(Calendar.current.date(byAdding: .day, value: offset, to: Date())!)
        }
    }

    private func buildLayout() {
        monthLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        monthLabel.textColor = .secondaryLabel
        monthLabel.adjustsFontForContentSizeCategory = true

        selectionLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        selectionLabel.numberOfLines = 0
        selectionLabel.adjustsFontForContentSizeCategory = true
        selectionLabel.text = "Tap days to select several. Swipe up and down for other months."

        let stack = UIStackView(arrangedSubviews: [calendarView, monthLabel, selectionLabel])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: guide.bottomAnchor, constant: -16),
            calendarView.heightAnchor.constraint(equalTo: calendarView.widthAnchor, multiplier: 1.1),
        ])
    }

    private func describeSelection() {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        let dates = calendarView.selectedDates.sorted().map(formatter.string(from:))
        selectionLabel.text = dates.isEmpty ? "No days selected." : "Selected: " + dates.joined(separator: ", ")
    }
}

extension DefaultStyleDemoViewController: CalendarViewDataSource {
    func startDate() -> Date { Calendar.current.date(byAdding: .month, value: -2, to: Date())! }
    func endDate() -> Date { Calendar.current.date(byAdding: .month, value: 6, to: Date())! }
}

extension DefaultStyleDemoViewController: CalendarViewDelegate {
    func calendar(_ calendar: CalendarView, didScrollToMonth date: Date) {
        monthLabel.text = "didScrollToMonth: " + date.formatted(.dateTime.month(.wide).year())
    }

    func calendar(_ calendar: CalendarView, didSelectDate date: Date, withEvents events: [CalendarEvent]) {
        describeSelection()
    }

    func calendar(_ calendar: CalendarView, didDeselectDate date: Date) {
        describeSelection()
    }
}
