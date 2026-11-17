import AppKit
import Foundation

@MainActor
final class DashboardStore: ObservableObject {
    @Published var claude = ProviderState()
    @Published var opencode = ProviderState()
    @Published var deepseek = ProviderState()
    @Published var deepseekHistory: [BalanceSample] = []

    private var timers: [Timer] = []
    private let historyURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SidecarDash", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("deepseek-history.json")
    }()

    func start() {
        loadHistory()
        refreshAll()
        schedule(every: 5 * 60) { [weak self] in self?.refreshClaude() }
        schedule(every: 3 * 60) { [weak self] in self?.refreshOpenCode() }
        schedule(every: 3 * 60) { [weak self] in self?.refreshDeepSeek() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshAll() }
        }
    }

    func refreshAll() {
        guard !Demo.isOn else { return }
        refreshClaude()
        refreshOpenCode()
        refreshDeepSeek()
    }

    private func schedule(every seconds: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        let timer = Timer(timeInterval: seconds, repeats: true) { _ in
            Task { @MainActor in action() }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers.append(timer)
    }

    func refreshClaude() {
        guard !claude.loading else { return }
        claude.loading = true
        Task {
            // The CLI source reads the signed-in Claude Code plan; fall back to CodexBar's default.
            var result = await CodexBarClient.fetch(provider: "claude", source: "cli")
            if case .failure = result { result = await CodexBarClient.fetch(provider: "claude") }
            if case .success(let r) = result, r.usage?.primary == nil, r.usage?.secondary == nil {
                result = .failure(.init(description: "No Claude limits reported"))
            }
            apply(result, to: \.claude)
        }
    }

    func refreshOpenCode() {
        guard !opencode.loading else { return }
        opencode.loading = true
        Task { apply(await CodexBarClient.fetch(provider: "opencodego"), to: \.opencode) }
    }

    func refreshDeepSeek() {
        guard !deepseek.loading else { return }
        deepseek.loading = true
        Task {
            let result = await CodexBarClient.fetch(provider: "deepseek")
            apply(result, to: \.deepseek)
            if case .success(let r) = result, let balance = DeepSeekBalance(r.usage?.primary?.resetDescription) {
                record(balance.total)
            }
        }
    }

    private func apply(_ result: Result<ProviderResult, CodexBarClient.Failure>,
                       to keyPath: ReferenceWritableKeyPath<DashboardStore, ProviderState>) {
        var state = self[keyPath: keyPath]
        state.loading = false
        switch result {
        case .success(let r):
            state.result = r
            state.error = nil
            state.lastSuccess = Date()
        case .failure(let f):
            // Keep the last good numbers on screen; the card shows them as stale.
            state.error = f.description
        }
        self[keyPath: keyPath] = state
    }

    // MARK: DeepSeek balance history

    var deepseekSpentToday: Double {
        let start = Calendar.current.startOfDay(for: Date())
        let today = deepseekHistory.filter { $0.date >= start }
        // Sum only drops so a top-up doesn't hide spending.
        return zip(today, today.dropFirst()).reduce(0) { sum, pair in
            sum + max(0, pair.0.balance - pair.1.balance)
        }
    }

    private func record(_ balance: Double) {
        deepseekHistory.append(BalanceSample(date: Date(), balance: balance))
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        deepseekHistory.removeAll { $0.date < cutoff }
        if let data = try? JSONEncoder().encode(deepseekHistory) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: historyURL),
              let samples = try? JSONDecoder().decode([BalanceSample].self, from: data) else { return }
        deepseekHistory = samples
    }
}
