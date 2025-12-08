import Foundation
import MonocleCore

enum SymbolCommandRunner {
  static func perform(method: DaemonMethod, workspace: String?, file: String, line: Int, column: Int) async throws -> SymbolInfo {
    let parameters = DaemonRequestParameters(workspaceRootPath: workspace, filePath: file, line: line, column: column)
    
    if FileManager.default.fileExists(atPath: DaemonSocketConfiguration.defaultSocketURL.path) {
      do {
        let response = try await DaemonClient().send(method: method, parameters: parameters)
        if let result = response.result {
          return result
        }
        if let error = response.error {
          throw mapDaemonError(error)
        }
      } catch {
        // Fall back to direct LSP session if daemon is unreachable or fails.
      }
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
  
  private static func mapDaemonError(_ error: DaemonErrorPayload) -> Error {
    switch error.code {
    case "workspace_not_found":
      return MonocleError.workspaceNotFound
    case "symbol_not_found":
      return MonocleError.symbolNotFound
    case "lsp_launch_failed":
      return MonocleError.lspLaunchFailed(error.message)
    case "lsp_initialization_failed":
      return MonocleError.lspInitializationFailed(error.message)
    case "io_error":
      return MonocleError.ioError(error.message)
    case "unsupported_workspace":
      return MonocleError.unsupportedWorkspaceKind
    default:
      return MonocleError.ioError(error.message)
    }
  }
}
