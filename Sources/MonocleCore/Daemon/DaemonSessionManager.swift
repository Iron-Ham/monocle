// By Dennis Müller

import Foundation

/// Manages pooled LSP sessions for daemon requests.
public actor DaemonSessionManager {
  private var sessions: [Workspace: LspSession] = [:]
  private var lastUsedDates: [Workspace: Date] = [:]
  private let toolchain: ToolchainConfiguration?

  public init(toolchain: ToolchainConfiguration? = nil) {
    self.toolchain = toolchain
  }

  /// Executes a symbol-related method and returns the result or error payload.
  public func handle(method: DaemonMethod,
                     parameters: DaemonRequestParameters) async -> Result<SymbolInfo, DaemonErrorPayload> {
    do {
      let workspace = try WorkspaceLocator.locate(
        explicitWorkspacePath: parameters.workspaceRootPath,
        filePath: parameters.filePath,
      )
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
      case .shutdown, .ping:
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

  /// Provides metadata about active sessions.
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
      idleSessionTimeoutSeconds: Int(idleSessionTimeout),
    )
  }

  /// Stops and discards sessions that have not been used recently.
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

  private func sessionForWorkspace(_ workspace: Workspace) async throws -> LspSession {
    if let existing = sessions[workspace] {
      return existing
    }
    let session = LspSession(workspace: workspace, toolchain: toolchain)
    sessions[workspace] = session
    return session
  }
}
