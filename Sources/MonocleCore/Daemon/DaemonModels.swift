// By Dennis Müller

import Foundation

/// Represents the supported daemon methods.
public enum DaemonMethod: String, Codable, Sendable {
  case inspect
  case definition
  case hover
  case shutdown
  case ping
  case status
}

/// Parameters required to process a daemon request.
public struct DaemonRequestParameters: Codable, Sendable {
  public var workspaceRootPath: String?
  public var filePath: String
  public var line: Int
  public var column: Int

  public init(workspaceRootPath: String?, filePath: String, line: Int, column: Int) {
    self.workspaceRootPath = workspaceRootPath
    self.filePath = filePath
    self.line = line
    self.column = column
  }
}

/// A request message sent to the daemon.
public struct DaemonRequest: Codable, Sendable {
  public var id: UUID
  public var method: DaemonMethod
  public var parameters: DaemonRequestParameters

  public init(id: UUID = UUID(), method: DaemonMethod, parameters: DaemonRequestParameters) {
    self.id = id
    self.method = method
    self.parameters = parameters
  }
}

/// An error payload returned by the daemon.
public struct DaemonErrorPayload: Codable, Sendable, Error {
  public var code: String
  public var message: String

  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

/// A response message sent by the daemon.
public struct DaemonResponse: Codable, Sendable {
  public var id: UUID
  public var result: SymbolInfo?
  public var status: DaemonStatus?
  public var error: DaemonErrorPayload?

  public init(id: UUID, result: SymbolInfo) {
    self.id = id
    self.result = result
    status = nil
    error = nil
  }

  public init(id: UUID, status: DaemonStatus) {
    self.id = id
    result = nil
    self.status = status
    error = nil
  }

  public init(id: UUID, error: DaemonErrorPayload) {
    self.id = id
    result = nil
    status = nil
    self.error = error
  }
}

/// Represents the current daemon state and active LSP sessions.
public struct DaemonStatus: Codable, Sendable {
  public struct Session: Codable, Sendable {
    public var workspaceRootPath: String
    public var kind: Workspace.Kind
    public var lastUsedISO8601: String

    public init(workspaceRootPath: String, kind: Workspace.Kind, lastUsedISO8601: String) {
      self.workspaceRootPath = workspaceRootPath
      self.kind = kind
      self.lastUsedISO8601 = lastUsedISO8601
    }
  }

  public var activeSessions: [Session]
  public var socketPath: String
  public var idleSessionTimeoutSeconds: Int

  public init(activeSessions: [Session], socketPath: String, idleSessionTimeoutSeconds: Int) {
    self.activeSessions = activeSessions
    self.socketPath = socketPath
    self.idleSessionTimeoutSeconds = idleSessionTimeoutSeconds
  }
}

/// Provides the default socket location used by the daemon and client.
public enum DaemonSocketConfiguration {
  public static var defaultSocketURL: URL {
    let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    let base = cachesDirectory?.appendingPathComponent("monocle", isDirectory: true)
    if let base {
      return base.appendingPathComponent("daemon.sock")
    } else {
      return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("monocle-daemon.sock")
    }
  }
}

extension DaemonErrorPayload {
  /// Maps internal `MonocleError` values to transport-friendly payloads.
  static func from(monocleError: MonocleError) -> DaemonErrorPayload {
    switch monocleError {
    case .workspaceNotFound:
      DaemonErrorPayload(code: "workspace_not_found", message: "Workspace could not be located for the provided file.")
    case let .lspLaunchFailed(description):
      DaemonErrorPayload(code: "lsp_launch_failed", message: description)
    case let .lspInitializationFailed(description):
      DaemonErrorPayload(code: "lsp_initialization_failed", message: description)
    case .symbolNotFound:
      DaemonErrorPayload(code: "symbol_not_found", message: "No symbol was found at the requested location.")
    case let .ioError(description):
      DaemonErrorPayload(code: "io_error", message: description)
    case .unsupportedWorkspaceKind:
      DaemonErrorPayload(code: "unsupported_workspace", message: "The workspace kind is not supported.")
    }
  }
}
