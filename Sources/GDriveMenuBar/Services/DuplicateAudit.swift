import Foundation

/// Tolerant reader for the duplicate-audit CSV produced by the storage audit.
/// Header-driven: works with any column layout, returns [] when no audit exists.
struct DupGroup {
    let name: String
    let detail: String
    let path: String?
}

enum DuplicateAudit {
    static var csvPath: String {
        if let e = ProcessInfo.processInfo.environment["GDRIVE_MANAGER_SCRATCH"], !e.isEmpty {
            return e + "/audit_output/duplicate_files.csv"
        }
        // Same default the SwiftBar plugin uses.
        return NSHomeDirectory() + "/.gemini/antigravity/brain/7698e221-d872-43d5-97e0-dd9c5a99fd57/scratch/audit_output/duplicate_files.csv"
    }

    static func top(limit: Int = 5) -> [DupGroup] {
        guard let text = try? String(contentsOfFile: csvPath, encoding: .utf8) else { return [] }
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count >= 2 else { return [] }
        let header = splitCSV(lines[0]).map { $0.lowercased() }
        func col(_ needles: [String]) -> Int? {
            header.firstIndex(where: { h in needles.contains(where: { h.contains($0) }) })
        }
        let sizeIdx = col(["wasted", "duplicate_wasted", "size", "mb", "gb", "bytes"])
        let pathIdx = col(["path", "file", "filepath", "name"])
        var rows: [(Double, [String])] = []
        for line in lines.dropFirst() {
            let cells = splitCSV(line)
            guard cells.count == header.count else { continue }
            var score = 0.0
            if let i = sizeIdx, i < cells.count {
                let digits = cells[i].components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).joined()
                score = Double(digits) ?? 0
            }
            rows.append((score, cells))
        }
        rows.sort { $0.0 > $1.0 }
        return rows.prefix(limit).map { score, cells in
            let rawPath = pathIdx.flatMap { $0 < cells.count ? cells[$0] : nil } ?? ""
            let exists = !rawPath.isEmpty && FileManager.default.fileExists(atPath: rawPath)
            let name = exists ? URL(fileURLWithPath: rawPath).lastPathComponent : (cells.first ?? "group")
            var detail = "duplicate"
            if let i = sizeIdx, i < cells.count, !cells[i].isEmpty {
                detail = "\(cells[i]) wasted"
            }
            return DupGroup(name: name, detail: detail, path: exists ? rawPath : nil)
        }
    }

    /// Minimal CSV split that respects double-quoted commas.
    private static func splitCSV(_ line: String) -> [String] {
        var cells: [String] = []
        var cur = ""
        var quoted = false
        for ch in line {
            if ch == "\"" { quoted.toggle(); continue }
            if ch == "," && !quoted { cells.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
            else { cur.append(ch) }
        }
        cells.append(cur.trimmingCharacters(in: .whitespaces))
        return cells
    }
}
