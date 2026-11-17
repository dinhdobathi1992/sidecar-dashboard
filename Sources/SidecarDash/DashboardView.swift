import Charts
import SwiftUI

// Designed for the iPad as a Sidecar screen (about 1016 × 810 points).

enum Palette {
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let opencode = Color(red: 0.24, green: 0.86, blue: 0.67)
    static let deepseek = Color(red: 0.36, green: 0.52, blue: 1.0)
    static let ink = Color.white
    static let muted = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.32)
    static let warn = Color(red: 1.0, green: 0.74, blue: 0.27)
    static let danger = Color(red: 1.0, green: 0.36, blue: 0.38)
    static let calendar = Color(red: 0.98, green: 0.62, blue: 0.80)
    static let lunar = Color(red: 0.99, green: 0.84, blue: 0.47)
    static let cpu = Color(red: 0.40, green: 0.84, blue: 1.0)
    static let memory = Color(red: 0.70, green: 0.56, blue: 1.0)
    static let disk = Color(red: 0.98, green: 0.62, blue: 0.80)
}

struct DashboardView: View {
    @EnvironmentObject var store: DashboardStore
    @AppStorage(Widget.clock.key) private var showClock = true
    @AppStorage(Widget.calendar.key) private var showCalendar = true
    @AppStorage(Widget.claude.key) private var showClaude = true
    @AppStorage(Widget.opencode.key) private var showOpenCode = true
    @AppStorage(Widget.deepseek.key) private var showDeepSeek = true

