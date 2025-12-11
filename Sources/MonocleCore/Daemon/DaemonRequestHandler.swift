// By Dennis Müller

import Foundation

/// Converts decoded daemon requests into responses using the session manager.
struct DaemonRequestHandler {
  /// Session manager used to serve symbol queries.
  var sessionManager: DaemonSessionManager
  /// Path of the Unix socket the daemon listens on.
  var socketPath: String
  /// Idle timeout used for reporting status.
  var idleSessionTimeout: TimeInterval

  /// Handles the request and always returns a response (never throws).
  ///
  /// - Parameter request: Decoded daemon request.
  /// - Returns: Response representing success, status, or an error payload.
  func handle(_ request: DaemonRequest) async -> DaemonResponse {
    switch request.method {
    case .shutdown:
      await sessionManager.shutdownAll()
      return DaemonResponse(id: request.id, result: SymbolInfo())
    case .ping:
      return DaemonResponse(id: request.id, result: SymbolInfo())
    case .status:
      let status = await sessionManager.status(socketPath: socketPath, idleSessionTimeout: idleSessionTimeout)
      return DaemonResponse(id: request.id, status: status)
    case .symbolSearch:
      let searchResult = await sessionManager.searchSymbols(parameters: request.parameters)
      switch searchResult {
      case let .success(results):
        return DaemonResponse(id: request.id, symbolResults: results)
      case let .failure(errorPayload):
        return DaemonResponse(id: request.id, error: errorPayload)
      }
    case .inspect, .definition, .hover:
      let result = await sessionManager.handle(method: request.method, parameters: request.parameters)
      switch result {
      case let .success(info):
        return DaemonResponse(id: request.id, result: info)
      case let .failure(errorPayload):
        return DaemonResponse(id: request.id, error: errorPayload)
      }
    }
  }
}
