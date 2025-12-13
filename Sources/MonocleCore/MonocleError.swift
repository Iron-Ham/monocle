// By Dennis Müller

import Foundation

/// Represents the domain-specific errors produced by Monocle.
public enum MonocleError: Error {
  /// A workspace root could not be located for the provided file.
  case workspaceNotFound
  /// Multiple candidate workspaces were found; an explicit choice is required.
  case workspaceAmbiguous(options: [String])
  /// An Xcode workspace/project needs a build server configuration, but none was found.
  case buildServerConfigurationMissing(workspaceRootPath: String)
  /// SourceKit-LSP failed to launch, carrying the underlying description.
  case lspLaunchFailed(String)
  /// SourceKit-LSP launched but did not complete initialization.
  case lspInitializationFailed(String)
  /// No symbol was resolved at the requested file, line, and column.
  case symbolNotFound
  /// A filesystem or process interaction failed with the provided description.
  case ioError(String)
  /// The detected workspace layout is not supported by monocle.
  case unsupportedWorkspaceKind
}

extension MonocleError: LocalizedError {
  /// Human-readable descriptions shown in CLI error output.
  public var errorDescription: String? {
    switch self {
    case .workspaceNotFound:
      "A Swift package or Xcode workspace could not be found for the provided file path."
    case let .workspaceAmbiguous(options):
      "Multiple workspace candidates were found: \(options.joined(separator: ", ")). Please pass --workspace to select one."
    case let .buildServerConfigurationMissing(workspaceRootPath):
      """
      No build server configuration was found for this Xcode workspace/project.

      Generate a `buildServer.json` in the workspace root and try again.
      For example (Xcode Build Server):

        xcode-build-server config -project <YourProject>.xcodeproj -scheme <YourScheme>
        xcode-build-server config -workspace <YourWorkspace>.xcworkspace -scheme <YourScheme>

      Workspace root: \(workspaceRootPath)
      """
    case let .lspLaunchFailed(message):
      "SourceKit-LSP failed to launch: \(message)"
    case let .lspInitializationFailed(message):
      "SourceKit-LSP could not initialize: \(message)"
    case .symbolNotFound:
      "No symbol was found at the requested location."
    case let .ioError(message):
      message
    case .unsupportedWorkspaceKind:
      "The detected workspace layout is not supported."
    }
  }
}