    var body: some View {
        let anyCard = showClaude || showOpenCode || showDeepSeek
        let anyHeader = showClock || showCalendar
        ZStack {
            Backdrop()
            VStack(spacing: 18) {
                if anyHeader {
                    HStack(alignment: .top, spacing: 16) {
                        if showClock {
                            ClockHeader().fixedSize(horizontal: true, vertical: false)
                        }
                        if showCalendar {
                            AgendaCard().frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: anyCard ? 232 : nil)
                    .frame(maxHeight: anyCard ? 232 : .infinity)
                }
                if anyCard {
                    HStack(alignment: .top, spacing: 16) {
                        if showClaude { ClaudeCard(state: store.claude) }
                        if showOpenCode { OpenCodeCard(state: store.opencode) }
                        if showDeepSeek {
                            DeepSeekCard(state: store.deepseek,
                                         history: store.deepseekHistory,
                                         spentToday: store.deepseekSpentToday)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                if !anyHeader && !anyCard {
                    Spacer()
                    Text("All widgets are off. Turn some on from the gauge icon in the menu bar.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.muted)
                    Spacer()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 22)
        }
        .preferredColorScheme(.dark)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { store.refreshAll() }
    }
}

// MARK: Background

struct Backdrop: View {
    @EnvironmentObject var background: BackgroundStore

    var body: some View {
        ZStack {
            if let image = background.image {
                GeometryReader { geo in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                // Darken so text and cards stay readable on any photo.
                LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0.35), Color.black.opacity(0.6)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [Color(red: 0.03, green: 0.04, blue: 0.08),
                                        Color(red: 0.06, green: 0.05, blue: 0.11)],
                               startPoint: .top, endPoint: .bottom)
                glow(Palette.claude, x: -0.35, y: 0.25, size: 520)
                glow(Palette.opencode, x: 0.05, y: 0.45, size: 480)
                glow(Palette.deepseek, x: 0.42, y: 0.2, size: 540)
                glow(Color.purple, x: 0.3, y: -0.45, size: 460)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.2), value: background.image)
    }

    private func glow(_ color: Color, x: CGFloat, y: CGFloat, size: CGFloat) -> some View {
        GeometryReader { geo in
            Circle()
                .fill(RadialGradient(colors: [color.opacity(0.22), .clear],
                                     center: .center, startRadius: 0, endRadius: size / 2))
                .frame(width: size, height: size)
                .position(x: geo.size.width * (0.5 + x), y: geo.size.height * (0.5 + y))
        }
    }
}

/// Shared glass panel behind every card; darker over a photo.
struct Glass: ViewModifier {
    var accent: Color
    @EnvironmentObject var background: BackgroundStore

    func body(content: Content) -> some View {
        let photo = background.image != nil
        content
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(photo ? AnyShapeStyle(Color.black.opacity(0.52))
                                : AnyShapeStyle(LinearGradient(colors: [Color.white.opacity(0.075), Color.white.opacity(0.03)],
                                                               startPoint: .top, endPoint: .bottom)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [accent.opacity(0.45), Color.white.opacity(0.08)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing),
                                  lineWidth: 1)
            )
            .shadow(color: accent.opacity(photo ? 0 : 0.12), radius: 30, y: 10)
    }
}

extension View {
    func glass(_ accent: Color) -> some View { modifier(Glass(accent: accent)) }
}

// MARK: Clock

struct ClockHeader: View {
    @AppStorage(Widget.lunar.key) private var showLunar = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let now = context.date
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(now, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        .font(.system(size: 104, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(LinearGradient(colors: [.white, .white.opacity(0.72)],
                                                        startPoint: .top, endPoint: .bottom))
                    Text(now, format: .dateTime.second(.twoDigits))
                        .font(.system(size: 34, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.faint)
                }
                .shadow(color: .white.opacity(0.12), radius: 24)
                .padding(.top, -14)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(now, format: .dateTime.weekday(.wide))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                    Text(now, format: .dateTime.day().month(.wide).year())
                        .font(.system(size: 19, weight: .regular, design: .rounded))
                        .foregroundStyle(Palette.muted)
                }

                if showLunar {
                    LunarLine(now: now).padding(.top, 8)
                }

                Spacer(minLength: 8)
                DayProgress(now: now)
            }
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: showCalendarSibling ? nil : .infinity, alignment: .leading)
        }
    }

    @AppStorage(Widget.calendar.key) private var showCalendarSibling = true
}

struct LunarLine: View {
    var now: Date

    var body: some View {
        let lunar = LunarDate(now)
        let special = lunar.day == 1 || lunar.day == 15
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: lunar.day == 15 ? "moon.fill" : "moon.stars.fill")
                    .foregroundStyle(Palette.lunar)
                Text("\(lunar.dayLabel) \(lunar.monthLabel)")
                    .foregroundStyle(Palette.ink)
                Text("· năm \(lunar.yearName)")
                    .foregroundStyle(Palette.muted)
                if special {
                    Text(lunar.day == 15 ? "Rằm" : "Mùng 1")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Palette.lunar.opacity(0.25)))
                        .foregroundStyle(Palette.lunar)
                }
            }
            .font(.system(size: 17, weight: .medium, design: .rounded))
            Text("Âm lịch \(lunar.day)/\(lunar.month)\(lunar.isLeapMonth ? "N" : "") · ngày \(lunar.dayName) · tháng \(lunar.monthName)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.faint)
        }
    }
}

struct DayProgress: View {
    var now: Date

    var body: some View {
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        let fraction = now.timeIntervalSince(start) / 86_400
        let week = cal.component(.weekOfYear, from: now)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [Palette.claude, Palette.opencode, Palette.deepseek],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 6)
            Text("Day \(Int((fraction * 100).rounded()))% · Week \(week) · Vietnam time")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.faint)
        }
        .frame(maxWidth: 360)
    }
}

// MARK: Calendar

struct AgendaCard: View {
    @EnvironmentObject var feed: CalendarFeed
    @AppStorage(Widget.system.key) private var showSystem = true

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let now = context.date
            HStack(alignment: .top, spacing: 18) {
                MonthGrid(now: now, eventDays: eventDays)
                    .frame(width: showSystem ? 320 : nil)
                    .frame(maxWidth: showSystem ? nil : .infinity)
                if showSystem {
                    Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                    SystemPanel()
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glass(Palette.calendar)
        }
    }

    private var eventDays: Set<DateComponents> {
        let cal = Calendar.current
        var days = Set<DateComponents>()
        for e in feed.events {
            var d = cal.startOfDay(for: e.start)
            // All-day events end at midnight; count the days they actually cover.
            let last = e.end.addingTimeInterval(-1)
            while d <= last {
                days.insert(cal.dateComponents([.year, .month, .day], from: d))
                d = cal.date(byAdding: .day, value: 1, to: d)!
            }
        }
        return days
    }
}

