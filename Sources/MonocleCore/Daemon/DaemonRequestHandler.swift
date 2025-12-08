// By Dennis Müller

import Foundation

/// Converts decoded daemon requests into responses using the session manager.
struct DaemonRequestHandler {
  var sessionManager: DaemonSessionManager
  var socketPath: String
  var idleSessionTimeout: TimeInterval

  /// Handles the request and always returns a response (never throws).
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
