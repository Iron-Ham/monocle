// By Dennis Müller

import ArgumentParser
import Foundation
import MonocleCore

/// Starts the long-running daemon that keeps SourceKit-LSP sessions warm.
struct ServeCommand: AsyncParsableCommand {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "serve",
      abstract: "Run a persistent daemon that reuses SourceKit-LSP sessions.",
    )
  }

  /// Filesystem path for the daemon's Unix domain socket.
  @Option(name: .long, help: "Path to the Unix domain socket used for daemon requests.")
  var socket: String?

  /// Idle session timeout in seconds.
  @Option(name: .long, help: "Idle session timeout in seconds.")
  var idleTimeout: Double = DaemonRuntimeConfiguration.defaultIdleTimeoutSeconds

  /// Runs the daemon until a shutdown request is received.
  mutating func run() async throws {
    let socketURL = socket.map { URL(fileURLWithPath: $0) } ?? DaemonSocketConfiguration.defaultSocketURL
    let server = DaemonServer(socketURL: socketURL, idleSessionTimeout: idleTimeout)
    print("monocle daemon listening on \(socketURL.path)")
    print("Idle session timeout: \(Int(idleTimeout))s")
    try await server.run()
  }
}
