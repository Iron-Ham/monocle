// By Dennis Müller

import ArgumentParser
import Foundation
import MonocleCore

/// Displays daemon status including active sessions and configuration.
struct StatusCommand: AsyncParsableCommand {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "status",
      abstract: "Show daemon status and active LSP sessions.",
    )
  }

  /// Optional override for the daemon socket path.
  @Option(name: .long, help: "Path to the Unix domain socket used by the daemon.")
  var socket: String?

  /// Outputs JSON when `true`; otherwise prints human-readable text.
  @Flag(name: .long, help: "Emit JSON output instead of human-readable text.")
  var json: Bool = false

  /// Runs the status command and prints results in the requested format.
  mutating func run() async throws {
    let socketURL = socket.map { URL(fileURLWithPath: $0) } ?? DaemonSocketConfiguration.defaultSocketURL
    let client = DaemonClient(socketURL: socketURL)
    let parameters = DaemonRequestParameters(workspaceRootPath: nil, filePath: "", line: 1, column: 1)
    let response: DaemonResponse
    do {
      response = try await client.send(method: .status, parameters: parameters)
    } catch {
      print(
        "No daemon is running. Start it with `monocle serve` or run any command (inspect/definition/hover) to auto-start it.",
      )
      return
    }
    guard let status = response.status else {
      throw MonocleError.ioError("Daemon returned an unexpected response.")
    }

    if json {
      try printJSON(status)
    } else {
      HumanReadablePrinter.printDaemonStatus(status)
    }
  }

  /// Encodes the provided value as pretty-printed JSON.
  ///
  /// - Parameter value: Value to encode.
  private func printJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    guard let output = String(data: data, encoding: .utf8) else {
      throw MonocleError.ioError("Unable to encode JSON output.")
    }

    print(output)
  }
}
