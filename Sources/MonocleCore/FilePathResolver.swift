// By Dennis Müller

import Foundation

/// Normalizes file system paths provided by CLI and daemon callers.
public enum FilePathResolver {
  /// Returns an absolute, standardized path for the given input.
  ///
  /// - Parameter path: Relative or absolute path supplied by the caller.
  /// - Returns: An absolute path with symlinks resolved when possible.
  public static func absolutePath(for path: String) -> String {
    let expandedPath = (path as NSString).expandingTildeInPath
    let url = URL(fileURLWithPath: expandedPath)
    return url.resolvingSymlinksInPath().standardizedFileURL.path
  }
}
