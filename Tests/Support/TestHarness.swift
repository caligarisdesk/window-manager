import Foundation

// A minimal XCTest-style harness. XCTest ships only with Xcode, and this project builds with the
// Command Line Tools alone, so tests are compiled together with Sources/Core into one executable.

/// A group of related tests.
protocol TestSuite {
    static var name: String { get }
    static var tests: [(String, () throws -> Void)] { get }
}

private var failureCount = 0
private var currentTest = ""

func fail(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
    failureCount += 1
    print("    ✗ \(currentTest): \(message)  (\(file):\(line))")
}

func check(_ condition: @autoclosure () -> Bool, _ message: String = "condition is false",
           file: StaticString = #fileID, line: UInt = #line) {
    if !condition() { fail(message, file: file, line: line) }
}

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #fileID, line: UInt = #line) {
    if actual != expected { fail("expected \(expected), got \(actual)", file: file, line: line) }
}

func checkNil<T>(_ value: T?, file: StaticString = #fileID, line: UInt = #line) {
    if let value { fail("expected nil, got \(value)", file: file, line: line) }
}

/// Unwraps or records a failure and throws, ending the test.
func unwrap<T>(_ value: T?, file: StaticString = #fileID, line: UInt = #line) throws -> T {
    guard let value else {
        fail("unexpected nil", file: file, line: line)
        throw TestAbort()
    }
    return value
}

struct TestAbort: Error {}

/// Spins the main run loop until `condition` holds or `timeout` passes. Needed for code that reports
/// back via `DispatchQueue.main.async`.
@discardableResult
func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return true
}

@main
enum TestMain {
    static let suites: [TestSuite.Type] = [
        ModelsTests.self, CommandRunnerTests.self, TerminalClientTests.self, ProcessScannerTests.self,
        TranscriptParserTests.self, PricingTests.self, ClaudeSessionStoreTests.self, TriageTests.self,
        WindowLayoutTests.self, FormattingTests.self, SummarizerTests.self, StorageTests.self, GitInfoTests.self,
    ]

    static func main() {
        var testCount = 0
        for suite in suites {
            print(suite.name)
            for (name, body) in suite.tests {
                currentTest = name
                testCount += 1
                let before = failureCount
                do { try body() } catch is TestAbort {} catch { fail("threw \(error)") }
                if failureCount == before { print("    ✓ \(name)") }
            }
        }
        print("\n\(testCount) tests, \(failureCount) failures")
        exit(failureCount == 0 ? 0 : 1)
    }
}
