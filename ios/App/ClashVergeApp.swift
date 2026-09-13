import SwiftUI

@main
struct ClashVergeApp: App {
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .tint(.purple)
                .task { await store.prepare() }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        await store.reload()
                        do { try await Task.sleep(for: .seconds(3)) }
                        catch { return }
                    }
                }
                .onOpenURL { url in
                    Task { await store.open(url) }
                }
        }
    }
}
