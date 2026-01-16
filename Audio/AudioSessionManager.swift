import AVFoundation
import Combine

// MARK: - Audio Session State

/// Represents the current state of the audio session
enum AudioSessionState {
    case inactive
    case active
    case interrupted
}

// MARK: - Audio Session Manager

/// Manages AVAudioSession configuration, notifications, and lifecycle for low-latency measurement mode
final class AudioSessionManager {
    // MARK: - Configuration Constants

    /// Preferred sample rate for audio capture (44.1 kHz is standard for music applications)
    private let preferredSampleRate: Double = 44100.0

    /// Preferred I/O buffer duration for low latency (5ms)
    private let preferredBufferDuration: TimeInterval = 0.005

    // MARK: - Published State

    /// Current state of the audio session
    private(set) var state: AudioSessionState = .inactive

    /// Publisher for interruption events
    let interruptionPublisher = PassthroughSubject<AudioInterruptionEvent, Never>()

    /// Publisher for route change events
    let routeChangePublisher = PassthroughSubject<AudioRouteChangeEvent, Never>()

    // MARK: - Private Properties

    private let session = AVAudioSession.sharedInstance()

    // MARK: - Initialization

    init() {
        setupNotificationObservers()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Configuration

    /// Configures the audio session with measurement-friendly settings for accurate pitch detection
    func configure() throws {
        AudioLogger.audio.info("Configuring audio session for measurement mode")

        do {
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.defaultToSpeaker, .allowBluetooth]
            )
            try session.setPreferredSampleRate(preferredSampleRate)
            try session.setPreferredIOBufferDuration(preferredBufferDuration)
        } catch {
            AudioLogger.audio.error("Failed to configure audio session: \(error.localizedDescription)")
            throw AudioSessionError.configurationFailed(underlying: error)
        }

        AudioLogger.audio.info(
            """
            Audio session configured - \
            category: playAndRecord, \
            mode: measurement, \
            preferredSampleRate: \(self.preferredSampleRate) Hz, \
            preferredBufferDuration: \(self.preferredBufferDuration * 1000) ms
            """
        )

        AudioLogger.audio.debug(
            """
            Actual session values - \
            sampleRate: \(self.session.sampleRate) Hz, \
            ioBufferDuration: \(self.session.ioBufferDuration * 1000) ms
            """
        )
    }

    /// Activates the audio session
    func activate() throws {
        guard state != .active else {
            AudioLogger.audio.debug("Audio session already active")
            return
        }

        do {
            try session.setActive(true, options: [])
            state = .active
            AudioLogger.audio.info("Audio session activated")

            logCurrentRoute()
        } catch {
            AudioLogger.audio.error("Failed to activate audio session: \(error.localizedDescription)")
            throw AudioSessionError.activationFailed(underlying: error)
        }
    }

    /// Deactivates the audio session
    func deactivate() {
        guard state != .inactive else {
            AudioLogger.audio.debug("Audio session already inactive")
            return
        }

        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            state = .inactive
            AudioLogger.audio.info("Audio session deactivated")
        } catch {
            // Deactivation failure is not critical - log but don't throw
            AudioLogger.audio.warning("Failed to deactivate audio session: \(error.localizedDescription)")
            state = .inactive
        }
    }

    // MARK: - Route Information

    /// Logs the current audio route for debugging
    func logCurrentRoute() {
        let currentRoute = session.currentRoute

        let inputs = currentRoute.inputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
        let outputs = currentRoute.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")

        AudioLogger.audio.info(
            """
            Current audio route - \
            inputs: [\(inputs.isEmpty ? "none" : inputs)], \
            outputs: [\(outputs.isEmpty ? "none" : outputs)]
            """
        )
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: session
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: session
        )

        AudioLogger.audio.debug("Audio session notification observers registered")
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            AudioLogger.audio.warning("Received interruption notification with invalid data")
            return
        }

        switch type {
        case .began:
            state = .interrupted
            AudioLogger.audio.info("Audio session interruption began")
            interruptionPublisher.send(.began)

        case .ended:
            let shouldResume: Bool
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                shouldResume = options.contains(.shouldResume)
            } else {
                shouldResume = false
            }

            state = .inactive
            AudioLogger.audio.info("Audio session interruption ended - shouldResume: \(shouldResume)")
            interruptionPublisher.send(.ended(shouldResume: shouldResume))

        @unknown default:
            AudioLogger.audio.warning("Received unknown interruption type: \(typeValue)")
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            AudioLogger.audio.warning("Received route change notification with invalid data")
            return
        }

        let reasonDescription = routeChangeReasonDescription(reason)
        AudioLogger.audio.info("Audio route changed - reason: \(reasonDescription)")

        // Log the previous route if available
        if let previousRoute = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
            let previousInputs = previousRoute.inputs.map { $0.portName }.joined(separator: ", ")
            let previousOutputs = previousRoute.outputs.map { $0.portName }.joined(separator: ", ")
            AudioLogger.audio.debug("Previous route - inputs: [\(previousInputs)], outputs: [\(previousOutputs)]")
        }

        // Log the new current route
        logCurrentRoute()

        // Publish the route change event
        routeChangePublisher.send(AudioRouteChangeEvent(reason: reason))
    }

    private func routeChangeReasonDescription(_ reason: AVAudioSession.RouteChangeReason) -> String {
        let descriptions: [AVAudioSession.RouteChangeReason: String] = [
            .unknown: "unknown",
            .newDeviceAvailable: "new device available",
            .oldDeviceUnavailable: "old device unavailable",
            .categoryChange: "category change",
            .override: "override",
            .wakeFromSleep: "wake from sleep",
            .noSuitableRouteForCategory: "no suitable route for category",
            .routeConfigurationChange: "route configuration change"
        ]
        return descriptions[reason] ?? "unknown (\(reason.rawValue))"
    }
}

// MARK: - Audio Interruption Event

/// Represents an audio session interruption event
enum AudioInterruptionEvent {
    /// Audio interruption began (e.g., phone call, Siri)
    case began
    /// Audio interruption ended
    /// - Parameter shouldResume: Whether the system recommends resuming audio
    case ended(shouldResume: Bool)
}

// MARK: - Audio Route Change Event

/// Represents an audio route change event
struct AudioRouteChangeEvent {
    let reason: AVAudioSession.RouteChangeReason

    /// Whether this route change likely requires stopping audio capture
    var requiresReconfiguration: Bool {
        switch reason {
        case .oldDeviceUnavailable, .noSuitableRouteForCategory:
            return true
        default:
            return false
        }
    }
}

// MARK: - Audio Session Error

/// Errors that can occur during audio session operations
enum AudioSessionError: Error, LocalizedError {
    case configurationFailed(underlying: Error)
    case activationFailed(underlying: Error)
    case inputNotAvailable

    var errorDescription: String? {
        switch self {
        case .configurationFailed(let underlying):
            return "Failed to configure audio session: \(underlying.localizedDescription)"
        case .activationFailed(let underlying):
            return "Failed to activate audio session: \(underlying.localizedDescription)"
        case .inputNotAvailable:
            return "Audio input is not available"
        }
    }
}
