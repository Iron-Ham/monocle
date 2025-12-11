// By Dennis Müller

import Foundation

/// Represents the supported daemon methods.
public enum DaemonMethod: String, Codable, Sendable {
  /// Returns definition and hover details for a symbol.
  case inspect
  /// Returns only definition information for a symbol.
  case definition
  /// Returns only hover information for a symbol.
  case hover
  /// Searches workspace symbols by name.
  case symbolSearch
  /// Requests a graceful daemon shutdown.
  case shutdown
  /// Health check that ensures the daemon is reachable.
  case ping
  /// Provides current daemon status.
  case status
}

/// Parameters required to process a daemon request.
public struct DaemonRequestParameters: Codable, Sendable {
  /// Optional workspace root path supplied by the caller.
  public var workspaceRootPath: String?
  /// Absolute Swift source file path.
  public var filePath: String
  /// One-based line number of the symbol location.
  public var line: Int
  /// One-based column number of the symbol location.
  public var column: Int
  /// Search query for workspace symbol search.
  public var query: String?
  /// Optional limit for workspace symbol search results.
  public var limit: Int?
  /// Whether to enrich workspace symbol search results.
  public var enrich: Bool?

  /// Creates a parameter payload for a daemon request.
  ///
  /// - Parameters:
  ///   - workspaceRootPath: Optional explicit workspace root path.
  ///   - filePath: Swift source file involved in the request.
  ///   - line: One-based line of the symbol location.
  ///   - column: One-based column of the symbol location.
  public init(workspaceRootPath: String?, filePath: String, line: Int, column: Int) {
    self.workspaceRootPath = workspaceRootPath
    self.filePath = filePath
    self.line = line
    self.column = column
    query = nil
    limit = nil
    enrich = nil
  }

  /// Creates parameters for a workspace symbol search request.
  ///
  /// - Parameters:
  ///   - workspaceRootPath: Optional explicit workspace root path.
  ///   - query: Search term forwarded to SourceKit-LSP.
  ///   - limit: Optional maximum number of results to return.
  ///   - enrich: Whether to enrich results with definition/hover details.
  public init(workspaceRootPath: String?, query: String, limit: Int?, enrich: Bool?) {
    self.workspaceRootPath = workspaceRootPath
    filePath = ""
    line = 1
    column = 1
    self.query = query
    self.limit = limit
    self.enrich = enrich
  }
}

/// A request message sent to the daemon.
public struct DaemonRequest: Codable, Sendable {
  /// Unique identifier for correlating requests and responses.
  public var id: UUID
  /// Method describing the requested daemon operation.
  public var method: DaemonMethod
  /// Payload containing workspace and position details.
  public var parameters: DaemonRequestParameters

  /// Creates a new daemon request envelope.
  ///
  /// - Parameters:
  ///   - id: Identifier used to match responses; defaults to a random UUID.
  ///   - method: Daemon operation to execute.
  ///   - parameters: Associated request parameters.
  public init(id: UUID = UUID(), method: DaemonMethod, parameters: DaemonRequestParameters) {
    self.id = id
    self.method = method
    self.parameters = parameters
  }
}

/// An error payload returned by the daemon.
public struct DaemonErrorPayload: Codable, Sendable, Error {
  /// Machine-readable error code.
  public var code: String
  /// Human-readable error description.
  public var message: String

  /// Creates an error payload for transport back to the client.
  ///
  /// - Parameters:
  ///   - code: Stable error code.
  ///   - message: Descriptive message for the failure.
  public init(code: String, message: String) {
    self.code = code
    self.message = message
  }
}

/// A response message sent by the daemon.
public struct DaemonResponse: Codable, Sendable {
  /// Identifier matching the originating request.
  public var id: UUID
  /// Result payload returned for symbol-related requests.
  public var result: SymbolInfo?
  /// Search results returned for workspace symbol queries.
  public var symbolResults: [SymbolSearchResult]?
  /// Daemon status description returned by status requests.
  public var status: DaemonStatus?
  /// Error payload when the request failed.
  public var error: DaemonErrorPayload?

  /// Creates a success response containing a symbol result.
  ///
  /// - Parameters:
  ///   - id: Identifier matching the request.
  ///   - result: Symbol description returned by the daemon.
  public init(id: UUID, result: SymbolInfo) {
    self.id = id
    self.result = result
    symbolResults = nil
    status = nil
    error = nil
  }

