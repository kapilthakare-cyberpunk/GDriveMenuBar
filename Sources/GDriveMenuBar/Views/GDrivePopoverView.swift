import SwiftUI
import AppKit
import UserNotifications

@MainActor
final class GDriveStore: ObservableObject {
    @Published var tab = 0
    @Published var snap = GDriveSnapshot()
    @Published var statusLine = "Loading…"
    @Published var trend: [(String, Double)] = []
    @Published var dups: [DupGroup] = []
    private static var authRequested = false

    func refresh(forceCapacity: Bool = false) {
        if forceCapacity { GDriveService.refreshCapacity() }
        Task.detached(priority: .userInitiated) {
            var snap = GDriveService.snapshot()
            if forceCapacity { snap.cap = GDriveService.driveCapacity(forceRefresh: true) }
            let line = snap.cap.available
                ? String(format: "Drive %.1f GiB / %.0f%% · %@", snap.cap.usedGB, snap.cap.usedPct, snap.state)
                : "Drive capacity unavailable · \(snap.state)"
            if snap.cap.available { GDriveHistory.record(pct: snap.cap.usedPct) }
            let trend = GDriveHistory.dailyPeaks()
            let dups = DuplicateAudit.top()
            await MainActor.run {
                self.snap = snap
                self.statusLine = line
                self.trend = trend
                self.dups = dups
                self.checkAlerts()
            }
        }
    }

    func act(_ name: String, _ work: @escaping @Sendable () -> Void) {
        Task.detached(priority: .userInitiated) {
            work()
            await MainActor.run { self.refresh() }
        }
    }

