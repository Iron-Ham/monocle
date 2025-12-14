// By Dennis Müller

import ArgumentParser
import Foundation
import MonocleCore

/// Lists Swift packages checked out for the current workspace.
struct PackagesCommand: AsyncParsableCommand {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "packages",
      abstract: "List checked-out Swift package dependencies for the workspace.",
    )
  }

  /// Optional workspace root path that overrides auto-detection.
  @Option(
    name: [.customShort("w"), .long, .customLong("project")],
    help: "Workspace root path (Package.swift, .xcodeproj, or .xcworkspace). Alias: --project.",
  )
  var workspace: String?

  /// Outputs JSON when `true`; otherwise prints human-readable text.
  @Flag(name: .long, help: "Emit JSON output instead of human-readable text.")
  var json: Bool = false

  mutating func run() async throws {
    var resolvedWorkspaceRootPath = workspace.map { FilePathResolver.absolutePath(for: $0) }

    if resolvedWorkspaceRootPath == nil {
      let detectedWorkspace = try WorkspaceLocator.locate(
        explicitWorkspacePath: nil,
        filePath: FileManager.default.currentDirectoryPath,
      )
      resolvedWorkspaceRootPath = detectedWorkspace.rootPath
    }

    let workspaceDescription = try WorkspaceLocator.locate(
      explicitWorkspacePath: resolvedWorkspaceRootPath,
      filePath: resolvedWorkspaceRootPath ?? FileManager.default.currentDirectoryPath,
    )

    let packages = try PackageCheckoutLocator.checkedOutPackages(in: workspaceDescription)
    try output(packages: packages, workspace: workspaceDescription)
  }

  private func output(packages: [PackageCheckout], workspace: Workspace) throws {
    if json {
      try printJSON(packages)
    } else {
      HumanReadablePrinter.printPackageCheckouts(packages, workspace: workspace)
    }
  }

  /// Encodes the provided value as pretty-printed JSON.
  ///
  /// - Parameter value: Value to encode.
  private func printJSON(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    guard let output = String(data: data, encoding: .utf8) else {
      throw MonocleError.ioError("Unable to encode JSON output.")
    }

    print(output)
  }
}
