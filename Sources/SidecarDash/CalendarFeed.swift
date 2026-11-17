import AppKit
import EventKit
import SwiftUI

struct AgendaEvent: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var color: Color
    var calendarName: String
}

/// Reads events from the Mac's Calendar, which includes any Google accounts
/// added under System Settings → Internet Accounts.
@MainActor
final class CalendarFeed: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var events: [AgendaEvent] = []
    @Published private(set) var access: Access = .unknown
    @Published private(set) var calendarCount = 0

    /// Called with true while the macOS permission prompt is up, so the window can step aside.
    var promptShowing: ((Bool) -> Void)?

    private let store = EKEventStore()
    private var timer: Timer?

    func start() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        let t = Timer(timeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        requestAccess()
    }

    func requestAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
            reload()
        case .notDetermined:
            promptShowing?(true)
            Task {
                let granted = (try? await store.requestFullAccessToEvents()) ?? false
                promptShowing?(false)
                access = granted ? .granted : .denied
                if granted { reload() }
            }
        default:
            access = .denied
        }
    }

    func loadDemo(_ sample: [AgendaEvent]) {
        access = .granted
        calendarCount = 2
        events = sample
    }

    func reload() {
        guard access == .granted, !Demo.isOn else { return }
        store.refreshSourcesIfNecessary()
        let calendars = store.calendars(for: .event)
        calendarCount = calendars.count
        guard !calendars.isEmpty else {
            events = []
            return
        }
        // Cover the month shown in the grid (for its dots) and the week ahead.
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: today))!
        let start = cal.date(byAdding: .day, value: -7, to: monthStart)!
        let end = max(cal.date(byAdding: .day, value: 8, to: today)!,
                      cal.date(byAdding: .month, value: 1, to: monthStart)!.addingTimeInterval(7 * 86_400))
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        events = store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .map { e in
                AgendaEvent(id: (e.eventIdentifier ?? UUID().uuidString) + "\(e.startDate.timeIntervalSince1970)",
                            title: e.title?.isEmpty == false ? e.title! : "Untitled",
                            start: e.startDate, end: e.endDate, isAllDay: e.isAllDay,
                            color: Color(nsColor: e.calendar.color ?? .systemBlue),
                            calendarName: e.calendar.title)
            }
            .sorted { ($0.start, $0.isAllDay ? 0 : 1) < ($1.start, $1.isAllDay ? 0 : 1) }
    }
}
