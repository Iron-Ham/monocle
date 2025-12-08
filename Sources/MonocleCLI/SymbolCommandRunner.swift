// By Dennis Müller

import Foundation
import MonocleCore

/// Runs symbol-related commands either through the daemon or a one-off LSP session.
enum SymbolCommandRunner {
  /// Executes a symbol request using the daemon when available or a direct LSP session otherwise.
  ///
  /// - Parameters:
  ///   - method: The symbol method to execute.
  ///   - workspace: Optional explicit workspace root path.
  ///   - file: Absolute Swift source file path.
  ///   - line: One-based line number of the symbol location.
  ///   - column: One-based column number of the symbol location.
  /// - Returns: Symbol information returned by SourceKit-LSP.
  static func perform(method: DaemonMethod, workspace: String?, file: String, line: Int,
                      column: Int) async throws -> SymbolInfo {
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

  /// Maps daemon transport errors back into the Monocle error domain.
  ///
  /// - Parameter error: Error payload returned by the daemon.
  /// - Returns: An equivalent `MonocleError` value.
  static func mapDaemonError(_ error: DaemonErrorPayload) -> Error {
    switch error.code {
    case "workspace_not_found":
      MonocleError.workspaceNotFound
    case "symbol_not_found":
      MonocleError.symbolNotFound
    case "lsp_launch_failed":
      MonocleError.lspLaunchFailed(error.message)
    case "lsp_initialization_failed":
      MonocleError.lspInitializationFailed(error.message)
    case "io_error":
      MonocleError.ioError(error.message)
    case "unsupported_workspace":
      MonocleError.unsupportedWorkspaceKind
    default:
      MonocleError.ioError(error.message)
    }
  }
}

/// Handles talking to the daemon, including launching it on demand when it is not running.
private enum AutomaticDaemonLauncher {
  private static let supportedMethods: Set<DaemonMethod> = [.inspect, .definition, .hover]
  private static let readinessTimeoutSeconds: TimeInterval = 5

  /// Sends the request to the daemon, launching it first if needed.
  ///
  /// - Parameters:
  ///   - method: Symbol method to execute.
  ///   - parameters: Request payload containing workspace and position details.
  /// - Returns: Symbol information when the daemon handles the request, or `nil` when the daemon is unavailable.
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

  /// Checks whether the daemon is reachable, starting it if necessary.
  ///
  /// - Parameters:
  ///   - client: Client used to probe daemon readiness.
  ///   - socketURL: Filesystem URL of the daemon socket.
  /// - Returns: `true` when the daemon is reachable within the timeout.
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

  /// Performs a ping request to verify the daemon is responsive.
  ///
  /// - Parameter client: Client used to send the ping request.
  /// - Returns: `true` when the daemon responds successfully.
  private static func daemonResponds(using client: DaemonClient) async -> Bool {
    do {
      _ = try await client.send(method: .ping, parameters: placeholderParameters())
      return true
    } catch {
      return false
    }
  }

  /// Waits for the daemon to begin responding, polling until the timeout expires.
  ///
  /// - Parameter client: Client used for probing readiness.
  /// - Returns: `true` when the daemon responds before the timeout.
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

  /// Launches the daemon as a detached child process.
  ///
  /// - Parameter socketURL: Socket URL that the daemon should bind to.
  private static func launchDaemon(socketURL: URL) throws {
    let process = Process()
    process.executableURL = executableURL()
    process.arguments = [
      "serve",
      "--socket", socketURL.path,
      "--idle-timeout", String(Int(DaemonRuntimeConfiguration.defaultIdleTimeoutSeconds)),
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

  /// Determines the executable URL for launching the current monocle binary.
  ///
  /// - Returns: URL of the running executable.
  private static func executableURL() -> URL {
    if let bundleURL = Bundle.main.executableURL {
      return bundleURL
    }

    return URL(fileURLWithPath: CommandLine.arguments[0])
  }

  /// Builds placeholder parameters for ping and shutdown requests that do not require file information.
  ///
  /// - Returns: Request parameters with empty file information.
  private static func placeholderParameters() -> DaemonRequestParameters {
    DaemonRequestParameters(workspaceRootPath: nil, filePath: "", line: 1, column: 1)
  }
}
