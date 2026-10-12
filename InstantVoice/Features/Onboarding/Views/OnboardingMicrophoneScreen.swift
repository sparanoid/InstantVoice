import CoreAudio
import SwiftUI

struct OnboardingMicrophoneScreen: View {
    let onBack: () -> Void
    let onContinue: () -> Void

    @ObservedObject private var audioDeviceManager = AudioDeviceManager.shared
    @State private var selectedDeviceUID: String?

    private typealias MicrophoneDevice = (id: AudioDeviceID, uid: String, name: String)

    var body: some View {
        OnboardingPage(
            navigation: OnboardingNavigationBar(
                onBack: onBack,
                isPrimaryEnabled: selectedDevice != nil,
                onPrimary: saveSelectionAndContinue
            )
        ) {
            OnboardingPageHeader(
                systemImage: OnboardingStage.microphone.systemImage,
                tint: OnboardingStage.microphone.tint,
                title: OnboardingStage.microphone.title,
                subtitle: OnboardingStage.microphone.subtitle
            )
        } content: {
            Section {
                if devices.isEmpty {
                    ContentUnavailableView {
                        Label("No microphones found", systemImage: "mic.slash")
                    } description: {
                        Text("Connect a microphone or allow microphone access, then refresh.")
                    }
                } else {
                    ForEach(devices, id: \.uid) { device in
                        microphoneRow(for: device)
                    }
                }
            } header: {
                HStack {
                    Text("Available Microphones")

                    Spacer()

                    Button("Refresh", systemImage: "arrow.clockwise") {
                        refreshMicrophones(selectingIfNeeded: false)
                    }
                    .buttonStyle(.borderless)
                    .labelStyle(.titleAndIcon)
                    .help("Refresh Microphones")
                }
            }
        }
        .onAppear {
            refreshMicrophones(selectingIfNeeded: true)
            initializeSelectionIfNeeded()
        }
        .onChange(of: audioDeviceManager.availableDevices.map(\.uid)) { _, _ in
            ensureSelectionIsAvailable()
        }
    }

    private func microphoneRow(for device: MicrophoneDevice) -> some View {
        let isSelected = selectedDeviceUID == device.uid

        return Button {
            selectedDeviceUID = device.uid
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "mic")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)

                Text(device.name)
                    .lineLimit(1)

                Spacer(minLength: 12)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var devices: [MicrophoneDevice] {
        audioDeviceManager.availableDevices
    }

    private var selectedDevice: MicrophoneDevice? {
        guard let selectedDeviceUID else { return nil }
        return devices.first { $0.uid == selectedDeviceUID }
    }

    private func refreshMicrophones(selectingIfNeeded: Bool) {
        audioDeviceManager.loadAvailableDevices {
            if selectingIfNeeded {
                initializeSelectionIfNeeded()
            } else {
                ensureSelectionIsAvailable()
            }
        }
    }

    private func initializeSelectionIfNeeded() {
        guard selectedDevice == nil else { return }

        if let savedDeviceID = audioDeviceManager.selectedDeviceID,
            let savedDevice = devices.first(where: { $0.id == savedDeviceID })
        {
            selectedDeviceUID = savedDevice.uid
            return
        }

        if let savedDeviceUID = UserDefaults.standard.selectedAudioDeviceUID,
            let savedDevice = devices.first(where: { $0.uid == savedDeviceUID })
        {
            selectedDeviceUID = savedDevice.uid
            return
        }

        if let defaultDeviceID = audioDeviceManager.getSystemDefaultDevice(),
            let defaultDevice = devices.first(where: { $0.id == defaultDeviceID })
        {
            selectedDeviceUID = defaultDevice.uid
            return
        }

        selectedDeviceUID = devices.first?.uid
    }

    private func ensureSelectionIsAvailable() {
        if selectedDevice == nil {
            selectedDeviceUID = nil
            initializeSelectionIfNeeded()
        }
    }

    private func saveSelectionAndContinue() {
        guard let selectedDevice else { return }
        guard audioDeviceManager.availableDevices.contains(where: { $0.uid == selectedDevice.uid }) else {
            selectedDeviceUID = nil
            refreshMicrophones(selectingIfNeeded: true)
            return
        }

        audioDeviceManager.selectDeviceAndSwitchToCustomMode(id: selectedDevice.id)

        DispatchQueue.main.async {
            onContinue()
        }
    }
}
