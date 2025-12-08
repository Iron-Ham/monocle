import ArgumentParser
import Foundation
import MonocleCore

struct ServeCommand: AsyncParsableCommand {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "serve",
      abstract: "Run a persistent daemon that reuses SourceKit-LSP sessions."
    )
  }
  
  @Option(name: .long, help: "Path to the Unix domain socket used for daemon requests.")
  var socket: String?
  
  @Option(name: .long, help: "Idle session timeout in seconds.")
  var idleTimeout: Double = DaemonRuntimeConfiguration.defaultIdleTimeoutSeconds
  
  mutating func run() async throws {
    let socketURL = socket.map { URL(fileURLWithPath: $0) } ?? DaemonSocketConfiguration.defaultSocketURL
    let server = DaemonServer(socketURL: socketURL, idleSessionTimeout: idleTimeout)
    print("monocle daemon listening on \(socketURL.path)")
    print("Idle session timeout: \(Int(idleTimeout))s")
    try await server.run()
  }
}
