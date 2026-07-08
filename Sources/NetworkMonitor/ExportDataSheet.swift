import NetworkMonitorCore
import SwiftUI
import Foundation
import AppKit

enum ExportTimeRange: String, CaseIterable {
    case week7
    case month30
    case all

    var displayName: String {
        switch self {
        case .week7: return L10n.tr("7 days")
        case .month30: return L10n.tr("30 days")
        case .all: return L10n.tr("All")
        }
    }
}

enum ExportFileFormat: String, CaseIterable {
    case csv = "CSV"
    case json = "JSON"
}

struct ExportDataSheet: View {
    @Binding var isPresented: Bool
    let theme: ThemeColors
    @State private var timeRange: ExportTimeRange = .week7
    @State private var includeDaily = true
    @State private var includeMinutely = false
    @State private var includeProcesses = false
    @State private var fileFormat: ExportFileFormat = .csv
    @State private var exporting = false

    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.tr("Export Data")).font(.system(size: 14, weight: .semibold)).foregroundColor(theme.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.tr("Time Range")).font(.system(size: 12, weight: .medium)).foregroundColor(theme.textMuted)
                Picker("", selection: $timeRange) {
                    ForEach(ExportTimeRange.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("Data Type")).font(.system(size: 12, weight: .medium)).foregroundColor(theme.textMuted)
                Toggle(L10n.tr("Daily Summary"), isOn: $includeDaily).font(.system(size: 12))
                Toggle(L10n.tr("Minutely Detail"), isOn: $includeMinutely).font(.system(size: 12))
                Toggle(L10n.tr("Process Record"), isOn: $includeProcesses).font(.system(size: 12))
                    .disabled(!includeMinutely)
                    .opacity(includeMinutely ? 1.0 : 0.4)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("File Format")).font(.system(size: 12, weight: .medium)).foregroundColor(theme.textMuted)
                Picker("", selection: $fileFormat) {
                    ForEach(ExportFileFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Button(L10n.tr("Cancel")) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.tr("Export")) { performExport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(exporting || (!includeDaily && !includeMinutely))
            }
        }
        .padding(20).frame(width: 340)
    }

    private func performExport() {
        exporting = true
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "NetMonitor-\(safeFilenameDate()).zip"
        panel.title = L10n.tr("Export Data")
        guard panel.runModal() == .OK, let url = panel.url else { exporting = false; return }

        let range = timeRange
        let fmt = fileFormat
        let wantDaily = includeDaily
        let wantMinutely = includeMinutely

        Task.detached(priority: .userInitiated) {
            let db = DatabaseManager.shared
            guard let db else {
                await MainActor.run { exporting = false; isPresented = false }
                LogService.error("export_no_db", detail: "DatabaseManager.shared is nil")
                return
            }
            let (from, to) = Self.dateRange(for: range)
            let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            } catch {
                await MainActor.run { exporting = false; isPresented = false }
                LogService.error("export_create_dir_failed", detail: error.localizedDescription)
                return
            }
            var files: [String] = []

            if wantDaily {
                let content: String
                if fmt == .csv { content = db.exportDailyCSV(from: from, to: to) } else { content = db.exportDailyJSON(from: from, to: to) }
                let ext = fmt == .csv ? "csv" : "json"
                let name = "daily.\(ext)"
                do {
                    try content.write(to: tmpDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
                    files.append(name)
                } catch {
                    LogService.error("export_write_daily_failed", detail: error.localizedDescription)
                }
            }
            if wantMinutely {
                let content: String
                if fmt == .csv { content = db.exportMinutelyCSV(from: from, to: to) } else { content = db.exportMinutelyJSON(from: from, to: to) }
                let ext = fmt == .csv ? "csv" : "json"
                let name = "minutely.\(ext)"
                do {
                    try content.write(to: tmpDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
                    files.append(name)
                } catch {
                    LogService.error("export_write_minutely_failed", detail: error.localizedDescription)
                }
            }

            guard !files.isEmpty else {
                try? FileManager.default.removeItem(at: tmpDir)
                await MainActor.run { exporting = false; isPresented = false }
                LogService.error("export_no_files", detail: "no export files produced")
                return
            }

            let zipPath = url.path
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-j", zipPath] + files
            process.currentDirectoryURL = tmpDir
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    LogService.error("export_zip_failed", detail: "zip exit code: \(process.terminationStatus)")
                    try? FileManager.default.removeItem(at: tmpDir)
                    await MainActor.run { exporting = false; isPresented = false }
                    return
                }
            } catch {
                LogService.error("export_zip_failed", detail: error.localizedDescription)
                try? FileManager.default.removeItem(at: tmpDir)
                await MainActor.run { exporting = false; isPresented = false }
                return
            }

            try? FileManager.default.removeItem(at: tmpDir)

            await MainActor.run {
                exporting = false
                isPresented = false
                LogService.log(.userAction, event: "data_exported", detail: "range=\(range.displayName),format=\(fmt.rawValue)")
                NSWorkspace.shared.selectFile(zipPath, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
            }
        }
    }

    private nonisolated static func dateRange(for range: ExportTimeRange) -> (Date, Date) {
        let to = Date()
        let from: Date
        switch range {
        case .week7:
            from = Calendar.current.date(byAdding: .day, value: -7, to: to) ?? Date(timeIntervalSinceNow: -604800)
        case .month30:
            from = Calendar.current.date(byAdding: .day, value: -30, to: to) ?? Date(timeIntervalSinceNow: -2592000)
        case .all:
            from = Calendar.current.date(byAdding: .year, value: -10, to: to) ?? Date(timeIntervalSinceNow: -315360000)
        }
        return (from, to)
    }
}
