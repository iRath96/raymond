import Foundation

enum ShellError: Error {
    case nonZeroExitCode(Int32)
}

func shell(_ args: String...) throws {
    let task = Process()
    task.launchPath = "/usr/bin/env"
    task.arguments = args
    task.launch()
    task.waitUntilExit()
    
    if task.terminationStatus != 0 {
        throw ShellError.nonZeroExitCode(task.terminationStatus)
    }
}
