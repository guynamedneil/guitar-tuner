import SwiftUI

// MARK: - Tuner View

/// Main tuner interface displaying note detection, cents offset, and audio controls
struct TunerView: View {
    @State private var viewModel: TunerViewModel
    @Environment(\.scenePhase) private var scenePhase

    init(audioInputMode: AudioInputMode = .mockGlide) {
        _viewModel = State(initialValue: TunerViewModel(audioInputMode: audioInputMode))
    }

    private var needsMicrophonePermission: Bool {
        viewModel.audioInputMode == .real && viewModel.microphonePermissionStatus != .granted
    }

    var body: some View {
        Group {
            if needsMicrophonePermission {
                MicrophonePermissionView(
                    permissionStatus: viewModel.microphonePermissionStatus,
                    onRequestPermission: viewModel.requestMicrophonePermission,
                    onOpenSettings: viewModel.openMicrophoneSettings
                )
            } else {
                tunerContent
            }
        }
        .onAppear(perform: viewModel.checkMicrophonePermission)
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.handleAppActiveStateChange(isActive: newPhase == .active)
        }
    }

    // MARK: - Tuner Content

    private var tunerContent: some View {
        VStack(spacing: 40) {
            Spacer()

            noteDisplay
            centsDisplay

            Spacer()

            controlButton
            debugSection

            Spacer()
        }
        .padding()
    }

    // MARK: - Note Display

    private var noteDisplay: some View {
        Text(viewModel.currentNote)
            .font(.system(size: 120, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(minHeight: 140)
    }

    // MARK: - Cents Display

    private var centsDisplay: some View {
        HStack(spacing: 4) {
            Text(centsText)
                .font(.system(size: 32, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("cents")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.tertiary)
        }
    }

    private var centsText: String {
        String(format: "%+.0f", viewModel.centsOffset)
    }

    // MARK: - Control Button

    private var controlButton: some View {
        Button(viewModel.isAudioRunning ? "Stop" : "Start") {
            viewModel.toggleTuning()
        }
        .font(.title2)
        .fontWeight(.semibold)
        .frame(minWidth: 120)
        .padding(.vertical, 12)
        .padding(.horizontal, 24)
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isAudioRunning ? .red : .blue)
    }

    // MARK: - Debug Section

    private var debugSection: some View {
        VStack(spacing: 4) {
            Text("audio: \(viewModel.isAudioRunning ? "running" : "stopped")")
            Text("mode: \(viewModel.audioInputMode.description)")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 8)
    }
}

// MARK: - Preview

#Preview("Mock Glide Mode") {
    TunerView(audioInputMode: .mockGlide)
}

#Preview("Mock Step Notes Mode") {
    TunerView(audioInputMode: .mockStepNotes)
}

#Preview("Real Audio Mode") {
    TunerView(audioInputMode: .real)
}