    private func checkAlerts() {
        if !Self.authRequested {
            Self.authRequested = true
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let defaults = UserDefaults.standard
        if snap.cap.available && snap.cap.usedPct >= 90 && !defaults.bool(forKey: "tb.drive90.notified") {
            defaults.set(true, forKey: "tb.drive90.notified")
            notify(title: "Drive almost full",
                   body: String(format: "Google Drive is %.0f%% used.", snap.cap.usedPct))
        }
        if snap.cap.available && snap.cap.usedPct < 88 {
            defaults.set(false, forKey: "tb.drive90.notified")
        }
        let stagingGB = Double(snap.mac.stagingBytes) / 1_073_741_824.0
        if stagingGB >= 5 && !defaults.bool(forKey: "tb.staging5.notified") {
            defaults.set(true, forKey: "tb.staging5.notified")
            notify(title: "Staging trash is large",
                   body: String(format: "Staging trash holds %.1f GiB.", stagingGB))
        }
        if stagingGB < 4 {
            defaults.set(false, forKey: "tb.staging5.notified")
        }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}

struct GDrivePopoverView: View {
    @ObservedObject var store: GDriveStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TabPill(title: "Storage", selected: store.tab == 0) { store.tab = 0 }
                TabPill(title: "Audit", selected: store.tab == 1) { store.tab = 1 }
                TabPill(title: "Media", selected: store.tab == 2) { store.tab = 2 }
                TabPill(title: "Cloud", selected: store.tab == 3) { store.tab = 3 }
                Spacer()
                Button("Refresh") { store.refresh() }.buttonStyle(.link).font(.caption)
            }
            Text(store.statusLine).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if store.tab == 0 { storageView }
            else if store.tab == 1 { auditView }
            else if store.tab == 2 { mediaView }
            else { cloudView }
            HStack {
                Text("GDrive Manager").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.link).font(.caption)
            }
        }
        .padding(14)
        .frame(width: 400)
    }

    // MARK: - Storage

    private var storageView: some View {
        VStack(alignment: .leading, spacing: 10) {
            TBCard {
                HStack(spacing: 12) {
                    if store.snap.cap.available {
                        QuotaRing(pct: store.snap.cap.usedPct)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "%.1f GiB used · %.1f%%", store.snap.cap.usedGB, store.snap.cap.usedPct))
                                .font(TBTheme.numberFont)
                            Text("Free \(String(format: "%.1f GiB", store.snap.cap.freeGB)) · \(store.snap.state)")
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    } else {
                        Text("Drive capacity: querying… (needs rclone gdrive: remote)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            TBSectionHeader(title: "14-Day Peak Use")
            TBCard { TrendBars(points: store.trend) }
            TBSectionHeader(title: "MacBook Storage")
            TBCard {
                MetricRow(label: "Primary SSD free", value: String(format: "%.1f GiB", store.snap.mac.freeGB), color: TBTheme.blue)
                MetricRow(label: "Used", value: String(format: "%.1f GiB", store.snap.mac.usedGB), color: TBTheme.gray)
                MetricRow(label: "Staging Trash", value: store.snap.mac.stagingTrash, color: TBTheme.orange)
                HStack {
                    Button("Empty Staging Trash") { store.act("purge") { GDriveService.purgeStagingTrash() } }
                        .buttonStyle(.link).font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("Refresh metrics") { store.refresh(forceCapacity: true) }
                        .buttonStyle(.link).font(.caption)
                }
            }
        }
    }

    // MARK: - Audit

    private var auditView: some View {
        VStack(alignment: .leading, spacing: 10) {
            TBSectionHeader(title: "Integrity & Audit")
            TBCard {
                MetricRow(label: "Duplicates", value: dupString, color: TBTheme.orange)
                MetricRow(label: "Drive Bin", value: binString, color: TBTheme.orange)
                MetricRow(label: "Reclaimable", value: reclaimString, color: TBTheme.green)
                MetricRow(label: "Last audit", value: store.snap.audit.lastUpdated ?? "—", color: TBTheme.gray)
                HStack {
                    Button("Empty Drive bin") { store.act("bin") { GDriveService.purgeCloudBin() } }
                        .buttonStyle(.link).font(.caption).foregroundStyle(.red)
                    Spacer()
                    Button("Open Drive trash") { NSWorkspace.shared.open(URL(string: "https://drive.google.com/drive/trash")!) }
                        .buttonStyle(.link).font(.caption)
                }
            }
            TBSectionHeader(title: "Top Duplicates")
            TBCard {
                if store.dups.isEmpty {
                    Text("No duplicate audit yet — run a scan to populate this list.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(store.dups.indices, id: \.self) { i in
                        HStack {
                            Text(store.dups[i].name).font(.body).lineLimit(1)
                            Spacer()
                            Text(store.dups[i].detail).font(.caption).foregroundStyle(.secondary)
                            if let path = store.dups[i].path {
                                Button("Reveal") {
                                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                                }.buttonStyle(.link).font(.caption)
                            }
                        }
                        Divider().opacity(0.4)
                    }
                }
            }
        }
    }

    private var dupString: String {
        if let g = store.snap.audit.dupGroups, let mb = store.snap.audit.dupWastedMB {
            return "\(g) groups / \(String(format: "%.0f", mb)) MB"
        }
        return "no audit yet"
    }

    private var binString: String {
        if let t = store.snap.audit.trashGB { return String(format: "%.2f GiB", t) }
        return "—"
    }

    private var reclaimString: String {
        let trash = store.snap.audit.trashGB ?? 0
        let staging = Double(store.snap.mac.stagingBytes) / 1_073_741_824.0
        return String(format: "%.2f GiB", trash + staging)
    }

    // MARK: - Media

    private var mediaView: some View {
        VStack(alignment: .leading, spacing: 10) {
            TBSectionHeader(title: "Immich Photos")
            TBCard {
                MetricRow(label: "Server", value: store.snap.immich.status,
                          color: store.snap.immich.online ? TBTheme.green : TBTheme.red)
                MetricRow(label: "Library", value: "\(store.snap.immich.assets) photos & videos", color: TBTheme.blue)
                Button("Open Immich web app") {
                    NSWorkspace.shared.open(URL(string: "http://localhost:2283")!)
                }.buttonStyle(.link).font(.caption)
            }
            TBSectionHeader(title: "Archival Queue")
            TBCard {
                ForEach(archivalRows, id: \.0) { name, label, ok in
                    HStack {
                        Text(name).font(.body).lineLimit(1)
                        Spacer()
                        Text(label).font(.caption)
                            .foregroundStyle(ok ? TBTheme.green : TBTheme.orange)
                    }
                    Divider().opacity(0.4)
                }
            }
        }
    }

    private var archivalRows: [(String, String, Bool)] {
        [("Documents", "Verified & Staged", true),
         ("Desktop", "Verified & Staged", true),
         ("backups", "Verified & Staged", true),
         ("GoogleDriveSync", "Verified & Staged", true),
         ("Downloads", "Pending Upload", false),
         ("Pictures", "Pending Upload", false),
         ("Music", "Pending Upload", false)]
    }

    // MARK: - Cloud

    private var cloudView: some View {
        VStack(alignment: .leading, spacing: 10) {
            TBSectionHeader(title: "Cloud Streaming")
            TBCard {
                MetricRow(label: "rclone", value: store.snap.running ? "Active" : "Idle",
                          color: store.snap.running ? TBTheme.green : TBTheme.gray)
                MetricRow(label: "CloudDrive", value: store.snap.mounted ? "Mounted" : "Not mounted",
                          color: store.snap.mounted ? TBTheme.green : TBTheme.orange)
                HStack {
                    if store.snap.mounted {
                        Button("Unmount CloudDrive") { store.act("unmount") { GDriveService.unmountCloudDrive() } }
                            .buttonStyle(.link).font(.caption).foregroundStyle(.orange)
                    } else {
                        Button("Mount CloudDrive") { store.act("mount") { GDriveService.mountCloudDrive() } }
                            .buttonStyle(.link).font(.caption).foregroundStyle(TBTheme.green)
                    }
                    Spacer()
                    Button("Open folder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory() + "/CloudDrive"))
                    }.buttonStyle(.link).font(.caption)
                }
                if store.snap.running {
                    Button("Stop uploads") { store.act("stop") { GDriveService.stopUploads() } }
                        .buttonStyle(.link).font(.caption).foregroundStyle(.red)
                }
            }
            TBCard {
                Button("Open Drive web console") {
                    NSWorkspace.shared.open(URL(string: "https://drive.google.com")!)
                }.buttonStyle(.link).font(.caption)
            }
        }
    }
}

private struct TrendBars: View {
    let points: [(String, Double)]
    var body: some View {
        if points.count < 2 {
            Text("Collecting history… check back after a few refreshes.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(points.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(TBTheme.usageColor(points[i].1))
                            .frame(height: max(4, points[i].1 / 100 * 56))
                            .help("\(points[i].0): \(Int(points[i].1))%")
                    }
                }.frame(height: 60)
                Text("Daily peak use · \(Int(points.map(\.1).min() ?? 0))–\(Int(points.map(\.1).max() ?? 0))%")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

private struct MetricRow: View {
    let label: String
    let value: String
    let color: Color
    var body: some View {
        HStack {
            Text(label).font(.body)
            Spacer()
            Text(value).font(TBTheme.numberFont).foregroundStyle(color)
        }
    }
}
