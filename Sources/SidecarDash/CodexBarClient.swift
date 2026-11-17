import Foundation

/// Runs the CodexBar CLI, which already knows how to sign in to each provider.
enum CodexBarClient {
    static let binary: String? = [
        "/opt/homebrew/bin/codexbar",
        "/usr/local/bin/codexbar",
        "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI",
    ].first { FileManager.default.isExecutableFile(atPath: $0) }

    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    static func fetch(provider: String, source: String? = nil) async -> Result<ProviderResult, Failure> {
        guard let binary else { return .failure(Failure(description: "CodexBar CLI not found")) }
        var args = ["usage", "--provider", provider, "--json", "--no-color"]
        if let source { args += ["--source", source] }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: run(binary, args))
            }
        }
    }

    private static func run(_ binary: String, _ args: [String]) -> Result<ProviderResult, Failure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        // Claude's CLI source needs `claude` on PATH; launchd gives a bare PATH.
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env

        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch {
            return .failure(Failure(description: "Could not start CodexBar: \(error.localizedDescription)"))
        }

        // Kill a hung fetch so one provider never blocks the next refresh.
        let deadline = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: deadline)
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        deadline.cancel()

        do {
            let results = try decoder.decode([ProviderResult].self, from: data)
            guard let first = results.first else { return .failure(Failure(description: "Empty response")) }
            if let message = first.error?.message { return .failure(Failure(description: message)) }
            return .success(first)
        } catch {
            return .failure(Failure(description: "Unreadable response from CodexBar"))
        }
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = plain.date(from: s) ?? fractional.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(s)"))
        }
        return d
    }()
}