// MARK: This Mac

/// CPU with a 2-minute sparkline, then memory and disk bars.
struct SystemPanel: View {
    @EnvironmentObject var monitor: SystemMonitor

    var body: some View {
        let s = monitor.snapshot
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "cpu")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.cpu)
                Text("THIS MAC")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Palette.faint)
                Spacer(minLength: 4)
                if let boot = s.bootDate {
                    Text("up \(uptimeLabel(since: boot))")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Palette.faint)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("CPU")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.ink.opacity(0.85))
                    Spacer(minLength: 4)
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(s.cpuPercent.rounded()))")
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                        Text("%")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.muted)
                    }
                    .monospacedDigit()
                    .foregroundStyle(severityColor(s.cpuPercent, accent: Palette.ink))
                }
                Sparkline(values: s.cpuHistory, color: severityColor(s.cpuPercent, accent: Palette.cpu))
                    .frame(height: 30)
                Text("\(s.cores) cores · load \(String(format: "%.2f", s.load1))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Palette.faint)
            }
            .padding(.top, 8)

            Spacer(minLength: 8)
            MetricBar(label: "Memory", percent: s.memPercent, accent: Palette.memory,
                      detail: "\(bytesLabel(s.memUsed)) / \(bytesLabel(s.memTotal))")
            Spacer(minLength: 8)
            MetricBar(label: "Disk", percent: s.diskPercent, accent: Palette.disk,
                      detail: "\(diskLabel(s.diskFree)) free")
        }
    }

    private func uptimeLabel(since boot: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(boot))
        let days = seconds / 86_400, hours = (seconds % 86_400) / 3600, minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

struct MetricBar: View {
    var label: String
    var percent: Double
    var accent: Color
    var detail: String

    var body: some View {
        let color = severityColor(percent, accent: accent)
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink.opacity(0.85))
                Text("\(Int(percent.rounded()))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
                Spacer(minLength: 4)
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .monospacedDigit()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.14))
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.6), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.width * min(percent / 100, 1), 4))
                        .shadow(color: color.opacity(0.5), radius: 4)
                }
            }
            .frame(height: 6)
            .animation(.easeInOut(duration: 0.6), value: percent)
        }
    }
}

/// Filled line of recent CPU samples on a fixed 0–100 scale.
struct Sparkline: View {
    var values: [Double]
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let n = SystemMonitor.historyLength
            let step = w / CGFloat(max(n - 1, 1))
            // Right-align so the newest sample sits at the edge while history fills in.
            let points = values.enumerated().map { i, v in
                CGPoint(x: w - CGFloat(values.count - 1 - i) * step,
                        y: h - CGFloat(min(max(v, 0), 100) / 100) * (h - 2) - 1)
            }
            ZStack {
                Capsule().fill(Color.white.opacity(0.06)).frame(height: 1).position(x: w / 2, y: h - 0.5)
                if points.count > 1 {
                    Path { p in
                        p.move(to: CGPoint(x: points[0].x, y: h))
                        points.forEach { p.addLine(to: $0) }
                        p.addLine(to: CGPoint(x: points.last!.x, y: h))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.35), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    Path { p in p.addLines(points) }
                        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .shadow(color: color.opacity(0.6), radius: 4)
                }
            }
        }
        .accessibilityLabel("CPU over the last two minutes")
    }
}

