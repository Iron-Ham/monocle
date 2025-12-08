import ArgumentParser
import Foundation
import MonocleCore

struct StatusCommand: AsyncParsableCommand {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "status",
      abstract: "Show daemon status and active LSP sessions."
    )
  }
  
  @Option(name: .long, help: "Path to the Unix domain socket used by the daemon.")
  var socket: String?
  
  @Flag(name: .long, help: "Emit JSON output instead of human-readable text.")
  var json: Bool = false
  
  mutating func run() async throws {
    let socketURL = socket.map { URL(fileURLWithPath: $0) } ?? DaemonSocketConfiguration.defaultSocketURL
    guard FileManager.default.fileExists(atPath: socketURL.path) else {
      throw MonocleError.ioError("Daemon socket not found at \(socketURL.path). Is the daemon running?")
    }
    
    let client = DaemonClient(socketURL: socketURL)
    let parameters = DaemonRequestParameters(workspaceRootPath: nil, filePath: "", line: 1, column: 1)
    let response = try await client.send(method: .status, parameters: parameters)
    guard let status = response.status else {
      throw MonocleError.ioError("Daemon returned an unexpected response.")
    }
    
    if json {
      try printJSON(status)
    } else {
      HumanReadablePrinter.printDaemonStatus(status)
    }
  }
  
  private func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    guard let output = String(data: data, encoding: .utf8) else {
      throw MonocleError.ioError("Unable to encode JSON output.")
    }
    print(output)
  }
}
