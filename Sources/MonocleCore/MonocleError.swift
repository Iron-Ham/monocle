/// Represents the domain-specific errors produced by Monocle.
public enum MonocleError: Error {
  /// A workspace root could not be located for the provided file.
  case workspaceNotFound
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
