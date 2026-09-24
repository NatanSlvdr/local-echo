import CoreAudio
import Foundation

class AudioRecorder {
    private let queue = DispatchQueue(label: "OpenWispr.AudioRecorder", qos: .userInitiated)
    private let duckQueue = DispatchQueue(label: "OpenWispr.AudioDucking", qos: .userInitiated)
    private let duckLock = NSLock()
    private var capture: AudioCaptureUnit?
    private var duckCapture: AudioCaptureUnit?
    private var duckGeneration = 0
    private var currentOutputURL: URL?
    private var selectedDeviceID: AudioDeviceID?
    private var shouldDuckOtherAudio = false

    var preferredDeviceID: AudioDeviceID? {
        get { queue.sync { selectedDeviceID } }
        set { queue.async { self.selectedDeviceID = newValue } }
    }

    var duckOtherAudio: Bool {
        get { queue.sync { shouldDuckOtherAudio } }
        set {
            queue.async {
                guard self.shouldDuckOtherAudio != newValue else { return }
                self.shouldDuckOtherAudio = newValue
                if newValue, self.currentOutputURL != nil, let route = self.capture?.cacheState.route {
                    self.startDucking(route: route)
                } else {
                    self.stopDucking()
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
            stopDucking(wait: true)
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
                if shouldDuckOtherAudio { startDucking(route: capture.cacheState.route) }
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
            stopDucking()
            currentOutputURL = nil
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

    // The VoiceProcessingIO unit only supplies macOS ducking; HAL always records the microphone.
    private func startDucking(route: AudioEngineCacheState.Route) {
        guard #available(macOS 14.0, *) else { return }
        let generation = nextDuckGeneration()
        duckQueue.async {
            guard self.isCurrentDuckGeneration(generation) else { return }
            do {
                let unit = try AudioCaptureUnit(route: route, voiceProcessing: true)
                guard self.isCurrentDuckGeneration(generation) else { return }
                self.duckCapture = unit
            } catch {
                print("Audio ducking unavailable: \(error.localizedDescription)")
            }
        }
    }

    private func stopDucking(wait: Bool = false) {
        _ = nextDuckGeneration()
        if wait {
            duckQueue.sync { duckCapture = nil }
        } else {
            duckQueue.async { self.duckCapture = nil }
        }
    }

    private func nextDuckGeneration() -> Int {
        duckLock.lock()
        defer { duckLock.unlock() }
        duckGeneration += 1
        return duckGeneration
    }

    private func isCurrentDuckGeneration(_ generation: Int) -> Bool {
        duckLock.lock()
        defer { duckLock.unlock() }
        return duckGeneration == generation
    }
}
