// By Dennis Müller

import Foundation

/// Locates a workspace starting from a file path and optional explicit hint.
public enum WorkspaceLocator {
  /// Attempts to locate a workspace for the provided Swift source file.
  /// - Parameters:
  ///   - explicitWorkspacePath: Optional explicit workspace root to prefer.
  ///   - filePath: Swift source file path used as a starting point.
  /// - Returns: A `Workspace` representing the detected root.
  /// - Throws: `MonocleError.workspaceNotFound` when no workspace is discovered.
  public static func locate(explicitWorkspacePath: String?, filePath: String) throws -> Workspace {
    if let explicitPath = explicitWorkspacePath {
      return try classifyWorkspace(at: explicitPath)
    }

    var currentURL = URL(fileURLWithPath: filePath).deletingLastPathComponent()
    let fileManager = FileManager.default

    while true {
      if fileManager.fileExists(atPath: currentURL.appendingPathComponent("Package.swift").path) {
        return Workspace(rootPath: currentURL.path, kind: .swiftPackage)
      }

      if let projectPath = firstMatch(in: currentURL, withExtension: "xcodeproj", fileManager: fileManager) {
        return Workspace(rootPath: projectPath.deletingLastPathComponent().path, kind: .xcodeProject)
      }

      if let workspacePath = firstMatch(in: currentURL, withExtension: "xcworkspace", fileManager: fileManager) {
        return Workspace(rootPath: workspacePath.deletingLastPathComponent().path, kind: .xcodeWorkspace)
      }

      let parent = currentURL.deletingLastPathComponent()
      if parent.path == currentURL.path {
        throw MonocleError.workspaceNotFound
      }
      currentURL = parent
    }
  }

  /// Determines the workspace kind for an explicit path.
  ///
  /// - Parameter path: Path to a package root, `.xcodeproj`, or `.xcworkspace`.
  /// - Returns: A workspace description for the path.
  /// - Throws: `MonocleError.workspaceNotFound` when the path does not describe a workspace.
  private static func classifyWorkspace(at path: String) throws -> Workspace {
    let url = URL(fileURLWithPath: path)
    let fileManager = FileManager.default

    if url.pathExtension == "xcodeproj" {
      return Workspace(rootPath: url.deletingLastPathComponent().path, kind: .xcodeProject)
    }

    if url.pathExtension == "xcworkspace" {
      return Workspace(rootPath: url.deletingLastPathComponent().path, kind: .xcodeWorkspace)
    }

    if fileManager.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
      return Workspace(rootPath: url.path, kind: .swiftPackage)
    }

    throw MonocleError.workspaceNotFound
  }

  /// Returns the first child item within `directory` matching the provided extension.
  ///
  /// - Parameters:
  ///   - directory: Directory to search.
  ///   - fileExtension: File extension to match, without the leading dot.
  ///   - fileManager: File manager used for the query.
  /// - Returns: The first matching URL or `nil` when none are present.
  private static func firstMatch(in directory: URL, withExtension fileExtension: String,
                                 fileManager: FileManager) -> URL? {
    let contents = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    return contents.first { $0.pathExtension == fileExtension }
  }
}
