import CoreAudio
import Foundation

// Ramps the current output device's volume while dictation is active.
final class OutputVolumeDucker: @unchecked Sendable {
    private struct State {
        let deviceID: AudioDeviceID
        let originalVolume: Float32
        var lastWrittenVolume: Float32
    }

    private let queue = DispatchQueue(label: "LocalEcho.OutputVolume", qos: .userInitiated)
    private var timer: DispatchSourceTimer?
    private var state: State?

    func start(deviceID: AudioDeviceID) {
        queue.async {
            guard Self.isSettable(deviceID), let current = Self.readVolume(deviceID) else {
                print("Audio ducking unavailable: output device has no volume control")
                return
            }
            self.cancelAnimation()
            if let previous = self.state, previous.deviceID != deviceID {
                self.restore(previous)
                self.state = nil
            }
            let original = self.state?.originalVolume ?? current
            self.state = State(deviceID: deviceID, originalVolume: original, lastWrittenVolume: current)
            self.animate(from: current, to: original * 0.35, clearWhenFinished: false)
        }
    }

    func stop() {
        queue.async {
            self.cancelAnimation()
            guard let state = self.state else { return }
            guard let current = Self.readVolume(state.deviceID),
                  abs(current - state.lastWrittenVolume) < 0.02 else {
                // Preserve a volume change made by the user during dictation.
                self.state = nil
                return
            }
            self.animate(from: current, to: state.originalVolume, clearWhenFinished: true)
        }
    }

    func restoreImmediately() {
        queue.sync {
            cancelAnimation()
            if let state { restore(state) }
            state = nil
        }
    }

    private func animate(from start: Float32, to target: Float32, clearWhenFinished: Bool) {
        let startedAt = DispatchTime.now().uptimeNanoseconds
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(20), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            guard let self, var state = self.state else { return }
            guard let current = Self.readVolume(state.deviceID),
                  abs(current - state.lastWrittenVolume) < 0.02 else {
                self.cancelAnimation()
                self.state = nil
                return
            }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000_000
            let progress = Float32(min(elapsed / 0.25, 1))
            let volume = start + (target - start) * progress
            guard let written = Self.writeVolume(volume, deviceID: state.deviceID) else {
                self.cancelAnimation()
                self.state = nil
                return
            }
            state.lastWrittenVolume = written
            self.state = state
            if progress == 1 {
                self.cancelAnimation()
                if clearWhenFinished { self.state = nil }
            }
        }
        self.timer = timer
        timer.resume()
    }

    private func restore(_ state: State) {
        guard let current = Self.readVolume(state.deviceID),
              abs(current - state.lastWrittenVolume) < 0.02 else { return }
        _ = Self.writeVolume(state.originalVolume, deviceID: state.deviceID)
    }

    private func cancelAnimation() {
        timer?.cancel()
        timer = nil
    }

    private static func volumeAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func isSettable(_ deviceID: AudioDeviceID) -> Bool {
        var address = volumeAddress()
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(deviceID, &address)
            && AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr
            && settable.boolValue
    }

    private static func readVolume(_ deviceID: AudioDeviceID) -> Float32? {
        var address = volumeAddress()
        var volume: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &volume) == noErr else { return nil }
        return volume
    }

    private static func writeVolume(_ volume: Float32, deviceID: AudioDeviceID) -> Float32? {
        var address = volumeAddress()
        var volume = min(max(volume, 0), 1)
        guard AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume) == noErr else {
            return nil
        }
        return readVolume(deviceID) ?? volume
    }
}