/// This month, weeks starting Monday, with small lunar day numbers and event dots.
struct MonthGrid: View {
    var now: Date
    var eventDays: Set<DateComponents>

    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        return c
    }()

    var body: some View {
        let cal = Self.cal
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now))!
        let daysInMonth = cal.range(of: .day, in: .month, for: monthStart)!.count
        let lead = (cal.component(.weekday, from: monthStart) + 5) % 7
        let rows = Int(ceil(Double(lead + daysInMonth) / 7))
        let todayDay = cal.component(.day, from: now)
        let lunarMonth = LunarDate(now)
        let rowHeight: CGFloat = rows > 5 ? 22 : 26

        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(now, format: .dateTime.month(.wide).year())
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text("\(lunarMonth.monthLabel.capitalizedFirst) âm")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.lunar.opacity(0.8))
            }
            .padding(.bottom, 4)
            HStack(spacing: 0) {
                ForEach(["T2", "T3", "T4", "T5", "T6", "T7", "CN"], id: \.self) { d in
                    Text(d)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(d == "CN" ? Palette.calendar.opacity(0.7) : Palette.faint)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { col in
                        let day = row * 7 + col - lead + 1
                        if day >= 1 && day <= daysInMonth {
                            let date = cal.date(byAdding: .day, value: day - 1, to: monthStart)!
                            DayCell(day: day, lunar: LunarDate(date), isToday: day == todayDay,
                                    isPast: day < todayDay, isSunday: col == 6,
                                    hasEvent: eventDays.contains(cal.dateComponents([.year, .month, .day], from: date)))
                                .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight)
                        }
                    }
                }
            }
        }
    }
}

struct DayCell: View {
    var day: Int
    var lunar: LunarDate
    var isToday: Bool
    var isPast: Bool
    var isSunday: Bool
    var hasEvent: Bool

    var body: some View {
        let special = lunar.day == 1 || lunar.day == 15
        ZStack {
            if isToday {
                Circle()
                    .fill(LinearGradient(colors: [Palette.calendar, Palette.calendar.opacity(0.6)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 26, height: 26)
                    .shadow(color: Palette.calendar.opacity(0.6), radius: 8)
            }
            VStack(spacing: 0) {
                Text("\(day)")
                    .font(.system(size: 12, weight: isToday ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isToday ? Color.black.opacity(0.85)
                                     : isSunday ? Palette.calendar.opacity(isPast ? 0.4 : 0.85)
                                     : Palette.ink.opacity(isPast ? 0.35 : 0.85))
                Text(lunar.day == 1 ? "\(lunar.day)/\(lunar.month)" : "\(lunar.day)")
                    .font(.system(size: 7, weight: special ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isToday ? Color.black.opacity(0.6)
                                     : special ? Palette.lunar : Palette.faint.opacity(isPast ? 0.6 : 1))
            }
            .monospacedDigit()
            if hasEvent && !isToday {
                Circle().fill(Palette.calendar).frame(width: 4, height: 4).offset(x: 12, y: -7)
            }
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: Card chrome

struct Card<Content: View>: View {
    var title: String
    var subtitle: String?
    var symbol: String
    var accent: Color
    var state: ProviderState
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(accent.opacity(0.18))
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Palette.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.muted)
                    }
                }
                Spacer()
                StatusDot(state: state, accent: accent)
            }

            if state.result == nil {
                Spacer()
                HStack {
                    Spacer()
                    if let error = state.error {
                        Text(error)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                content
                Spacer(minLength: 0)
            }

            UpdatedLine(state: state)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glass(accent)
    }
}

struct StatusDot: View {
    var state: ProviderState
    var accent: Color

    var body: some View {
        let color: Color = state.error != nil ? Palette.warn : (state.isStale ? Palette.faint : accent)
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .shadow(color: color, radius: state.loading ? 8 : 3)
            .opacity(state.loading ? 0.5 : 1)
            .animation(.easeInOut(duration: 0.6), value: state.loading)
    }
}

struct UpdatedLine: View {
    var state: ProviderState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            HStack(spacing: 6) {
                if let last = state.lastSuccess {
                    Text(Date().timeIntervalSince(last) < 60
                         ? "Updated just now"
                         : "Updated \(last.formatted(.relative(presentation: .named)))")
                } else {
                    Text(state.loading ? "Loading…" : "Waiting for data")
                }
                if state.error != nil, state.result != nil {
                    Text("· couldn't refresh")
                        .foregroundStyle(Palette.warn.opacity(0.85))
                }
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Palette.faint)
        }
    }
}

// MARK: Gauges

func severityColor(_ percent: Double, accent: Color) -> Color {
    if percent >= 90 { return Palette.danger }
    if percent >= 75 { return Palette.warn }
    return accent
}

struct Ring: View {
    var percent: Double
    var accent: Color
    var size: CGFloat
    var lineWidth: CGFloat

    var body: some View {
        let color = severityColor(percent, accent: accent)
        let fraction = min(max(percent / 100, 0), 1)
        ZStack {
            Circle().stroke(color.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(fraction, 0.004))
                .stroke(AngularGradient(colors: [color.opacity(0.55), color],
                                        center: .center,
                                        startAngle: .degrees(0),
                                        endAngle: .degrees(360 * max(fraction, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.55), radius: 7)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(Int(percent.rounded()))")
                    .font(.system(size: size * 0.28, weight: .semibold, design: .rounded))
                Text("%")
                    .font(.system(size: size * 0.13, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.muted)
            }
            .monospacedDigit()
            .foregroundStyle(Palette.ink)
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.8), value: percent)
    }
}

struct RingTile: View {
    var label: String
    var window: RateWindow?
    var accent: Color
    var size: CGFloat
    var lineWidth: CGFloat = 11

    var body: some View {
        VStack(spacing: 8) {
            Ring(percent: window?.usedPercent ?? 0, accent: accent, size: size, lineWidth: lineWidth)
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.ink.opacity(0.85))
            ResetText(window: window)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ResetText: View {
    var window: RateWindow?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(resetLabel(window?.resetsAt, now: context.date))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.faint)
        }
    }
}

func resetLabel(_ date: Date?, now: Date) -> String {
    guard let date else { return " " }
    let seconds = Int(date.timeIntervalSince(now))
    if seconds <= 0 { return "resetting" }
    let days = seconds / 86_400
    let hours = (seconds % 86_400) / 3600
    let minutes = (seconds % 3600) / 60
    if days > 0 { return "resets in \(days)d \(hours)h" }
    if hours > 0 { return "resets in \(hours)h \(minutes)m" }
    return "resets in \(minutes)m"
}

struct BarRow: View {
    var label: String
    var percent: Double
    var accent: Color
    var trailing: String?

    var body: some View {
        let color = severityColor(percent, accent: accent)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .foregroundStyle(Palette.ink.opacity(0.85))
                Spacer()
                Text(trailing ?? "\(Int(percent.rounded()))%")
                    .monospacedDigit()
                    .foregroundStyle(Palette.muted)
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.14))
                    Capsule()
                        .fill(color)
                        .frame(width: max(geo.size.width * min(percent / 100, 1), 4))
                        .shadow(color: color.opacity(0.5), radius: 4)
                }
            }
            .frame(height: 6)
        }
    }
}

