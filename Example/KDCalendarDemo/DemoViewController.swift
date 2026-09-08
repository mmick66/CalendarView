import KDCalendar
import KDCalendarEventKit
import UIKit

/// The original demo: a styled horizontal calendar, previous and next month
/// buttons, and a date picker that scrolls the calendar to the picked month.
final class DemoViewController: UIViewController {

    private let calendarView = CalendarView(frame: .zero)
    private let datePicker = UIDatePicker()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 252 / 255, green: 252 / 255, blue: 252 / 255, alpha: 1.0)

        let style = CalendarView.Style()
        style.cellShape = .bevel(8.0)
        style.cellColorDefault = UIColor.clear
        style.cellColorToday = UIColor(red: 1.00, green: 0.84, blue: 0.64, alpha: 1.00)
        style.cellSelectedBorderColor = UIColor(red: 1.00, green: 0.63, blue: 0.24, alpha: 1.00)
        style.cellEventColor = UIColor(red: 1.00, green: 0.63, blue: 0.24, alpha: 1.00)
        style.headerTextColor = UIColor.gray
        style.cellTextColorDefault = UIColor(red: 249 / 255, green: 180 / 255, blue: 139 / 255, alpha: 1.0)
        style.cellTextColorToday = UIColor.orange
        style.cellTextColorWeekend = UIColor(red: 237 / 255, green: 103 / 255, blue: 73 / 255, alpha: 1.0)
        style.cellColorOutOfRange = UIColor(red: 249 / 255, green: 226 / 255, blue: 212 / 255, alpha: 1.0)
        style.headerBackgroundColor = UIColor.white
        style.weekdaysBackgroundColor = UIColor.white
        style.firstWeekday = .sunday
        style.locale = Locale(identifier: "en_US")
        style.cellFont = UIFont(name: "Helvetica", size: 20.0) ?? UIFont.systemFont(ofSize: 20.0)
        style.headerFont = UIFont(name: "Helvetica", size: 20.0) ?? UIFont.systemFont(ofSize: 20.0)
        style.weekdaysFont = UIFont(name: "Helvetica", size: 14.0) ?? UIFont.systemFont(ofSize: 14.0)

        calendarView.style = style
        calendarView.dataSource = self
        calendarView.delegate = self
        calendarView.direction = .horizontal
        calendarView.multipleSelectionEnable = false
        calendarView.marksWeekends = true
        calendarView.backgroundColor = view.backgroundColor

        buildLayout()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let today = Date()
        if let tomorrow = calendarView.calendar.date(byAdding: .day, value: 1, to: today) {
            calendarView.selectDate(tomorrow)
        }

        calendarView.loadEvents { [weak self] error in
            guard let self, error != nil else { return }
            let message = "The calendar could not load system events. It is possibly a problem with permissions."
            let alert = UIAlertController(title: "Events Loading Error", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }

        calendarView.setDisplayDate(today)

        datePicker.locale = calendarView.style.locale
        datePicker.timeZone = calendarView.calendar.timeZone
        datePicker.setDate(today, animated: false)
    }

    // MARK: Layout

    private func buildLayout() {
        let previous = UIButton(type: .system)
        previous.setTitle("Previous", for: .normal)
        previous.addTarget(self, action: #selector(goToPreviousMonth), for: .touchUpInside)

        let next = UIButton(type: .system)
        next.setTitle("Next", for: .normal)
        next.addTarget(self, action: #selector(goToNextMonth), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [previous, UIView(), next])
        buttons.axis = .horizontal
        buttons.translatesAutoresizingMaskIntoConstraints = false

        datePicker.datePickerMode = .date
        datePicker.preferredDatePickerStyle = .compact
        datePicker.addTarget(self, action: #selector(onValueChange), for: .valueChanged)
        datePicker.translatesAutoresizingMaskIntoConstraints = false

        calendarView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(calendarView)
        view.addSubview(buttons)
        view.addSubview(datePicker)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            calendarView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 16),
            calendarView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            calendarView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            calendarView.heightAnchor.constraint(equalTo: calendarView.widthAnchor),

            buttons.topAnchor.constraint(equalTo: calendarView.bottomAnchor, constant: 8),
            buttons.leadingAnchor.constraint(equalTo: calendarView.leadingAnchor, constant: 8),
            buttons.trailingAnchor.constraint(equalTo: calendarView.trailingAnchor, constant: -8),
            buttons.heightAnchor.constraint(equalToConstant: 30),

            datePicker.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 20),
            datePicker.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
        ])
    }

    // MARK: Actions

    @objc private func onValueChange(_ picker: UIDatePicker) {
        calendarView.setDisplayDate(picker.date, animated: true)
    }

    @objc private func goToPreviousMonth() {
        calendarView.goToPreviousMonth()
    }

    @objc private func goToNextMonth() {
        calendarView.goToNextMonth()
    }

    override var prefersStatusBarHidden: Bool { true }
}

extension DemoViewController: CalendarViewDataSource {

    func startDate() -> Date {
        calendarView.calendar.date(byAdding: .month, value: -1, to: Date())!
    }

    func endDate() -> Date {
        calendarView.calendar.date(byAdding: .month, value: 12, to: Date())!
    }

    func headerString(_ date: Date) -> String? {
        nil
    }
}

extension DemoViewController: CalendarViewDelegate {

    func calendar(_ calendar: CalendarView, didSelectDate date: Date, withEvents events: [CalendarEvent]) {
        print("Did Select: \(date) with \(events.count) events")
        for event in events {
            print("\t\"\(event.title)\" - Starting at:\(event.startDate)")
        }
    }

    func calendar(_ calendar: CalendarView, didScrollToMonth date: Date) {
        datePicker.setDate(date, animated: true)
    }

    func calendar(_ calendar: CalendarView, canSelectDate date: Date) -> Bool {
        true
    }

    func calendar(_ calendar: CalendarView, didDeselectDate date: Date) {
    }

    func calendar(_ calendar: CalendarView, didLongPressDate date: Date, withEvents events: [CalendarEvent]?) {
        let alert = UIAlertController(title: "Create New Event", message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Event Title"
        }
        alert.addAction(
            UIAlertAction(title: "Create", style: .default) { [weak self] _ in
                guard let self, let title = alert.textFields?.first?.text, !title.isEmpty else { return }
                self.calendarView.addEvent(title, date: date)
            })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }
}
