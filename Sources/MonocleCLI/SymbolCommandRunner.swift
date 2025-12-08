import Foundation
import MonocleCore

enum SymbolCommandRunner {
  static func perform(method: DaemonMethod, workspace: String?, file: String, line: Int, column: Int) async throws -> SymbolInfo {
    let parameters = DaemonRequestParameters(workspaceRootPath: workspace, filePath: file, line: line, column: column)

    if let daemonResult = try await AutomaticDaemonLauncher.send(method: method, parameters: parameters) {
      return daemonResult
    }

    let workspaceDescription = try WorkspaceLocator.locate(explicitWorkspacePath: workspace, filePath: file)
    let session = LspSession(workspace: workspaceDescription)
    switch method {
    case .inspect:
      return try await session.inspectSymbol(file: file, line: line, column: column)
    case .definition:
      return try await session.definition(file: file, line: line, column: column)
    case .hover:
      return try await session.hover(file: file, line: line, column: column)
    case .shutdown, .ping, .status:
      throw MonocleError.ioError("Unsupported method for CLI command.")
    }
  }
  
  static func mapDaemonError(_ error: DaemonErrorPayload) -> Error {
    switch error.code {
    case "workspace_not_found":
      return MonocleError.workspaceNotFound
    case "symbol_not_found":
      return MonocleError.symbolNotFound
    case "lsp_launch_failed":
      return MonocleError.lspLaunchFailed(error.message)
    case "lsp_initialization_failed":
      return MonocleError.lspInitializationFailed(error.message)
    case "io_error":
      return MonocleError.ioError(error.message)
    case "unsupported_workspace":
      return MonocleError.unsupportedWorkspaceKind
    default:
      return MonocleError.ioError(error.message)
    }
  }
}

/// Handles talking to the daemon, including launching it on demand when it is not running.
private enum AutomaticDaemonLauncher {
  private static let supportedMethods: Set<DaemonMethod> = [.inspect, .definition, .hover]
  private static let readinessTimeoutSeconds: TimeInterval = 5

  static func send(method: DaemonMethod, parameters: DaemonRequestParameters) async throws -> SymbolInfo? {
    guard supportedMethods.contains(method) else { return nil }

    let socketURL = DaemonSocketConfiguration.defaultSocketURL
    let daemonClient = DaemonClient(socketURL: socketURL, requestTimeout: readinessTimeoutSeconds)

    guard await ensureDaemonIsReady(using: daemonClient, socketURL: socketURL) else {
      return nil
    }

    let response = try await daemonClient.send(method: method, parameters: parameters)
    if let result = response.result {
      return result
    }
    if let error = response.error {
      throw SymbolCommandRunner.mapDaemonError(error)
    }
    throw MonocleError.ioError("Daemon returned an unexpected response.")
  }

  private static func ensureDaemonIsReady(using client: DaemonClient, socketURL: URL) async -> Bool {
    if await daemonResponds(using: client) {
      return true
    }

    do {
      try launchDaemon(socketURL: socketURL)
    } catch {
      return false
    }

    return await waitForDaemonReadiness(using: client)
  }

  private static func daemonResponds(using client: DaemonClient) async -> Bool {
    do {
      _ = try await client.send(method: .ping, parameters: placeholderParameters())
      return true
    } catch {
      return false
    }
  }

  private static func waitForDaemonReadiness(using client: DaemonClient) async -> Bool {
    let deadline = Date().addingTimeInterval(readinessTimeoutSeconds)

    while Date() < deadline {
      if await daemonResponds(using: client) {
        return true
      }
      try? await Task.sleep(nanoseconds: 100_000_000)
    }

    return false
  }

  private static func launchDaemon(socketURL: URL) throws {
    let process = Process()
    process.executableURL = executableURL()
    process.arguments = [
      "serve",
      "--socket", socketURL.path,
      "--idle-timeout", String(Int(DaemonRuntimeConfiguration.defaultIdleTimeoutSeconds))
    ]

    let logDirectory = DaemonRuntimeConfiguration.logDirectoryURL
    try? FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
    let logFileURL = DaemonRuntimeConfiguration.logFileURL
    if FileManager.default.fileExists(atPath: logFileURL.path) == false {
      FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
    }
    if let logHandle = try? FileHandle(forWritingTo: logFileURL) {
      logHandle.seekToEndOfFile()
      process.standardOutput = logHandle
      process.standardError = logHandle
    } else {
      process.standardOutput = FileHandle.nullDevice
      process.standardError = FileHandle.nullDevice
    }
    process.standardInput = FileHandle.nullDevice

    try process.run()
  }

  private static func executableURL() -> URL {
    if let bundleURL = Bundle.main.executableURL {
      return bundleURL
    }

    return URL(fileURLWithPath: CommandLine.arguments[0])
  }

  private static func placeholderParameters() -> DaemonRequestParameters {
    DaemonRequestParameters(workspaceRootPath: nil, filePath: "", line: 1, column: 1)
  }
}
