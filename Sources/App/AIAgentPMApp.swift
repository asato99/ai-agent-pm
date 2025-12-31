// Sources/App/AIAgentPMApp.swift
// SwiftUI Mac App エントリーポイント

import SwiftUI

@main
struct AIAgentPMApp: App {
    @StateObject private var container: DependencyContainer
    @State private var router = Router()

    init() {
        // Initialize container - any error here is fatal
        let newContainer: DependencyContainer
        do {
            newContainer = try DependencyContainer()
        } catch {
            fatalError("Failed to initialize DependencyContainer: \(error)")
        }
        _container = StateObject(wrappedValue: newContainer)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(container)
                .environment(router)
        }
        .commands {
            // File Menu
            CommandGroup(replacing: .newItem) {
                Button("New Project") {
                    router.showSheet(.newProject)
                }
                .keyboardShortcut("n", modifiers: [.command])

                if let projectId = router.selectedProject {
                    Divider()

                    Button("New Task") {
                        router.showSheet(.newTask(projectId))
                    }
                    .keyboardShortcut("t", modifiers: [.command])

                    Button("New Agent") {
                        router.showSheet(.newAgent(projectId))
                    }
                    .keyboardShortcut("a", modifiers: [.command, .shift])
                }
            }

            // View Menu additions
            CommandGroup(after: .sidebar) {
                Divider()

                Button("Refresh") {
                    // Trigger refresh
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(container)
        }
    }
}