/// Used vs. where you'd expect to be at this point in each window.
struct PaceBlock: View {
    var result: ProviderResult?
    var keys: [String]
    var fallbackLabels: [String: String]
    var accent: Color

    var body: some View {
        let rows = keys.compactMap { key -> (String, Pace)? in
            guard let pace = result?.pace?[key], pace.expectedUsedPercent != nil else { return nil }
            return (key, pace)
        }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("PACE")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(Palette.faint)
                ForEach(rows, id: \.0) { key, pace in
                    PaceRow(label: result?.rateWindowLabels?[key] ?? fallbackLabels[key] ?? key,
                            used: usedPercent(key), pace: pace, accent: accent)
                }
            }
        }
    }

    private func usedPercent(_ key: String) -> Double {
        switch key {
        case "primary": return result?.usage?.primary?.usedPercent ?? 0
        case "secondary": return result?.usage?.secondary?.usedPercent ?? 0
        default: return result?.usage?.tertiary?.usedPercent ?? 0
        }
    }
}

struct PaceRow: View {
    var label: String
    var used: Double
    var pace: Pace
    var accent: Color

    var body: some View {
        let expected = pace.expectedUsedPercent ?? 0
        let onTrack = pace.willLastToReset ?? (used <= expected)
        let color = onTrack ? accent : Palette.warn
        let reserve = pace.summary?.components(separatedBy: " | ").first ?? ""
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(label).foregroundStyle(Palette.ink.opacity(0.85))
                Spacer()
                Image(systemName: onTrack ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(color)
                Text(reserve).foregroundStyle(Palette.muted)
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07))
                    Capsule()
                        .fill(color.opacity(0.9))
                        .frame(width: max(geo.size.width * min(used / 100, 1), 4))
                    // Where usage "should" be by now
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.8))
                        .frame(width: 2, height: 14)
                        .offset(x: geo.size.width * min(expected / 100, 1) - 1)
                }
            }
            .frame(height: 8)
            HStack {
                Text("Used \(Int(used.rounded()))%")
                Spacer()
                Text("Expected \(Int(expected.rounded()))%")
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Palette.faint)
        }
    }
}

