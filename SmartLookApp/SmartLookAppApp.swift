import SwiftUI

@main
struct SmartLookAppApp: App {
    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(
            at: documents.appendingPathComponent("TrainingData", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
