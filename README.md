# GDriveMenuBar

macOS menu-bar app for Google Drive storage, Mac disk usage, Immich, and
rclone CloudDrive streaming. Native Swift/AppKit + SwiftUI, TokenBar-style UI.

## Requirements

- macOS 14+
- Swift 6 toolchain (Xcode Command Line Tools)
- `rclone` configured with a `gdrive:` remote (Drive capacity + CloudDrive mount)
- Optional: `docker` with the `immich_postgres` container (Immich library count)

## Build & Run

```bash
swift build
swift run            # development
swift build -c release
```

The menu bar shows Drive usage percent (or the rclone state when capacity is
unavailable). Click it for the popover.

## Tabs

- **Storage** — Drive quota ring, 14-day peak-use trend, Mac SSD usage.
- **Audit** — duplicate groups, Drive Bin size, reclaimable space.
- **Media** — Immich server health and asset count, archival queue.
- **Cloud** — mount/unmount CloudDrive, stop uploads, open Drive console.

## Shared data

This app mirrors the `gdrive_manager.10s.py` SwiftBar plugin and reads the same
files, so the two stay in sync:

| File | Purpose |
|------|---------|
| `/tmp/gdrive_about_cache.json` | Drive capacity, 60s TTL shared with the plugin |
| `/tmp/gdrive_audit_results.json` | Last audit summary (bin size, duplicate totals) |
| `~/.local_staging_trash` | Staging trash directory measured on the Storage tab |
| `~/CloudDrive` | rclone mount point |
| `.../duplicate_files.csv` | Duplicate-audit CSV (overridable via `GDRIVE_MANAGER_SCRATCH`) |

## Environment

- `GDRIVE_MANAGER_SCRATCH` — override the audit scratch directory.
- `GDRIVE_DEBUG` — set to any value to write `/tmp/GDriveMenuBar.debug.log`.

## Structure

```
Sources/GDriveMenuBar/
  App.swift                  NSApplication entry point
  StatusBarController.swift  Status item, popover, 30s refresh timer
  Models/GDriveSnapshot.swift
  Services/
    GDriveService.swift      rclone/docker probes, capacity cache, actions
    GDriveHistory.swift      local capacity history (JSONL)
    DuplicateAudit.swift     tolerant duplicate-CSV reader
  Theme/TokenBarTheme.swift  shared design tokens and components
  Views/GDrivePopoverView.swift
```
