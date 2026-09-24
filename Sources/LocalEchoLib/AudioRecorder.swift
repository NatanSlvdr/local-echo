import CoreAudio
import Foundation

final class AudioRecorder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "LocalEcho.AudioRecorder", qos: .userInitiated)
    private var capture: AudioCaptureUnit?
    private var currentOutputURL: URL?
    private var selectedDeviceID: AudioDeviceID?
    private var shouldDuckOtherAudio = false
    private let volumeDucker = OutputVolumeDucker()

    var preferredDeviceID: AudioDeviceID? {
        get { queue.sync { selectedDeviceID } }
        set { queue.async { self.selectedDeviceID = newValue } }
    }

    var duckOtherAudio: Bool {
        get { queue.sync { shouldDuckOtherAudio } }
        set {
            queue.async {
                self.shouldDuckOtherAudio = newValue
                guard self.currentOutputURL != nil else { return }
                if newValue, #available(macOS 14.0, *) {
                    self.volumeDucker.start(deviceID: AudioDeviceManager.getDefaultOutputDeviceID())
                } else {
                    self.volumeDucker.stop()
                }
            }
        }
    }

    func prepare() {
        queue.async {
            guard self.currentOutputURL == nil else { return }
            do {
                _ = try self.configuredCapture()
            } catch {
                self.capture = nil
                print("Microphone preparation failed: \(error.localizedDescription)")
            }
        }
    }

    func teardown() {
        queue.sync {
            volumeDucker.restoreImmediately()
            capture = nil
            currentOutputURL = nil
        }
    }

    private func configuredCapture() throws -> AudioCaptureUnit {
        let defaultInput = AudioDeviceManager.getDefaultInputDeviceID()
        let route = AudioEngineCacheState.Route(
            inputDeviceID: selectedDeviceID ?? defaultInput,
            outputDeviceID: AudioDeviceManager.getDefaultOutputDeviceID(),
            defaultInputDeviceID: defaultInput
        )
        if let capture, capture.cacheState.canReuse(for: route) { return capture }
        capture = nil
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let configured = try AudioCaptureUnit(route: route, voiceProcessing: false)
        capture = configured
        print("Audio setup: \((DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000) ms; input=\(route.inputDeviceID), output=\(route.outputDeviceID)")
        return configured
    }

    func startRecording(to outputURL: URL) throws {
        let requestedAt = DispatchTime.now().uptimeNanoseconds
        try queue.sync {
            guard currentOutputURL == nil else { return }
            do {
                let capture = try configuredCapture()
                try capture.start(to: outputURL, requestedAt: requestedAt)
                currentOutputURL = outputURL
                if shouldDuckOtherAudio, #available(macOS 14.0, *) {
                    volumeDucker.start(deviceID: capture.cacheState.route.outputDeviceID)
                }
                print("Microphone ready in \((DispatchTime.now().uptimeNanoseconds - requestedAt) / 1_000_000) ms")
            } catch {
                capture = nil
                throw error
            }
        }
    }

    func stopRecording() -> URL? {
        return queue.sync {
            guard let url = currentOutputURL else { return nil }
            currentOutputURL = nil
            volumeDucker.stop()
            do {
                try capture?.stop()
                return url
            } catch {
                capture = nil
                try? FileManager.default.removeItem(at: url)
                print("Recording failed: \(error.localizedDescription)")
                return nil
            }
        }
    }
}
