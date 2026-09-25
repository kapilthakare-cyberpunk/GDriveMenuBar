import Foundation
import Darwin

/// Native mirror of gdrive_manager.10s.py data layer.
/// Shares /tmp/gdrive_about_cache.json with the SwiftBar plugin.
enum GDriveService {
    private static var fm: FileManager { .default }
    private static var home: String { NSHomeDirectory() }
    private static var stagingTrash: String { home + "/.local_staging_trash" }
    private static var cloudDrive: String { home + "/CloudDrive" }
    private static var cacheFile: String { "/tmp/gdrive_about_cache.json" }
    private static var auditFile: String { "/tmp/gdrive_audit_results.json" }
    private static let cacheTTL: Double = 60

    // MARK: - Snapshot

    static func snapshot(forceCapacity: Bool = false) -> GDriveSnapshot {
        var snap = GDriveSnapshot()
        snap.running = isRcloneRunning()
        snap.mounted = isMounted()
        snap.cap = driveCapacity(forceRefresh: forceCapacity)
        snap.mac = macAudit()
        snap.audit = auditData()
        snap.immich = immichStatus()
        return snap
    }

    // MARK: - Helpers

    @discardableResult
    private static func run(_ path: String, args: [String] = [], timeout: Double = 6,
                            env: [String: String]? = nil) -> (out: String, code: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        if let env {
            var e = ProcessInfo.processInfo.environment
            for (k, v) in env { e[k] = v }
            p.environment = e
        }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
        } catch {
            return ("", -1)
        }
        // Drain the pipe concurrently: waiting for exit first would deadlock
        // as soon as the child writes more than the pipe buffer.
        let box = OutputBox()
        let readDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            box.data = pipe.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }
        let exited = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            p.waitUntilExit()
            exited.signal()
        }
        // Escalate to SIGKILL so a child ignoring SIGTERM can't hang us forever.
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            p.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(p.processIdentifier, SIGKILL)
            }
        }
        _ = readDone.wait(timeout: .now() + 2)
        return (String(data: box.data, encoding: .utf8) ?? "", p.terminationStatus)
    }

    private final class OutputBox: @unchecked Sendable {
        var data = Data()
    }

    private final class ProbeResult: @unchecked Sendable {
        var reachable = false
    }

    private static func binary(_ name: String) -> String? {
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", home + "/bin", "/usr/bin", "/bin", "/sbin"] {
            let full = dir + "/" + name
            if fm.isExecutableFile(atPath: full) { return full }
        }
        return nil
    }

    // MARK: - Drive capacity (60s shared cache)

    static func driveCapacity(forceRefresh: Bool = false) -> DriveCapacity {
        if !forceRefresh, let cached = readCache() {
            return cached
        }
        var cap = DriveCapacity()
        guard let rclone = binary("rclone") else { return cap }
        let (out, code) = run(rclone, args: ["about", "gdrive:", "--json"], timeout: 8)
        guard code == 0,
              let data = out.data(using: .utf8),
              let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return cap }
        let gib: (Any?) -> Double = { v in
            if let n = v as? NSNumber { return n.doubleValue / 1_073_741_824.0 }
            return 0
        }
        let total = (info["total"] as? NSNumber)?.doubleValue ?? 0
        let used = (info["used"] as? NSNumber)?.doubleValue ?? 0
        cap.totalGB = gib(info["total"])
        cap.usedGB = gib(info["used"])
        cap.freeGB = gib(info["free"])
        cap.trashedGB = gib(info["trashed"])
        cap.usedPct = total > 0 ? used / total * 100 : 0
        cap.available = true
        writeCache(cap)
        return cap
    }

    private static func readCache() -> DriveCapacity? {
        guard let data = fm.contents(atPath: cacheFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ts = json["timestamp"] as? Double,
              Date().timeIntervalSince1970 - ts < cacheTTL,
              let p = json["payload"] as? [String: Any] else { return nil }
        var cap = DriveCapacity()
        cap.totalGB = p["total_gb"] as? Double ?? 0
        cap.usedGB = p["used_gb"] as? Double ?? 0
        cap.freeGB = p["free_gb"] as? Double ?? 0
        cap.trashedGB = p["trashed_gb"] as? Double ?? 0
        cap.usedPct = p["used_pct"] as? Double ?? 0
        cap.available = true
        // An all-zero cache means the plugin never got data; treat as miss.
        if cap.totalGB == 0 && cap.usedGB == 0 && cap.freeGB == 0 { return nil }
        return cap
    }

    private static func writeCache(_ cap: DriveCapacity) {
        let payload: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "payload": [
                "total_gb": cap.totalGB, "used_gb": cap.usedGB,
                "free_gb": cap.freeGB, "trashed_gb": cap.trashedGB,
                "used_pct": cap.usedPct,
            ],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            fm.createFile(atPath: cacheFile, contents: data)
        }
    }

    // MARK: - Mac audit

    static func macAudit() -> MacAudit {
        var audit = MacAudit()
        if let attrs = try? fm.attributesOfFileSystem(forPath: "/") {
            let total = (attrs[.systemSize] as? NSNumber)?.uint64Value ?? 0
            let free = (attrs[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
            audit.totalGB = Double(total) / 1_073_741_824.0
            audit.freeGB = Double(free) / 1_073_741_824.0
            audit.usedGB = max(audit.totalGB - audit.freeGB, 0)
        }
        var vols: [String] = []
        if let urls = fm.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey, .volumeAvailableCapacityKey], options: [.skipHiddenVolumes]) {
            for url in urls {
                guard let vals = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeAvailableCapacityKey]),
                      let name = vals.volumeName, name != "Macintosh HD" else { continue }
                if let free = vals.volumeAvailableCapacity {
                    vols.append("\(name) (\(String(format: "%.1f", Double(free) / 1_073_741_824.0)) GiB free)")
                } else {
                    vols.append(name)
                }
            }
        }
        if !vols.isEmpty { audit.volumes = vols }
        var bytes: UInt64 = 0
        if fm.fileExists(atPath: stagingTrash),
           let walker = fm.enumerator(atPath: stagingTrash) {
            for case let rel as String in walker {
                let full = stagingTrash + "/" + rel
                if let vals = try? URL(fileURLWithPath: full).resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                   vals.isRegularFile == true, let size = vals.fileSize {
                    bytes += UInt64(max(size, 0))
                }
            }
        }
        audit.stagingBytes = bytes
        let gb = Double(bytes) / 1_073_741_824.0
        audit.stagingTrash = gb >= 0.1
            ? String(format: "%.2f GiB", gb)
            : String(format: "%.2f MiB", Double(bytes) / 1_048_576.0)
        return audit
    }

    // MARK: - Audit file / rclone state / mount

    static func auditData() -> AuditData {
        var audit = AuditData()
        guard let data = fm.contents(atPath: auditFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return audit }
        audit.lastUpdated = json["last_updated"] as? String
        audit.trashGB = json["trash_size_gb"] as? Double
        audit.dupGroups = json["duplicate_groups"] as? Int
        audit.dupWastedMB = json["duplicate_wasted_mb"] as? Double
        return audit
    }

    static func isRcloneRunning() -> Bool {
        guard let pgrep = binary("pgrep") else { return false }
        let (out, code) = run(pgrep, args: ["-x", "rclone"], timeout: 3)
        return code == 0 && !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func isMounted() -> Bool {
        if let urls = fm.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: []) {
            for url in urls {
                if let name = try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName,
                   name.contains("CloudDrive") == true { return true }
            }
        }
        if let mount = binary("mount") {
            let (out, _) = run(mount, timeout: 3)
            return out.contains("CloudDrive")
        }
        return fm.fileExists(atPath: cloudDrive + "/.mounted")
    }

    // MARK: - Immich

    static func immichStatus() -> ImmichStatus {
        let st = ImmichStatus()
        guard let url = URL(string: "http://localhost:2283") else { return st }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2
        req.httpMethod = "HEAD"
        let probe = ProbeResult()
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { _, resp, _ in
            probe.reachable = (resp as? HTTPURLResponse)?.statusCode == 200
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 3)
        guard probe.reachable else { return st }
        guard let docker = binary("docker") else {
            return ImmichStatus(status: "Online (probe only)", assets: "?", online: false)
        }
        let env = [
            "DOCKER_HOST": "unix://\(home)/.colima/default/docker.sock",
            "PATH": "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:\(ProcessInfo.processInfo.environment["PATH"] ?? "")",
        ]
        let (out, code) = run(docker,
                              args: ["exec", "immich_postgres", "psql", "-U", "postgres",
                                     "-d", "immich", "-t", "-c", "SELECT count(*) FROM asset;"],
                              timeout: 6, env: env)
        guard code == 0 else {
            return ImmichStatus(status: "Unhealthy", assets: "?", online: false)
        }
        let count = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return ImmichStatus(status: "Online (Healthy)", assets: count.isEmpty ? "?" : count, online: true)
    }

    // MARK: - Actions

    static func stopUploads() {
        guard let pkill = binary("pkill") else { return }
        _ = run(pkill, args: ["-9", "-f", "rclone"], timeout: 5)
        _ = run(pkill, args: ["-9", "-f", "batch_archive"], timeout: 5)
    }

    static func mountCloudDrive() {
        guard let rclone = binary("rclone") else { return }
        try? fm.createDirectory(atPath: cloudDrive, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: rclone)
        p.arguments = ["mount", "gdrive:MacArchive", cloudDrive,
                       "--vfs-cache-mode", "full", "--vfs-cache-max-size", "10G", "--daemon"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    static func unmountCloudDrive() {
        guard let umount = binary("umount") else { return }
        _ = run(umount, args: [cloudDrive], timeout: 10)
    }

    static func purgeStagingTrash() {
        try? fm.removeItem(atPath: stagingTrash)
    }

    static func purgeCloudBin() {
        guard let rclone = binary("rclone") else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: rclone)
        p.arguments = ["cleanup", "gdrive:"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }
}
