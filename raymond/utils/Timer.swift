import Foundation

func measure(title: String, operation: () -> ()) {
    let startTime = CFAbsoluteTimeGetCurrent()
    operation()
    let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
    print("Time elapsed for \(title): \(String(format: "%.2f", timeElapsed*1000)) ms.")
}
