import Foundation

struct DriveCapacity {
    var totalGB: Double = 0
    var usedGB: Double = 0
    var freeGB: Double = 0
    var trashedGB: Double = 0
    var usedPct: Double = 0
    var available: Bool = false
}

struct MacAudit {
    var totalGB: Double = 0
    var usedGB: Double = 0
    var freeGB: Double = 0
    var volumes: [String] = ["None (Primary SSD Only)"]
    var stagingTrash: String = "—"
    var stagingBytes: UInt64 = 0
}

struct AuditData {
    var lastUpdated: String?
    var trashGB: Double?
    var dupGroups: Int?
    var dupWastedMB: Double?
}

struct ImmichStatus {
    var status: String = "Offline"
    var assets: String = "0"
    var online: Bool = false
}

struct GDriveSnapshot {
    var running: Bool = false
    var mounted: Bool = false
    var state: String { running ? "Active" : (mounted ? "Mounted" : "Idle") }
    var cap = DriveCapacity()
    var mac = MacAudit()
    var audit = AuditData()
    var immich = ImmichStatus()
}
