import AVFoundation
import Combine

// MARK: - Audio Session Error

/// Errors that can occur during audio session management
enum AudioSessionError: Error, LocalizedError {
    case configurationFailed(underlying: Error)
    case activationFailed(underlying: Error)
    case deactivationFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .configurationFailed(let underlying):
            return "Failed to configure audio session: \(underlying.localizedDescription)"
        case .activationFailed(let underlying):
            return "Failed to activate audio session: \(underlying.localizedDescription)"
        case .deactivationFailed(let underlying):
            return "Failed to deactivate audio session: \(underlying.localizedDescription)"
        }
    }
}

// MARK: - Audio Session State

/// Represents the current state of an audio interruption
enum AudioInterruptionState {
    /// Audio was interrupted (e.g., phone call, Siri)
    case began
    /// Audio interruption ended
    case ended(shouldResume: Bool)
}

// MARK: - Audio Session Manager

/// Manages AVAudioSession configuration, interruptions, and route changes for the guitar tuner
final class AudioSessionManager {
    // MARK: - Constants

    /// Preferred sample rate for audio capture (standard CD quality)
    private static let preferredSampleRate: Double = 44100.0

    /// Preferred I/O buffer duration for low latency (~5ms)
    private static let preferredBufferDuration: TimeInterval = 0.005

    // MARK: - Published State

    /// Publisher for audio interruption events
    let interruptionPublisher = PassthroughSubject<AudioInterruptionState, Never>()

    // MARK: - Private Properties

    private let audioSession = AVAudioSession.sharedInstance()
    private var notificationObservers: [NSObjectProtocol] = []

    // MARK: - Initialization

    init() {
        setupNotificationObservers()
    }

    deinit {
        removeNotificationObservers()
    }

    // MARK: - Public Methods

    /// Configures the audio session for measurement mode with low-latency settings
    /// - Throws: `AudioSessionError.configurationFailed` if configuration fails
    func configureSession() throws {
        do {
            // Set category to playAndRecord with measurement mode for flat frequency response
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetooth]
            )

            // Set preferred sample rate for consistent audio processing
            try audioSession.setPreferredSampleRate(Self.preferredSampleRate)

            // Set preferred buffer duration for low latency
            try audioSession.setPreferredIOBufferDuration(Self.preferredBufferDuration)

            let bufferMs = Self.preferredBufferDuration * 1000
            AudioLogger.audio.info("Audio session configured - category: playAndRecord, mode: measurement, preferredSampleRate: \(Self.preferredSampleRate) Hz, preferredBufferDuration: \(bufferMs) ms")
        } catch {
            AudioLogger.audio.error("Failed to configure audio session: \(error.localizedDescription)")
            throw AudioSessionError.configurationFailed(underlying: error)
        }
    }

    /// Activates the audio session
    /// - Throws: `AudioSessionError.activationFailed` if activation fails
    func activateSession() throws {
        do {
            try audioSession.setActive(true, options: [])
            logCurrentRoute()
            AudioLogger.audio.info("Audio session activated")
        } catch {
            AudioLogger.audio.error("Failed to activate audio session: \(error.localizedDescription)")
            throw AudioSessionError.activationFailed(underlying: error)
        }
    }

    /// Deactivates the audio session
    /// - Parameter notifyOthers: Whether to notify other audio sessions that they can resume
    /// - Throws: `AudioSessionError.deactivationFailed` if deactivation fails
    func deactivateSession(notifyOthers: Bool = true) throws {
        do {
            let options: AVAudioSession.SetActiveOptions = notifyOthers ? [.notifyOthersOnDeactivation] : []
            try audioSession.setActive(false, options: options)
            AudioLogger.audio.info("Audio session deactivated")
        } catch {
            AudioLogger.audio.error("Failed to deactivate audio session: \(error.localizedDescription)")
            throw AudioSessionError.deactivationFailed(underlying: error)
        }
    }

    /// Returns the current actual sample rate of the audio session
    var currentSampleRate: Double {
        audioSession.sampleRate
    }

    /// Returns the current actual I/O buffer duration
    var currentBufferDuration: TimeInterval {
        audioSession.ioBufferDuration
    }

    // MARK: - Notification Handling

    private func setupNotificationObservers() {
        // Interruption notification observer
        let interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
        notificationObservers.append(interruptionObserver)

        // Route change notification observer
        let routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: audioSession,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
        notificationObservers.append(routeChangeObserver)

        AudioLogger.audio.debug("Audio session notification observers registered")
    }

    private func removeNotificationObservers() {
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers.removeAll()
        AudioLogger.audio.debug("Audio session notification observers removed")
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            AudioLogger.audio.warning("Received interruption notification with invalid data")
            return
        }

        switch type {
        case .began:
            AudioLogger.audio.info("Audio session interruption began")
            interruptionPublisher.send(.began)

        case .ended:
            var shouldResume = false

            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                shouldResume = options.contains(.shouldResume)
            }

            AudioLogger.audio.info("Audio session interruption ended - shouldResume: \(shouldResume)")
            interruptionPublisher.send(.ended(shouldResume: shouldResume))

        @unknown default:
            AudioLogger.audio.warning("Unknown audio session interruption type: \(typeValue)")
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            AudioLogger.audio.warning("Received route change notification with invalid data")
            return
        }

        if let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
            AudioLogger.audio.debug("Previous route - \(self.formatRoute(previousRoute))")
        }

        logCurrentRoute()
        AudioLogger.audio.info("Audio route changed - reason: \(reason.displayDescription)")
    }

    private func logCurrentRoute() {
        AudioLogger.audio.debug("Current route - \(self.formatRoute(self.audioSession.currentRoute))")
    }

    private func formatRoute(_ route: AVAudioSessionRouteDescription) -> String {
        let inputs = route.inputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
        let outputs = route.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
        return "inputs: [\(inputs)], outputs: [\(outputs)]"
    }
}

// MARK: - Route Change Reason Extension

private extension AVAudioSession.RouteChangeReason {
    var displayDescription: String {
        switch self {
        case .unknown: return "unknown"
        case .newDeviceAvailable: return "new device available"
        case .oldDeviceUnavailable: return "old device unavailable"
        case .categoryChange: return "category change"
        case .override: return "override"
        case .wakeFromSleep: return "wake from sleep"
        case .noSuitableRouteForCategory: return "no suitable route for category"
        case .routeConfigurationChange: return "route configuration change"
        @unknown default: return "unknown (\(rawValue))"
        }
    }
}
