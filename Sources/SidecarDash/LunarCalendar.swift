import Foundation

/// Vietnamese lunar calendar (âm lịch), computed for the UTC+7 meridian.
/// Algorithm by Hồ Ngọc Đức; Vietnam's calendar differs from the Chinese one
/// in some years because new moons are dated in Vietnam time.
struct LunarDate: Equatable {
    var day: Int
    var month: Int
    var year: Int
    var isLeapMonth: Bool
    /// Julian day number of the solar date, used for the day's can chi.
    var julianDay: Int

    static let stems = ["Giáp", "Ất", "Bính", "Đinh", "Mậu", "Kỷ", "Canh", "Tân", "Nhâm", "Quý"]
    static let branches = ["Tý", "Sửu", "Dần", "Mão", "Thìn", "Tỵ", "Ngọ", "Mùi", "Thân", "Dậu", "Tuất", "Hợi"]

    var yearName: String { "\(Self.stems[(year + 6) % 10]) \(Self.branches[(year + 8) % 12])" }
    var monthName: String { "\(Self.stems[(year * 12 + month + 3) % 10]) \(Self.branches[(month + 1) % 12])" }
    var dayName: String { "\(Self.stems[(julianDay + 9) % 10]) \(Self.branches[(julianDay + 1) % 12])" }

    /// "Mùng 9", "Rằm", or the plain day number.
    var dayLabel: String {
        if day == 15 { return "Rằm" }
        if day <= 10 { return "Mùng \(day)" }
        return "\(day)"
    }

    var monthLabel: String {
        let names = [1: "Giêng", 11: "Một", 12: "Chạp"]
        let base = "tháng \(names[month] ?? String(month))"
        return isLeapMonth ? "\(base) nhuận" : base
    }

