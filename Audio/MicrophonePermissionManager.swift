import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Microphone Permission Status

/// Represents the current state of microphone permission
enum MicrophonePermissionStatus {
    /// Permission has not been requested yet
    case notDetermined
    /// User denied microphone access
    case denied
    /// User granted microphone access
    case granted

    /// Creates a status from AVAudioSession.RecordPermission
    init(recordPermission: AVAudioSession.RecordPermission) {
        switch recordPermission {
        case .undetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .granted:
            self = .granted
        @unknown default:
            self = .notDetermined
        }
    }
}

// MARK: - Microphone Permission Manager

/// Manages microphone permission requests and status checking
@MainActor
final class MicrophonePermissionManager {
    /// Returns the current microphone permission status
    var currentStatus: MicrophonePermissionStatus {
        MicrophonePermissionStatus(recordPermission: AVAudioSession.sharedInstance().recordPermission)
    }

    /// Requests microphone permission from the user
    /// - Returns: The resulting permission status after the request
    func requestPermission() async -> MicrophonePermissionStatus {
        AudioLogger.audio.info("Requesting microphone permission")

        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                let status: MicrophonePermissionStatus = granted ? .granted : .denied
                AudioLogger.audio.info("Microphone permission result: \(granted ? "granted" : "denied")")
                continuation.resume(returning: status)
            }
        }
    }

    /// Opens the system Settings app to the app's settings page
    func openSettings() {
        #if canImport(UIKit)
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            AudioLogger.audio.error("Failed to create Settings URL")
            return
        }

        AudioLogger.audio.info("Opening Settings app")
        UIApplication.shared.open(settingsURL)
        #endif
    }
}