// MARK: Provider cards

struct ClaudeCard: View {
    var state: ProviderState
    @AppStorage(Billing.claudePriceKey) private var claudePrice = Billing.defaultClaudePrice
    @AppStorage(Billing.claudeDayKey) private var claudeDay = 0

    var body: some View {
        let usage = state.usage
        let plan = usage?.loginMethod.map { "Claude \($0) plan" } ?? "Claude Code"
        Card(title: "Claude", subtitle: plan, symbol: "sparkle", accent: Palette.claude, state: state) {
            HStack(spacing: 8) {
                RingTile(label: "Session · 5h", window: usage?.primary, accent: Palette.claude, size: 94, lineWidth: 10)
                RingTile(label: "Weekly", window: usage?.secondary, accent: Palette.claude, size: 94, lineWidth: 10)
            }
            VStack(spacing: 12) {
                ForEach(Array((usage?.extraRateWindows ?? []).enumerated()), id: \.offset) { _, extra in
                    BarRow(label: extra.title ?? "Extra", percent: extra.window?.usedPercent ?? 0,
                           accent: Palette.claude)
                }
            }
            Spacer(minLength: 0)
            PaceBlock(result: state.result, keys: ["primary", "secondary"],
                      fallbackLabels: ["primary": "Session", "secondary": "Weekly"],
                      accent: Palette.claude)
            BillingStrip(price: claudePrice, renews: Billing.nextCharge(day: claudeDay),
                         verb: "Renews", accent: Palette.claude,
                         hint: "Set charge day: menu bar → Billing…")
        }
    }
}

struct OpenCodeCard: View {
    var state: ProviderState
    @AppStorage(Billing.opencodePriceKey) private var opencodePrice = Billing.defaultOpenCodePrice

    var body: some View {
        let usage = state.usage
        let labels = state.result?.rateWindowLabels ?? [:]
        Card(title: "OpenCode Go", subtitle: "Subscription limits", symbol: "chevron.left.forwardslash.chevron.right",
             accent: Palette.opencode, state: state) {
            RingTile(label: labels["tertiary"] ?? "Monthly", window: usage?.tertiary,
                     accent: Palette.opencode, size: 94, lineWidth: 10)
            VStack(spacing: 10) {
                BarRow(label: labels["primary"] ?? "5-hour", percent: usage?.primary?.usedPercent ?? 0,
                       accent: Palette.opencode,
                       trailing: barTrailing(usage?.primary))
                BarRow(label: labels["secondary"] ?? "Weekly", percent: usage?.secondary?.usedPercent ?? 0,
                       accent: Palette.opencode,
                       trailing: barTrailing(usage?.secondary))
            }
            Spacer(minLength: 0)
            PaceBlock(result: state.result, keys: ["secondary", "tertiary"],
                      fallbackLabels: ["secondary": "Weekly", "tertiary": "Monthly"],
                      accent: Palette.opencode)
            BillingStrip(price: opencodePrice,
                         renews: usage?.extraRateWindows?.first { $0.id == "renewal" }?.window?.resetsAt,
                         verb: "Renews", accent: Palette.opencode,
                         hint: "Renewal date not reported yet")
        }
    }

    private func barTrailing(_ window: RateWindow?) -> String {
        let percent = "\(Int((window?.usedPercent ?? 0).rounded()))%"
        let reset = resetLabel(window?.resetsAt, now: Date())
        return reset.trimmingCharacters(in: .whitespaces).isEmpty ? percent : "\(percent) · \(reset)"
    }
}

