// By Dennis Müller

import Foundation

/// A tiny façade the CLI uses to talk to the daemon without dealing with sockets directly.
public struct DaemonClient {
  private let transport: DaemonTransport
  /// Filesystem location of the daemon socket.
  public let socketURL: URL
  /// Maximum time to wait for a daemon response.
  public let requestTimeout: TimeInterval

  /// Creates a daemon client bound to a socket URL.
  ///
  /// - Parameters:
  ///   - socketURL: Location of the Unix domain socket.
  ///   - requestTimeout: Maximum number of seconds to wait for a response.
  public init(socketURL: URL = DaemonSocketConfiguration.defaultSocketURL, requestTimeout: TimeInterval = 5) {
    self.socketURL = socketURL
    self.requestTimeout = requestTimeout
    transport = UnixSocketDaemonTransport(socketPath: socketURL.path)
  }

  /// Sends a raw request to the daemon, returning either a response or throwing on transport errors.
  ///
  /// - Parameters:
  ///   - method: Daemon operation to perform.
  ///   - parameters: Request payload for the operation.
  /// - Returns: Decoded daemon response.
  public func send(method: DaemonMethod, parameters: DaemonRequestParameters) async throws -> DaemonResponse {
    let request = DaemonRequest(method: method, parameters: parameters)
    return try await transport.send(request, timeout: requestTimeout)
  }

  /// Convenience helper for the inspect method.
  ///
  /// - Parameters:
  ///   - filePath: Absolute Swift source file path.
  ///   - line: One-based line number of the symbol location.
  ///   - column: One-based column number of the symbol location.
  ///   - workspaceRootPath: Optional workspace root override.
  /// - Returns: Symbol information that combines definition and hover data.
  public func inspect(filePath: String, line: Int, column: Int, workspaceRootPath: String?) async throws -> SymbolInfo {
    let parameters = DaemonRequestParameters(
      workspaceRootPath: workspaceRootPath,
      filePath: filePath,
      line: line,
      column: column,
    )
    let response = try await send(method: .inspect, parameters: parameters)
    return try extractResult(from: response)
  }

  /// Convenience helper for the definition method.
  ///
  /// - Parameters:
  ///   - filePath: Absolute Swift source file path.
  ///   - line: One-based line number of the symbol location.
  ///   - column: One-based column number of the symbol location.
  ///   - workspaceRootPath: Optional workspace root override.
  /// - Returns: Symbol information that includes definition metadata.
  public func definition(filePath: String, line: Int, column: Int,
                         workspaceRootPath: String?) async throws -> SymbolInfo {
    let parameters = DaemonRequestParameters(
      workspaceRootPath: workspaceRootPath,
      filePath: filePath,
      line: line,
      column: column,
    )
    let response = try await send(method: .definition, parameters: parameters)
    return try extractResult(from: response)
  }

  /// Convenience helper for the hover method.
  ///
  /// - Parameters:
  ///   - filePath: Absolute Swift source file path.
  ///   - line: One-based line number of the symbol location.
  ///   - column: One-based column number of the symbol location.
  ///   - workspaceRootPath: Optional workspace root override.
  /// - Returns: Symbol information derived from hover content.
  public func hover(filePath: String, line: Int, column: Int, workspaceRootPath: String?) async throws -> SymbolInfo {
    let parameters = DaemonRequestParameters(
      workspaceRootPath: workspaceRootPath,
      filePath: filePath,
      line: line,
      column: column,
    )
    let response = try await send(method: .hover, parameters: parameters)
    return try extractResult(from: response)
  }

  // MARK: - Private

  /// Extracts the symbol result from a daemon response or throws an error payload.
  ///
  /// - Parameter response: Response returned by the daemon.
  /// - Returns: Symbol information when present.
  /// - Throws: `DaemonErrorPayload` when the response contains an error or no result.
  private func extractResult(from response: DaemonResponse) throws -> SymbolInfo {
    if let result = response.result {
      return result
    }
    if let error = response.error {
      throw error
    }
    throw DaemonErrorPayload(code: "no_result", message: "Daemon returned neither result nor error.")
  }
}

/// Abstracts the transport the daemon client uses; currently Unix sockets, later could be something else.
protocol DaemonTransport {
  /// Sends the request and returns the decoded response.
  ///
  /// - Parameters:
  ///   - request: Request payload to transmit.
  ///   - timeout: Maximum number of seconds to wait for a response.
  /// - Returns: Decoded response from the daemon.
  func send(_ request: DaemonRequest, timeout: TimeInterval) async throws -> DaemonResponse
}

/// Unix domain socket implementation of the daemon transport.
struct UnixSocketDaemonTransport: DaemonTransport {
  /// Filesystem path of the Unix domain socket.
  var socketPath: String

  /// Sends a request over the Unix socket and waits for a response.
  ///
  /// - Parameters:
  ///   - request: Encoded daemon request.
  ///   - timeout: Maximum duration to wait for a response before timing out.
  /// - Returns: Decoded daemon response.
  func send(_ request: DaemonRequest, timeout: TimeInterval) async throws -> DaemonResponse {
    try await Task.detached(priority: .userInitiated) {
      let descriptor = try UnixDomainSocket.connect(path: socketPath)
      defer { close(descriptor) }

      let requestData = try JSONEncoder().encode(request)
      try FileDescriptorIO.writeAll(requestData, to: descriptor)

      // Let the server know we are done writing the request payload.
      _ = Darwin.shutdown(descriptor, SHUT_WR)

      let responseData = try FileDescriptorIO.readAll(from: descriptor, timeout: timeout)
      return try JSONDecoder().decode(DaemonResponse.self, from: responseData)
    }.value
  }
}
