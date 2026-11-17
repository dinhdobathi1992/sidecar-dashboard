import AppKit
import ImageIO

/// Widgets that can be switched on or off from the menu bar. All start on.
enum Widget: String, CaseIterable {
    case clock, lunar, calendar, system, claude, opencode, deepseek

    var title: String {
        switch self {
        case .clock: return "Clock & Date"
        case .lunar: return "Lunar Date (Âm lịch)"
        case .calendar: return "Calendar"
        case .system: return "This Mac (CPU, Memory, Disk)"
        case .claude: return "Claude"
        case .opencode: return "OpenCode Go"
        case .deepseek: return "DeepSeek"
        }
    }

    var key: String { "widget.\(rawValue)" }

    var isOn: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        nonmutating set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

/// Photos for the dashboard background. Chosen images are copied into the app's
/// own folder so they keep loading at login without extra file permissions.
@MainActor
final class BackgroundStore: ObservableObject {
    static let enabledKey = "background.enabled"
    private static let indexKey = "background.index"
    private static let rotateEvery: TimeInterval = 15 * 60

    @Published private(set) var image: NSImage?

    let folder: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SidecarDash/Backgrounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var timer: Timer?

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            reload()
        }
    }

    var imageFiles: [URL] {
        let exts: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "tif", "tiff", "gif"]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { exts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    func start() {
        reload()
        let t = Timer(timeInterval: Self.rotateEvery, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.next() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Copies the picked files in and shows the first new one.
    func add(_ urls: [URL]) {
        var firstNew: String?
        for url in urls {
            var dest = folder.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                dest = folder.appendingPathComponent("\(UUID().uuidString.prefix(6))-\(url.lastPathComponent)")
            }
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil, firstNew == nil {
                firstNew = dest.lastPathComponent
            }
        }
        if let firstNew, let i = imageFiles.firstIndex(where: { $0.lastPathComponent == firstNew }) {
            UserDefaults.standard.set(i, forKey: Self.indexKey)
        }
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        reload()
    }

    func next() {
        let count = imageFiles.count
        guard count > 1 else { return reload() }
        let i = (UserDefaults.standard.integer(forKey: Self.indexKey) + 1) % count
        UserDefaults.standard.set(i, forKey: Self.indexKey)
        reload()
    }

    func reload() {
        let files = imageFiles
        guard isEnabled, !files.isEmpty else {
            image = nil
            return
        }
        let i = UserDefaults.standard.integer(forKey: Self.indexKey) % files.count
        image = Self.downscaled(files[i], maxPixels: 2600)
    }

    /// Big photos are shrunk to about screen size so they don't hold lots of memory.
    private static func downscaled(_ url: URL, maxPixels: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

/// What each subscription costs and when it charges, so the cards can remind you.
/// OpenCode's renewal date comes from CodexBar; Claude's charge day is set from the menu.
enum Billing {
    static let claudePriceKey = "billing.claude.price"
    static let claudeDayKey = "billing.claude.day"
    static let opencodePriceKey = "billing.opencode.price"

    static let defaultClaudePrice = 100.0   // Claude Max 5x
    static let defaultOpenCodePrice = 10.0  // OpenCode Go

    static var claudePrice: Double {
        get { UserDefaults.standard.object(forKey: claudePriceKey) as? Double ?? defaultClaudePrice }
        set { UserDefaults.standard.set(newValue, forKey: claudePriceKey) }
    }
    /// Day of the month Claude charges (1–31), or 0 when not set yet.
    static var claudeDay: Int {
        get { UserDefaults.standard.integer(forKey: claudeDayKey) }
        set { UserDefaults.standard.set(newValue, forKey: claudeDayKey) }
    }
    static var opencodePrice: Double {
        get { UserDefaults.standard.object(forKey: opencodePriceKey) as? Double ?? defaultOpenCodePrice }
        set { UserDefaults.standard.set(newValue, forKey: opencodePriceKey) }
    }

    /// Next date (today or later) falling on `day` of the month; short months use their last day.
    static func nextCharge(day: Int, from now: Date = Date()) -> Date? {
        guard (1...31).contains(day) else { return nil }
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        for offset in 0...1 {
            guard let month = cal.date(byAdding: .month, value: offset,
                                       to: cal.date(from: cal.dateComponents([.year, .month], from: today))!),
                  let days = cal.range(of: .day, in: .month, for: month)?.count,
                  let date = cal.date(byAdding: .day, value: min(day, days) - 1, to: month) else { continue }
            if date >= today { return date }
        }
        return nil
    }
}
