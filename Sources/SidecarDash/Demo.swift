import SwiftUI

/// Sample data for screenshots: start with `--demo` and nothing is read from
/// CodexBar, the Calendar or your accounts.
enum Demo {
    static let isOn = CommandLine.arguments.contains("--demo")

    @MainActor
    static func load(store: DashboardStore, calendar: CalendarFeed) {
        // Sample billing that outranks saved settings for this run only; nothing is written.
        UserDefaults.standard.setVolatileDomain([
            Billing.claudePriceKey: Billing.defaultClaudePrice,
            Billing.claudeDayKey: 3,
            Billing.opencodePriceKey: Billing.defaultOpenCodePrice,
        ], forName: UserDefaults.argumentDomain)
        let now = Date()
        store.claude = state(provider: "claude", now: now, """
        "usage": {"loginMethod": "Max",
          "primary": {"usedPercent": 42, "resetsAt": "\(iso(now, hours: 2.3))", "windowMinutes": 300},
          "secondary": {"usedPercent": 31, "resetsAt": "\(iso(now, hours: 76))", "windowMinutes": 10080},
          "extraRateWindows": [{"id": "opus", "title": "Opus only", "window": {"usedPercent": 12}}]},
        "pace": {"primary": {"summary": "11% in reserve | Expected 53% used", "expectedUsedPercent": 53, "willLastToReset": true},
                 "secondary": {"summary": "24% in reserve | Expected 55% used", "expectedUsedPercent": 55, "willLastToReset": true}}
        """)
        store.opencode = state(provider: "opencodego", now: now, """
        "rateWindowLabels": {"primary": "5-hour", "secondary": "Weekly", "tertiary": "Monthly"},
        "usage": {
          "primary": {"usedPercent": 18, "resetsAt": "\(iso(now, hours: 3.1))", "windowMinutes": 300},
          "secondary": {"usedPercent": 46, "resetsAt": "\(iso(now, hours: 98))", "windowMinutes": 10080},
          "tertiary": {"usedPercent": 63, "resetsAt": "\(iso(now, hours: 290))", "windowMinutes": 43200},
          "extraRateWindows": [{"id": "renewal", "title": "Renews", "window": {"resetsAt": "\(iso(now, hours: 290))"}}]},
        "pace": {"secondary": {"summary": "12% in reserve | Expected 58% used", "expectedUsedPercent": 58, "willLastToReset": true},
                 "tertiary": {"summary": "4% over | Expected 59% used", "expectedUsedPercent": 59, "willLastToReset": false}}
        """)
        store.deepseek = state(provider: "deepseek", now: now, """
        "usage": {"primary": {"resetDescription": "$24.80 (Paid: $20.00 / Granted: $4.80)"}}
        """)
        store.deepseekHistory = (0...48).map { i in
            let t = Double(i) / 48
            let spend = 3.2 * t + 0.4 * sin(t * 9) * t
            return BalanceSample(date: now.addingTimeInterval(-24 * 3600 * (1 - t)), balance: 28.0 - spend)
        }

        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        func at(_ day: Int, _ hour: Double) -> Date { today.addingTimeInterval(Double(day) * 86_400 + hour * 3600) }
        calendar.loadDemo([
            AgendaEvent(id: "1", title: "Design review", start: now.addingTimeInterval(40 * 60),
                        end: now.addingTimeInterval(100 * 60), isAllDay: false,
                        color: Color(red: 0.98, green: 0.62, blue: 0.80), calendarName: "Work"),
            AgendaEvent(id: "2", title: "Lunch with the team", start: at(1, 12), end: at(1, 13.5),
                        isAllDay: false, color: Color(red: 0.45, green: 0.78, blue: 0.98), calendarName: "Personal"),
            AgendaEvent(id: "3", title: "Sprint planning", start: at(2, 9.5), end: at(2, 10.5),
                        isAllDay: false, color: Color(red: 0.98, green: 0.62, blue: 0.80), calendarName: "Work"),
            AgendaEvent(id: "4", title: "Gym", start: at(4, 18), end: at(4, 19),
                        isAllDay: false, color: Color(red: 0.55, green: 0.90, blue: 0.62), calendarName: "Personal"),
            AgendaEvent(id: "5", title: "Release day", start: at(9, 0), end: at(10, 0),
                        isAllDay: true, color: Color(red: 0.99, green: 0.75, blue: 0.40), calendarName: "Work"),
        ])
    }

    private static func iso(_ now: Date, hours: Double) -> String {
        ISO8601DateFormatter().string(from: now.addingTimeInterval(hours * 3600))
    }

    private static func state(provider: String, now: Date, _ body: String) -> ProviderState {
        let json = "{\"provider\": \"\(provider)\", \(body)}"
        let result = try? CodexBarClient.decoder.decode(ProviderResult.self, from: Data(json.utf8))
        assert(result != nil, "Bad demo JSON for \(provider)")
        return ProviderState(result: result, error: nil, lastSuccess: now)
    }
}