  /// Creates a success response containing daemon status.
  ///
  /// - Parameters:
  ///   - id: Identifier matching the request.
  ///   - status: Current daemon status payload.
  public init(id: UUID, status: DaemonStatus) {
    self.id = id
    result = nil
    symbolResults = nil
    self.status = status
    error = nil
  }

  /// Creates a success response containing symbol search results.
  ///
  /// - Parameters:
  ///   - id: Identifier matching the request.
  ///   - results: Symbol search results returned by the daemon.
  public init(id: UUID, symbolResults: [SymbolSearchResult]) {
    self.id = id
    result = nil
    self.symbolResults = symbolResults
    status = nil
    error = nil
  }

  /// Creates an error response.
  ///
  /// - Parameters:
  ///   - id: Identifier matching the request.
  ///   - error: Error payload that describes the failure.
  public init(id: UUID, error: DaemonErrorPayload) {
    self.id = id
    result = nil
    symbolResults = nil
    status = nil
    self.error = error
  }
}

/// Represents the current daemon state and active LSP sessions.
public struct DaemonStatus: Codable, Sendable {
  public struct Session: Codable, Sendable {
    /// Workspace root path for the active session.
    public var workspaceRootPath: String
    /// Workspace kind for the session.
    public var kind: Workspace.Kind
    /// ISO8601 timestamp of when the session was last used.
    public var lastUsedISO8601: String

    /// Creates a session summary.
    ///
    /// - Parameters:
    ///   - workspaceRootPath: Root path of the workspace.
    ///   - kind: Kind of workspace represented by the session.
    ///   - lastUsedISO8601: Last-used timestamp in ISO8601 format.
    public init(workspaceRootPath: String, kind: Workspace.Kind, lastUsedISO8601: String) {
      self.workspaceRootPath = workspaceRootPath
      self.kind = kind
      self.lastUsedISO8601 = lastUsedISO8601
    }
  }

  /// All sessions currently maintained by the daemon.
  public var activeSessions: [Session]
  /// Path to the Unix socket where the daemon listens.
  public var socketPath: String
  /// Idle timeout, in seconds, after which sessions are reaped.
  public var idleSessionTimeoutSeconds: Int
  /// Path to the daemon log file.
  public var logFilePath: String

  /// Creates a daemon status payload.
  ///
  /// - Parameters:
  ///   - activeSessions: Active LSP sessions tracked by the daemon.
  ///   - socketPath: Filesystem path of the daemon's Unix socket.
  ///   - idleSessionTimeoutSeconds: Idle timeout threshold in seconds.
  ///   - logFilePath: Path of the daemon log file.
  public init(activeSessions: [Session], socketPath: String, idleSessionTimeoutSeconds: Int, logFilePath: String) {
    self.activeSessions = activeSessions
    self.socketPath = socketPath
    self.idleSessionTimeoutSeconds = idleSessionTimeoutSeconds
    self.logFilePath = logFilePath
  }
}

/// Provides the default socket location used by the daemon and client.
public enum DaemonSocketConfiguration {
  /// Default socket URL in the user's caches directory.
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

/// Shared daemon defaults used by both the CLI and auto-launcher.
public enum DaemonRuntimeConfiguration {
  /// Matches the default value in ServeCommand.
  public static let defaultIdleTimeoutSeconds: TimeInterval = 600

  /// Directory for daemon logs and other runtime artifacts.
  public static var logDirectoryURL: URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".monocle", isDirectory: true)
  }

  /// Default path for the daemon log file.
  public static var logFileURL: URL {
    logDirectoryURL.appendingPathComponent("daemon.log")
  }
}

extension DaemonErrorPayload {
  /// Maps internal `MonocleError` values to transport-friendly payloads.
  ///
  /// - Parameter monocleError: Domain error to convert.
  /// - Returns: Transport-friendly daemon error payload.
  static func from(monocleError: MonocleError) -> DaemonErrorPayload {
    switch monocleError {
    case .workspaceNotFound:
      DaemonErrorPayload(code: "workspace_not_found", message: "Workspace could not be located for the provided file.")
    case let .workspaceAmbiguous(options):
      DaemonErrorPayload(code: "workspace_ambiguous", message: "Multiple workspace candidates were found: \(options.joined(separator: ", ")).")
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
