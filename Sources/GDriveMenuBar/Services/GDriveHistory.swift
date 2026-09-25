import Foundation

/// Local capacity history (TokenBar-style trend).
/// Appends one sample per refresh to Application Support, aggregates daily peaks.
enum GDriveHistory {
    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("GDriveMenuBar", isDirectory: true)
    }

    private static var file: URL { dir.appendingPathComponent("capacity.jsonl") }

    struct Sample: Codable {
        let t: Double
        let pct: Double
    }

    static func record(pct: Double) {
        guard pct.isFinite, pct >= 0, pct <= 100 else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let line = (try? JSONEncoder().encode(Sample(t: Date().timeIntervalSince1970, pct: pct)))
            .flatMap { String(data: $0, encoding: .utf8) }.map { $0 + "\n" } ?? ""
        guard !line.isEmpty else { return }
        if FileManager.default.fileExists(atPath: file.path) {
            if let fh = try? FileHandle(forWritingTo: file) {
                _ = try? fh.seekToEnd()
                try? fh.write(contentsOf: Data(line.utf8))
                try? fh.close()
            }
        } else {
            try? line.write(to: file, atomically: true, encoding: .utf8)
        }
        prune()
    }

    /// Last 14 days as (day label, peak pct), oldest → newest.
    static func dailyPeaks(days: Int = 14) -> [(String, Double)] {
        guard let text = try? String(contentsOf: file) else { return [] }
        var peak: [String: Double] = [:]
        var order: [String] = []
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        for rawLine in text.components(separatedBy: .newlines) {
            guard let data = rawLine.data(using: .utf8),
                  let s = try? JSONDecoder().decode(Sample.self, from: data) else { continue }
            let day = fmt.string(from: Date(timeIntervalSince1970: s.t))
            if peak[day] == nil { order.append(day) }
            peak[day] = max(peak[day] ?? 0, s.pct)
        }
        let label = DateFormatter()
        label.dateFormat = "d"
        return order.suffix(days).compactMap { day -> (String, Double)? in
            guard let pct = peak[day], let date = fmt.date(from: day) else { return nil }
            return (label.string(from: date), pct)
        }
    }

    private static func prune() {
        guard let text = try? String(contentsOf: file) else { return }
        var lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 10000 else { return }
        lines = Array(lines.suffix(5000))
        try? lines.joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)
    }
}
