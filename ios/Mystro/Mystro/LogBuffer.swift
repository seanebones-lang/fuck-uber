import Foundation

/// In-memory ring buffer of the last 50 log lines. Thread-safe.
final class LogBuffer {
  static let shared = LogBuffer()

  private let queue = DispatchQueue(label: "destro.logbuffer", qos: .utility)
  private var _lines: [String] = []
  private let maxLines = 50

  var lines: [String] {
    queue.sync { _lines }
  }

  private init() {}

  func append(_ line: String) {
    queue.sync {
      _lines.append(line)
      if _lines.count > maxLines {
        _lines.removeFirst(_lines.count - maxLines)
      }
    }
  }
}
