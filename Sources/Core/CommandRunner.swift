import Foundation

struct CommandResult: Equatable {
    var out: String
    var status: Int32

    var succeeded: Bool { status == 0 }
}

/// Runs external programs. Abstracted so tests can substitute canned output.
protocol CommandRunning {
    func run(_ path: String, _ args: [String], stdin: String?, cwd: String?, timeout: TimeInterval) -> CommandResult
}

extension CommandRunning {
    func run(_ path: String, _ args: [String], timeout: TimeInterval = 10) -> CommandResult {
        run(path, args, stdin: nil, cwd: nil, timeout: timeout)
    }

    func osascript(_ script: String) -> String {
        run("/usr/bin/osascript", ["-e", script]).out
    }
}

/// Runs programs with `Process`, synchronously, killing them after `timeout` seconds.
struct ProcessRunner: CommandRunning {
    func run(_ path: String, _ args: [String], stdin: String?, cwd: String?, timeout: TimeInterval) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }

        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = stdin == nil ? FileHandle.nullDevice : inPipe

        do { try process.run() } catch { return CommandResult(out: "", status: -1) }

        if let stdin {
            DispatchQueue.global().async {
                inPipe.fileHandleForWriting.write(Data(stdin.utf8))
                try? inPipe.fileHandleForWriting.close()
            }
        }
        // Drain stderr so the child never blocks on a full pipe.
        DispatchQueue.global().async { _ = errPipe.fileHandleForReading.readDataToEndOfFile() }

        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        return CommandResult(out: String(decoding: data, as: UTF8.self), status: process.terminationStatus)
    }
}
