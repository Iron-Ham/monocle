// By Dennis Müller

import Darwin
import Foundation
import MonocleCore

/// Runs symbol-related commands either through the daemon or a one-off LSP session.
enum SymbolCommandRunner {
  /// Executes a symbol request using the daemon when available or a direct LSP session otherwise.
  ///
  /// - Parameters:
  ///   - method: The symbol method to execute.
  ///   - workspace: Optional explicit workspace root path.
  ///   - file: Swift source file path (relative or absolute).
  ///   - line: One-based line number of the symbol location.
  ///   - column: One-based column number of the symbol location.
  /// - Returns: Symbol information returned by SourceKit-LSP.
  static func perform(method: DaemonMethod, workspace: String?, file: String, line: Int,
                      column: Int) async throws -> SymbolInfo {
    let resolvedFile = FilePathResolver.absolutePath(for: file)
    let workspaceDescription = try resolveWorkspace(for: workspace, sourceFilePath: resolvedFile)

    let parameters = DaemonRequestParameters(
      workspaceRootPath: workspaceDescription.rootPath,
      filePath: resolvedFile,
      line: line,
      column: column,
    )

    if let daemonResult = try await AutomaticDaemonLauncher.send(method: method, parameters: parameters) {
      return daemonResult
    }

    let session = LspSession(workspace: workspaceDescription)
    switch method {
    case .inspect:
      return try await session.inspectSymbol(file: resolvedFile, line: line, column: column)
    case .definition:
      return try await session.definition(file: resolvedFile, line: line, column: column)
    case .hover:
      return try await session.hover(file: resolvedFile, line: line, column: column)
    case .symbolSearch, .shutdown, .ping, .status:
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
    case "workspace_ambiguous":
      MonocleError.workspaceAmbiguous(options: [])
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

  /// Resolves the workspace path, falling back to auto-detection when no workspace argument is provided.
  ///
  /// - Parameters:
  ///   - workspaceArgument: Optional workspace path supplied by the user.
  ///   - sourceFilePath: Absolute path of the source file involved in the request.
  /// - Returns: The detected workspace description.
  private static func resolveWorkspace(for workspaceArgument: String?, sourceFilePath: String) throws -> Workspace {
    if let workspaceArgument {
      let absoluteWorkspacePath = FilePathResolver.absolutePath(for: workspaceArgument)
      return try WorkspaceLocator.locate(
        explicitWorkspacePath: absoluteWorkspacePath,
        filePath: absoluteWorkspacePath,
      )
    }

    return try WorkspaceLocator.locate(explicitWorkspacePath: nil, filePath: sourceFilePath)
  }
}

/// Handles talking to the daemon, including launching it on demand when it is not running.
enum AutomaticDaemonLauncher {
  private static let supportedMethods: Set<DaemonMethod> = [.inspect, .definition, .hover, .symbolSearch]
  private static let daemonReadinessTimeoutSeconds: TimeInterval = 2
  private static let daemonDefaultRequestTimeoutSeconds: TimeInterval = 30
  private static let daemonEnrichedSymbolSearchBaseTimeoutSeconds: TimeInterval = 45
  private static let daemonEnrichedSymbolSearchPerResultTimeoutSeconds: TimeInterval = 3
  private static let daemonEnrichedSymbolSearchMaximumTimeoutSeconds: TimeInterval = 180
  private static let daemonForceRestartWaitSeconds: TimeInterval = 2

  /// Sends the request to the daemon, launching it first if needed.
  ///
  /// - Parameters:
  ///   - method: Symbol method to execute.
  ///   - parameters: Request payload containing workspace and position details.
  /// - Returns: Symbol information when the daemon handles the request, or `nil` when the daemon is unavailable.
  static func send(method: DaemonMethod, parameters: DaemonRequestParameters) async throws -> SymbolInfo? {
    guard supportedMethods.contains(method) else { return nil }

    let socketURL = DaemonSocketConfiguration.defaultSocketURL
    let readinessClient = DaemonClient(socketURL: socketURL, requestTimeout: daemonReadinessTimeoutSeconds)

    guard await ensureDaemonIsReady(using: readinessClient, socketURL: socketURL) else {
      return nil
    }

    let requestClient = DaemonClient(
      socketURL: socketURL,
      requestTimeout: requestTimeoutSeconds(for: method, parameters: parameters),
    )

    let response: DaemonResponse
    do {
      response = try await requestClient.send(method: method, parameters: parameters)
    } catch {
      return nil
    }
    if let result = response.result {
      return result
    }
    if let error = response.error {
      throw SymbolCommandRunner.mapDaemonError(error)
    }
    throw MonocleError.ioError("Daemon returned an unexpected response.")
  }

  /// Sends a workspace symbol search request to the daemon when available.
  ///
  /// - Parameter parameters: Request payload containing workspace and search details.
  /// - Returns: Search results when handled by the daemon, or `nil` when the daemon is unavailable.
  static func sendSymbolSearch(parameters: DaemonRequestParameters) async throws -> [SymbolSearchResult]? {
    guard supportedMethods.contains(.symbolSearch) else { return nil }

    let socketURL = DaemonSocketConfiguration.defaultSocketURL
    let readinessClient = DaemonClient(socketURL: socketURL, requestTimeout: daemonReadinessTimeoutSeconds)

    guard await ensureDaemonIsReady(using: readinessClient, socketURL: socketURL) else {
      return nil
    }

    let requestClient = DaemonClient(
      socketURL: socketURL,
      requestTimeout: requestTimeoutSeconds(for: .symbolSearch, parameters: parameters),
    )

    let response: DaemonResponse
    do {
      response = try await requestClient.send(method: .symbolSearch, parameters: parameters)
    } catch {
      return nil
    }
    // Older daemons may not understand this method; fall back to local execution when no results are present.
    if let results = response.symbolResults {
      return results
    }
    if let error = response.error {
      if error.code == "unsupported_method" {
        return nil
      }
      throw SymbolCommandRunner.mapDaemonError(error)
    }
    // If we receive a non-error, non-result response (e.g., from an older daemon), skip daemon handling.
    return nil
  }

  /// Computes a request timeout suitable for the requested daemon method.
  ///
  /// Longer-running operations (notably enriched symbol search) need a higher timeout than quick health checks.
  private static func requestTimeoutSeconds(for method: DaemonMethod,
                                            parameters: DaemonRequestParameters) -> TimeInterval {
    if method == .symbolSearch, parameters.enrich == true {
      let limit = max(parameters.limit ?? 20, 1)
      let computedTimeout = daemonEnrichedSymbolSearchBaseTimeoutSeconds
        + (TimeInterval(limit) * daemonEnrichedSymbolSearchPerResultTimeoutSeconds)
      return min(computedTimeout, daemonEnrichedSymbolSearchMaximumTimeoutSeconds)
    }

    return daemonDefaultRequestTimeoutSeconds
  }

  /// Checks whether the daemon is reachable, starting it if necessary.
  ///
  /// - Parameters:
  ///   - client: Client used to probe daemon readiness.
  ///   - socketURL: Filesystem URL of the daemon socket.
  /// - Returns: `true` when the daemon is reachable within the timeout.
  private static func ensureDaemonIsReady(using client: DaemonClient, socketURL: URL) async -> Bool {
    let reachability = await daemonReachability(using: client, socketURL: socketURL)
    switch reachability {
    case .reachable:
      return true
    case .noSocketFile:
      break
    case .staleSocketFile:
      try? FileManager.default.removeItem(at: socketURL)
    case .unresponsiveDaemon:
      await forceStopUnresponsiveDaemon(socketURL: socketURL)
    case .unknown:
      break
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

  private enum DaemonReachability {
    case reachable
    case noSocketFile
    case staleSocketFile
    case unresponsiveDaemon
    case unknown
  }

  private static func daemonReachability(using client: DaemonClient, socketURL: URL) async -> DaemonReachability {
    guard FileManager.default.fileExists(atPath: socketURL.path) else {
      return .noSocketFile
    }

    do {
      _ = try await client.send(method: .ping, parameters: placeholderParameters())
      return .reachable
    } catch let error as POSIXError where error.code == .ECONNREFUSED {
      return .staleSocketFile
    } catch let error as POSIXError where error.code == .ENOENT {
      return .staleSocketFile
    } catch let error as POSIXError where error.code == .ETIMEDOUT {
      return .unresponsiveDaemon
    } catch {
      let description = error.localizedDescription.lowercased()
      if description.contains("timed out") {
        return .unresponsiveDaemon
      }

      if let pid = readDaemonProcessIdentifier(), isProcessAlive(pid: pid) == false {
        return .staleSocketFile
      }

      return .unknown
    }
  }

  private static func forceStopUnresponsiveDaemon(socketURL: URL) async {
    if let pid = readDaemonProcessIdentifier() {
      _ = kill(pid, SIGTERM)
      if waitForProcessExit(pid: pid, timeoutSeconds: daemonForceRestartWaitSeconds) == false {
        _ = kill(pid, SIGKILL)
        _ = waitForProcessExit(pid: pid, timeoutSeconds: 1)
      }
    }

    let pidFileURL = DaemonRuntimeConfiguration.pidFileURL
    if FileManager.default.fileExists(atPath: pidFileURL.path) {
      try? FileManager.default.removeItem(at: pidFileURL)
    }
    if FileManager.default.fileExists(atPath: socketURL.path) {
      try? FileManager.default.removeItem(at: socketURL)
    }
  }

  private static func readDaemonProcessIdentifier() -> Int32? {
    let pidFileURL = DaemonRuntimeConfiguration.pidFileURL
    guard let pidString = try? String(contentsOf: pidFileURL).trimmingCharacters(in: .whitespacesAndNewlines),
          let pid = Int32(pidString), pid > 1
    else {
      return nil
    }

    return pid
  }

  private static func isProcessAlive(pid: Int32) -> Bool {
    if kill(pid, 0) == 0 {
      return true
    }

    let errorCode = POSIXErrorCode(rawValue: errno) ?? .EIO
    return errorCode != .ESRCH
  }

  private static func waitForProcessExit(pid: Int32, timeoutSeconds: TimeInterval) -> Bool {
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

  /// Waits for the daemon to begin responding, polling until the timeout expires.
  ///
  /// - Parameter client: Client used for probing readiness.
  /// - Returns: `true` when the daemon responds before the timeout.
  private static func waitForDaemonReadiness(using client: DaemonClient) async -> Bool {
    let deadline = Date().addingTimeInterval(daemonReadinessTimeoutSeconds)

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

    let pidFileURL = DaemonRuntimeConfiguration.pidFileURL
    try? FileManager.default.createDirectory(
      at: pidFileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )
    try? String(process.processIdentifier).write(to: pidFileURL, atomically: true, encoding: .utf8)
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