    init(_ date: Date, timeZone: TimeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.day, .month, .year], from: date)
        self = Self.convert(day: c.day!, month: c.month!, year: c.year!, tz: 7)
    }

    private init(day: Int, month: Int, year: Int, isLeapMonth: Bool, julianDay: Int) {
        self.day = day
        self.month = month
        self.year = year
        self.isLeapMonth = isLeapMonth
        self.julianDay = julianDay
    }

    // MARK: Astronomy

    private static func jdFromDate(_ dd: Int, _ mm: Int, _ yy: Int) -> Int {
        let a = (14 - mm) / 12
        let y = yy + 4800 - a
        let m = mm + 12 * a - 3
        var jd = dd + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
        if jd < 2_299_161 { jd = dd + (153 * m + 2) / 5 + 365 * y + y / 4 - 32083 }
        return jd
    }

    private static func newMoon(_ k: Int) -> Double {
        let k = Double(k)
        let t = k / 1236.85, t2 = t * t, t3 = t2 * t
        let dr = Double.pi / 180
        var jd1 = 2_415_020.75933 + 29.53058868 * k + 0.0001178 * t2 - 0.000000155 * t3
        jd1 += 0.00033 * sin((166.56 + 132.87 * t - 0.009173 * t2) * dr)
        let m = 359.2242 + 29.10535608 * k - 0.0000333 * t2 - 0.00000347 * t3
        let mpr = 306.0253 + 385.81691806 * k + 0.0107306 * t2 + 0.00001236 * t3
        let f = 21.2964 + 390.67050646 * k - 0.0016528 * t2 - 0.00000239 * t3
        var c1 = (0.1734 - 0.000393 * t) * sin(m * dr) + 0.0021 * sin(2 * dr * m)
        c1 = c1 - 0.4068 * sin(mpr * dr) + 0.0161 * sin(dr * 2 * mpr)
        c1 = c1 - 0.0004 * sin(dr * 3 * mpr)
        c1 = c1 + 0.0104 * sin(dr * 2 * f) - 0.0051 * sin(dr * (m + mpr))
        c1 = c1 - 0.0074 * sin(dr * (m - mpr)) + 0.0004 * sin(dr * (2 * f + m))
        c1 = c1 - 0.0004 * sin(dr * (2 * f - m)) - 0.0006 * sin(dr * (2 * f + mpr))
        c1 = c1 + 0.0010 * sin(dr * (2 * f - mpr)) + 0.0005 * sin(dr * (2 * mpr + m))
        let deltaT = t < -11
            ? 0.001 + 0.000839 * t + 0.0002261 * t2 - 0.00000845 * t3 - 0.000000081 * t * t3
            : -0.000278 + 0.000265 * t + 0.000262 * t2
        return jd1 + c1 - deltaT
    }

    private static func sunLongitude(_ jdn: Double) -> Double {
        let t = (jdn - 2_451_545.0) / 36525, t2 = t * t
        let dr = Double.pi / 180
        let m = 357.52910 + 35999.05030 * t - 0.0001559 * t2 - 0.00000048 * t * t2
        let l0 = 280.46645 + 36000.76983 * t + 0.0003032 * t2
        var dl = (1.914600 - 0.004817 * t - 0.000014 * t2) * sin(dr * m)
        dl += (0.019993 - 0.000101 * t) * sin(dr * 2 * m) + 0.000290 * sin(dr * 3 * m)
        var l = (l0 + dl) * dr
        l -= Double.pi * 2 * floor(l / (Double.pi * 2))
        return l
    }

    private static func newMoonDay(_ k: Int, _ tz: Double) -> Int {
        Int(floor(newMoon(k) + 0.5 + tz / 24))
    }

    private static func sunSector(_ dayNumber: Int, _ tz: Double) -> Int {
        Int(floor(sunLongitude(Double(dayNumber) - 0.5 - tz / 24) / Double.pi * 6))
    }

    private static func lunarMonth11(_ yy: Int, _ tz: Double) -> Int {
        let off = Double(jdFromDate(31, 12, yy)) - 2_415_021
        let k = Int(floor(off / 29.530588853))
        var nm = newMoonDay(k, tz)
        if sunSector(nm, tz) >= 9 { nm = newMoonDay(k - 1, tz) }
        return nm
    }

    private static func leapMonthOffset(_ a11: Int, _ tz: Double) -> Int {
        let k = Int(floor((Double(a11) - 2_415_021.076998695) / 29.530588853 + 0.5))
        var i = 1
        var arc = sunSector(newMoonDay(k + i, tz), tz)
        var last = 0
        repeat {
            last = arc
            i += 1
            arc = sunSector(newMoonDay(k + i, tz), tz)
        } while arc != last && i < 14
        return i - 1
    }

    static func convert(day dd: Int, month mm: Int, year yy: Int, tz: Double) -> LunarDate {
        let dayNumber = jdFromDate(dd, mm, yy)
        let k = Int(floor((Double(dayNumber) - 2_415_021.076998695) / 29.530588853))
        var monthStart = newMoonDay(k + 1, tz)
        if monthStart > dayNumber { monthStart = newMoonDay(k, tz) }
        var a11 = lunarMonth11(yy, tz)
        var b11 = a11
        var lunarYear: Int
        if a11 >= monthStart {
            lunarYear = yy
            a11 = lunarMonth11(yy - 1, tz)
        } else {
            lunarYear = yy + 1
            b11 = lunarMonth11(yy + 1, tz)
        }
        let lunarDay = dayNumber - monthStart + 1
        let diff = (monthStart - a11) / 29
        var leap = false
        var lunarMonth = diff + 11
        if b11 - a11 > 365 {
            let leapDiff = leapMonthOffset(a11, tz)
            if diff >= leapDiff {
                lunarMonth = diff + 10
                if diff == leapDiff { leap = true }
            }
        }
        if lunarMonth > 12 { lunarMonth -= 12 }
        if lunarMonth >= 11 && diff < 4 { lunarYear -= 1 }
        return LunarDate(day: lunarDay, month: lunarMonth, year: lunarYear, isLeapMonth: leap, julianDay: dayNumber)
    }
}
