import SwiftUI

// MARK: - Microphone Permission View

/// View displayed when microphone permission is denied or not yet determined
struct MicrophonePermissionView: View {
    let permissionStatus: MicrophonePermissionStatus
    let onRequestPermission: () async -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            microphoneIcon
            titleText
            explanationText

            Spacer()

            actionButton

            Spacer()
        }
        .padding()
    }

    // MARK: - Microphone Icon

    private var microphoneIcon: some View {
        Image(systemName: permissionStatus == .denied ? "mic.slash.fill" : "mic.fill")
            .font(.system(size: 80))
            .foregroundStyle(permissionStatus == .denied ? .red : .secondary)
    }

    // MARK: - Title Text

    private var titleText: some View {
        Text("Enable Microphone")
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
    }

    // MARK: - Explanation Text

    private var explanationText: some View {
        Text("Guitar Tuner needs microphone access to hear your guitar and detect its pitch. Without microphone access, the tuner cannot work.")
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
    }

    // MARK: - Action Button

    private var actionButton: some View {
        Group {
            if permissionStatus == .denied {
                Button("Open Settings", action: onOpenSettings)
            } else {
                Button("Allow Microphone Access") {
                    Task {
                        await onRequestPermission()
                    }
                }
            }
        }
        .font(.title2)
        .fontWeight(.semibold)
        .frame(minWidth: 160)
        .padding(.vertical, 12)
        .padding(.horizontal, 24)
        .buttonStyle(.borderedProminent)
    }
}

// MARK: - Preview

#Preview("Permission Not Determined") {
    MicrophonePermissionView(
        permissionStatus: .notDetermined,
        onRequestPermission: {},
        onOpenSettings: {}
    )
}

#Preview("Permission Denied") {
    MicrophonePermissionView(
        permissionStatus: .denied,
        onRequestPermission: {},
        onOpenSettings: {}
    )
}