/// Monthly price and the next charge date, so the billing day is easy to remember.
struct BillingStrip: View {
    var price: Double
    var renews: Date?
    var verb: String
    var accent: Color
    var hint: String

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let days = renews.map { daysUntil($0, from: context.date) }
            let soon = (days ?? 99) <= 3
            let tint = soon ? Palette.warn : accent
            HStack(spacing: 10) {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(renews.map { "\(verb.uppercased()) \(Self.dateFormat.string(from: $0).uppercased())" } ?? "MONTHLY")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(Palette.faint)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(usdShort(price))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                        Text("/mo")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Palette.muted)
                    }
                }
                Spacer(minLength: 4)
                if let days {
                    Text(days == 0 ? "today" : days == 1 ? "tomorrow" : "in \(days) days")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(tint.opacity(0.16)))
                        .fixedSize()
                } else {
                    Text(hint)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.faint)
                }
            }
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(soon ? 0.12 : 0.07)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1))
        }
    }

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM"
        return f
    }()

    private func daysUntil(_ date: Date, from now: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
    }
}

func usdShort(_ value: Double) -> String {
    let digits = value == value.rounded() ? 0 : 2
    return value.formatted(.currency(code: "USD").precision(.fractionLength(digits)).locale(Locale(identifier: "en_US")))
}

struct DeepSeekCard: View {
    var state: ProviderState
    var history: [BalanceSample]
    var spentToday: Double

    var body: some View {
        let balance = DeepSeekBalance(state.usage?.primary?.resetDescription)
        Card(title: "DeepSeek", subtitle: "API balance", symbol: "water.waves",
             accent: Palette.deepseek, state: state) {
            VStack(alignment: .leading, spacing: 4) {
                Text(balance.map { usd($0.total) } ?? "–")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient(colors: [.white, Palette.deepseek.opacity(0.9)],
                                                    startPoint: .top, endPoint: .bottom))
                    .shadow(color: Palette.deepseek.opacity(0.4), radius: 14)
                if let balance {
                    Text("Paid \(usd(balance.paid ?? 0)) · Granted \(usd(balance.granted ?? 0))")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Palette.muted)
                }
            }

            Spacer(minLength: 8)
            BalanceChart(history: history)
                .frame(minHeight: 70, maxHeight: 180)
            Spacer(minLength: 8)

            HStack {
                Label("Spent today", systemImage: "arrow.down.right")
                    .foregroundStyle(Palette.muted)
                Spacer()
                Text(usd(spentToday))
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink)
            }
            .font(.system(size: 13, weight: .medium, design: .rounded))
        }
    }
}

struct BalanceChart: View {
    var history: [BalanceSample]

    var body: some View {
        let recent = history.filter { $0.date > Date().addingTimeInterval(-24 * 3600) }
        let flat = (recent.map(\.balance).max() ?? 0) - (recent.map(\.balance).min() ?? 0) < 0.005
        if recent.count < 2 || flat {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.03))
                Text(recent.count < 2 ? "Balance trend fills in over the day"
                                      : "No spending in the last 24 hours")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Palette.faint)
            }
        } else {
            let values = recent.map(\.balance)
            let low = values.min() ?? 0
            let high = values.max() ?? 1
            let pad = max((high - low) * 0.2, 0.05)
            Chart(recent, id: \.date) { sample in
                AreaMark(x: .value("Time", sample.date),
                         yStart: .value("Floor", low - pad),
                         yEnd: .value("Balance", sample.balance))
                    .foregroundStyle(LinearGradient(colors: [Palette.deepseek.opacity(0.35), .clear],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", sample.date), y: .value("Balance", sample.balance))
                    .foregroundStyle(Palette.deepseek)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: (low - pad)...(high + pad))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .accessibilityLabel("DeepSeek balance over the last 24 hours")
        }
    }
}

func usd(_ value: Double) -> String {
    value.formatted(.currency(code: "USD").precision(.fractionLength(2)).locale(Locale(identifier: "en_US")))
}
