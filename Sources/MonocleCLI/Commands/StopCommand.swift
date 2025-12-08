// By Dennis Müller

import ArgumentParser
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

  /// Sends a shutdown request to the daemon and prints confirmation.
  mutating func run() async throws {
    let socketURL = socket.map { URL(fileURLWithPath: $0) } ?? DaemonSocketConfiguration.defaultSocketURL
    guard FileManager.default.fileExists(atPath: socketURL.path) else {
      print("No daemon socket found at \(socketURL.path)")
      return
    }

    let client = DaemonClient(socketURL: socketURL)
    let parameters = DaemonRequestParameters(workspaceRootPath: nil, filePath: "", line: 1, column: 1)
    do {
      _ = try await client.send(method: .shutdown, parameters: parameters)
      print("Daemon stopped.")
    } catch {
      throw MonocleError.ioError("Failed to stop daemon: \(error.localizedDescription)")
    }
  }
}
