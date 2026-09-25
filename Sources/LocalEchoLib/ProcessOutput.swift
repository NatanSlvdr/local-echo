import Foundation

/// Drains both process pipes concurrently so neither full pipe can stall the child.
enum ProcessOutput {
    static func read(stdout: Pipe, stderr: Pipe) -> (Data, Data) {
        let group = DispatchGroup()
        let stderrResult = LockedData()
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            stderrResult.store(stderr.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        return (stdoutData, stderrResult.value)
    }
}

private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }

    func store(_ value: Data) {
        lock.lock()
        data = value
        lock.unlock()
    }
}
