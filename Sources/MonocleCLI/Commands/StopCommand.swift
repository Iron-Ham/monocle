// By Dennis Müller

import ArgumentParser
import Darwin
import Foundation
import MonocleCore

/// Stops a running monocle daemon if its socket is present.
struct StopCommand: AsyncParsableCommand {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "stop",
      abstract: "Stop the running monocle daemon.",
    )
  }

  /// Optional path to the daemon's Unix domain socket.
  @Option(name: .long, help: "Path to the Unix domain socket used by the daemon.")
  var socket: String?

  /// Maximum time to wait for a graceful shutdown response.
  @Option(name: .long, help: "Seconds to wait for the daemon to acknowledge shutdown.")
  var timeoutSeconds: Double = 5

  /// Force-stop the daemon when graceful shutdown fails.
  @Flag(name: .long, help: "Force-stop the daemon using its pid file when shutdown times out.")
  var force: Bool = false

  /// Sends a shutdown request to the daemon and prints confirmation.
  mutating func run() async throws {
    let socketURL = socket.map { URL(fileURLWithPath: $0) } ?? DaemonSocketConfiguration.defaultSocketURL
    let parameters = DaemonRequestParameters(workspaceRootPath: nil, filePath: "", line: 1, column: 1)

    if FileManager.default.fileExists(atPath: socketURL.path) {
      let client = DaemonClient(socketURL: socketURL, requestTimeout: timeoutSeconds)
      do {
        _ = try await client.send(method: .shutdown, parameters: parameters)
        print("Daemon stopped.")
        return
      } catch {
        if let posixError = error as? POSIXError, posixError.code == .ETIMEDOUT {
          try forceStop(socketURL: socketURL)
          print("Daemon force-stopped (unresponsive to shutdown).")
          return
        }

        if force == false {
          throw MonocleError.ioError("Failed to stop daemon: \(error.localizedDescription)")
        }
      }
    } else if force == false {
      print("No daemon socket found at \(socketURL.path)")
      return
    }

    try forceStop(socketURL: socketURL)
    print("Daemon force-stopped.")
  }

  private func forceStop(socketURL: URL) throws {
    let pidFileURL = DaemonRuntimeConfiguration.pidFileURL
    guard let pidString = try? String(contentsOf: pidFileURL).trimmingCharacters(in: .whitespacesAndNewlines),
          let pid = Int32(pidString), pid > 1
    else {
      if FileManager.default.fileExists(atPath: socketURL.path) {
        try? FileManager.default.removeItem(at: socketURL)
        throw MonocleError
          .ioError("Unable to read daemon pid from \(pidFileURL.path). Removed stale socket at \(socketURL.path).")
      }

      throw MonocleError.ioError("Unable to read daemon pid from \(pidFileURL.path).")
    }

    if kill(pid, SIGTERM) != 0 {
      let errorCode = POSIXErrorCode(rawValue: errno) ?? .EIO
      if errorCode != .ESRCH {
        throw MonocleError.ioError("Failed to send SIGTERM to daemon pid \(pid): \(errorCode)")
      }
    }

    if waitForProcessExit(pid: pid, timeoutSeconds: 2) == false {
      _ = kill(pid, SIGKILL)
      _ = waitForProcessExit(pid: pid, timeoutSeconds: 1)
    }

    if FileManager.default.fileExists(atPath: pidFileURL.path) {
      try? FileManager.default.removeItem(at: pidFileURL)
    }
    if FileManager.default.fileExists(atPath: socketURL.path) {
      try? FileManager.default.removeItem(at: socketURL)
    }
  }

  private func waitForProcessExit(pid: Int32, timeoutSeconds: Double) -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)

    while Date() < deadline {
      if kill(pid, 0) != 0 {
        let errorCode = POSIXErrorCode(rawValue: errno) ?? .EIO
        if errorCode == .ESRCH {
          return true
        }
      }

      usleep(50000)
    }

    return false
  }
}
