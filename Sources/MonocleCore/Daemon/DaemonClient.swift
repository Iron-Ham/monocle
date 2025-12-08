// By Dennis Müller

import Foundation

/// A tiny façade the CLI uses to talk to the daemon without dealing with sockets directly.
public struct DaemonClient {
  private let transport: DaemonTransport
  public let socketURL: URL
  public let requestTimeout: TimeInterval

  public init(socketURL: URL = DaemonSocketConfiguration.defaultSocketURL, requestTimeout: TimeInterval = 5) {
    self.socketURL = socketURL
    self.requestTimeout = requestTimeout
    transport = UnixSocketDaemonTransport(socketPath: socketURL.path)
  }

  /// Sends a raw request to the daemon, returning either a response or throwing on transport errors.
  public func send(method: DaemonMethod, parameters: DaemonRequestParameters) async throws -> DaemonResponse {
    let request = DaemonRequest(method: method, parameters: parameters)
    return try await transport.send(request, timeout: requestTimeout)
  }

  /// Convenience helper for the inspect method.
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
  func send(_ request: DaemonRequest, timeout: TimeInterval) async throws -> DaemonResponse
}

/// Unix domain socket implementation of the daemon transport.
struct UnixSocketDaemonTransport: DaemonTransport {
  var socketPath: String

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
