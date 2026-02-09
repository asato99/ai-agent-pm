// Sources/App/Features/Settings/DatabaseSettingsView.swift
// データベース設定タブ

import SwiftUI
import AppKit
import Infrastructure

struct DatabaseSettingsView: View {
    @State private var databasePath: String = ""
    @State private var databaseSize: String = "Unknown"

    var body: some View {
        Form {
            Section("Database Location") {
                LabeledContent("Path") {
                    Text(databasePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Size") {
                    Text(databaseSize)
                }

                Button("Reveal in Finder") {
                    revealInFinder()
                }
            }

            Section("Maintenance") {
                Button("Optimize Database") {
                    optimizeDatabase()
                }

                Button("Export Data...") {
                    exportData()
                }

                Button("Import Data...") {
                    importData()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .task {
            loadDatabaseInfo()
        }
    }

    private func loadDatabaseInfo() {
        // AppConfigから統一されたDBパスを取得
        databasePath = AppConfig.databasePath

        if let attributes = try? FileManager.default.attributesOfItem(atPath: databasePath),
           let size = attributes[.size] as? Int64 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            databaseSize = formatter.string(fromByteCount: size)
        }
    }

    private func revealInFinder() {
        if let url = URL(string: "file://\(databasePath)") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func optimizeDatabase() {
        // TODO: Implement database optimization (VACUUM)
    }

    private func exportData() {
        // TODO: Implement data export
    }

    private func importData() {
        // TODO: Implement data import
    }
}
