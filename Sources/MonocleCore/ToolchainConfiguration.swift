// By Dennis Müller

import Foundation

/// Describes an optional custom toolchain configuration.
public struct ToolchainConfiguration: Sendable {
  /// Optional override for `DEVELOPER_DIR` used when launching SourceKit-LSP.
  public var developerDirectory: String?
  /// Optional explicit path to a `sourcekit-lsp` executable.
  public var sourceKitPath: String?

  /// Creates a toolchain override description.
  ///
  /// - Parameters:
  ///   - developerDirectory: Custom Xcode developer directory to export as `DEVELOPER_DIR`.
  ///   - sourceKitPath: Explicit path to the SourceKit-LSP binary to execute.
  public init(developerDirectory: String? = nil, sourceKitPath: String? = nil) {
    self.developerDirectory = developerDirectory
    self.sourceKitPath = sourceKitPath
  }
}
