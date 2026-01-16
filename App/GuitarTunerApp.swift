import SwiftUI

// MARK: - App Entry Point

@main
struct GuitarTunerApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            TunerView(audioInputMode: .mockStepNotes)
            #else
            TunerView(audioInputMode: .real)
            #endif
        }
    }
}
