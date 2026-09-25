import XCTest
@testable import LocalEchoLib

final class ProcessOutputTests: XCTestCase {
    func testProcessOutputDrainsLargeStdoutAndStderr() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "printf '%*s' 131072 '' ; printf '%*s' 131072 '' >&2"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let (output, errors) = ProcessOutput.read(stdout: stdout, stderr: stderr)
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(output.count, 131072)
        XCTAssertEqual(errors.count, 131072)
    }
}
