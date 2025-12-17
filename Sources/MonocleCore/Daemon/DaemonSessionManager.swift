// By Dennis Müller

import Foundation

/// Manages pooled LSP sessions for daemon requests.
public actor DaemonSessionManager {
  private var sessions: [Workspace: LspSession] = [:]
  private var lastUsedDates: [Workspace: Date] = [:]
  private let toolchain: ToolchainConfiguration?

  /// Creates a session manager that can reuse LSP sessions across requests.
  ///
  /// - Parameter toolchain: Optional toolchain overrides passed to new sessions.
  public init(toolchain: ToolchainConfiguration? = nil) {
    self.toolchain = toolchain
  }

  /// Executes a symbol-related method and returns the result or error payload.
  ///
  /// - Parameters:
  ///   - method: Symbol method requested by the client.
  ///   - parameters: Workspace and position details for the request.
  /// - Returns: Success with symbol info or a daemon error payload.
  public func handle(method: DaemonMethod,
                     parameters: DaemonRequestParameters) async -> Result<SymbolInfo, DaemonErrorPayload> {
    do {
      let workspace = try resolveWorkspace(from: parameters)
      let session = try await sessionForWorkspace(workspace)
      let info: SymbolInfo
      switch method {
      case .inspect:
        info = try await session.inspectSymbol(
          file: parameters.filePath,
          line: parameters.line,
          column: parameters.column,
        )
      case .definition:
        info = try await session.definition(file: parameters.filePath, line: parameters.line, column: parameters.column)
      case .hover:
        info = try await session.hover(file: parameters.filePath, line: parameters.line, column: parameters.column)
      case .symbolSearch, .shutdown, .ping:
        return .failure(DaemonErrorPayload(
          code: "unsupported_method",
          message: "Method \(method.rawValue) is handled by the server control path.",
        ))
      case .status:
        return .failure(DaemonErrorPayload(
          code: "unsupported_method",
          message: "Method \(method.rawValue) is handled by the server control path.",
        ))
      }
      lastUsedDates[workspace] = Date()
      return .success(info)
    } catch let error as MonocleError {
      return .failure(DaemonErrorPayload.from(monocleError: error))
    } catch {
      return .failure(DaemonErrorPayload(code: "unknown_error", message: error.localizedDescription))
    }
  }

  /// Executes a workspace symbol search request.
  ///
  /// - Parameter parameters: Workspace root, query, and optional enrichment options.
  /// - Returns: Success with search results or an error payload.
  public func searchSymbols(parameters: DaemonRequestParameters) async
    -> Result<[SymbolSearchResult], DaemonErrorPayload> {
    do {
      guard let query = parameters.query else {
        return .failure(DaemonErrorPayload(code: "invalid_parameters", message: "Missing search query."))
      }

      let workspace = try resolveWorkspace(from: parameters)
      let session = try await sessionForWorkspace(workspace)
      let results = try await session.searchSymbols(
        matching: query,
        limit: parameters.limit ?? 20,
        enrich: parameters.enrich ?? false,
      )
      lastUsedDates[workspace] = Date()
      return .success(results)
    } catch let error as MonocleError {
      return .failure(DaemonErrorPayload.from(monocleError: error))
    } catch {
      return .failure(DaemonErrorPayload(code: "unknown_error", message: error.localizedDescription))
    }
  }

  /// Provides metadata about active sessions.
  ///
  /// - Parameters:
  ///   - socketPath: Path of the daemon's Unix domain socket.
  ///   - idleSessionTimeout: Idle timeout used to reap sessions.
  /// - Returns: Status payload describing current daemon state.
  public func status(socketPath: String, idleSessionTimeout: TimeInterval) async -> DaemonStatus {
    let formatter = ISO8601DateFormatter()
    let sessionsInfo = sessions.map { workspace, session in
      let lastUsed = lastUsedDates[workspace] ?? Date()
      return DaemonStatus.Session(
        workspaceRootPath: workspace.rootPath,
        kind: workspace.kind,
        lastUsedISO8601: formatter.string(from: lastUsed),
      )
    }.sorted { $0.workspaceRootPath < $1.workspaceRootPath }

    return DaemonStatus(
      activeSessions: sessionsInfo,
      socketPath: socketPath,
      daemonProcessIdentifier: Int(ProcessInfo.processInfo.processIdentifier),
      idleSessionTimeoutSeconds: Int(idleSessionTimeout),
      logFilePath: DaemonRuntimeConfiguration.logFileURL.path,
    )
  }

  /// Stops and discards sessions that have not been used recently.
  ///
  /// - Parameter idleInterval: Maximum age, in seconds, before a session is reaped.
  public func reapIdleSessions(olderThan idleInterval: TimeInterval) async {
    let now = Date()
    for (workspace, lastUsed) in lastUsedDates {
      if now.timeIntervalSince(lastUsed) > idleInterval {
        if let session = sessions[workspace] {
          await session.shutdown()
        }
        sessions.removeValue(forKey: workspace)
        lastUsedDates.removeValue(forKey: workspace)
      }
    }
  }

  /// Shuts down all tracked sessions.
  public func shutdownAll() async {
    for session in sessions.values {
      await session.shutdown()
    }
    sessions.removeAll()
    lastUsedDates.removeAll()
  }

  // MARK: - Private

  /// Resolves the workspace from the provided daemon parameters.
  ///
  /// - Parameter parameters: Request parameters containing the workspace root path.
  /// - Returns: A workspace description derived from the explicit root path.
  private func resolveWorkspace(from parameters: DaemonRequestParameters) throws -> Workspace {
    guard let workspaceRootPath = parameters.workspaceRootPath else {
      throw MonocleError.workspaceNotFound
    }

    return try WorkspaceLocator.locate(
      explicitWorkspacePath: workspaceRootPath,
      filePath: workspaceRootPath,
    )
  }

  /// Returns an existing LSP session for the workspace or creates a new one.
  ///
  /// - Parameter workspace: Workspace description used as the session key.
  /// - Returns: A ready LSP session bound to the workspace.
  private func sessionForWorkspace(_ workspace: Workspace) async throws -> LspSession {
    if let existing = sessions[workspace] {
      return existing
    }
    let session = LspSession(workspace: workspace, toolchain: toolchain)
    sessions[workspace] = session
    return session
  }
}
