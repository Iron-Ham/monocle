// By Dennis Müller

import ArgumentParser
import Foundation
import MonocleCore

/// Searches workspace symbols by name using SourceKit-LSP.
struct SymbolCommand: AsyncParsableCommand {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "symbol",
      abstract: "Search workspace symbols by name using SourceKit-LSP.",
    )
  }

  /// Optional workspace root path that overrides auto-detection.
  @Option(
    name: [.customShort("w"), .long],
    help: "Workspace root (Package.swift or Xcode project/workspace file).",
  )
  var workspace: String?

  /// Query string to search for.
  @Option(name: [.customShort("q"), .long], help: "Symbol name query to search for.")
  var query: String

  /// Maximum number of results to return.
  @Option(name: .long, help: "Maximum number of results to return. Defaults to 5.")
  var limit: Int = 5

  /// Whether to enrich results with definition and documentation.
  @Flag(name: .long, help: "Enrich results with definition and documentation.")
  var enrich: Bool = false

  /// Outputs JSON when `true`; otherwise prints human-readable text.
  @Flag(name: .long, help: "Emit JSON output instead of human-readable text.")
  var json: Bool = false

  mutating func run() async throws {
    var resolvedWorkspace = workspace.map { FilePathResolver.absolutePath(for: $0) }

    if resolvedWorkspace == nil {
      let detectedWorkspace = try WorkspaceLocator.locate(
        explicitWorkspacePath: nil,
        filePath: FileManager.default.currentDirectoryPath
      )
      resolvedWorkspace = detectedWorkspace.rootPath
    }

    let parameters = DaemonRequestParameters(
      workspaceRootPath: resolvedWorkspace,
      query: query,
      limit: limit,
      enrich: enrich,
    )

    if let daemonResults = try await AutomaticDaemonLauncher.sendSymbolSearch(parameters: parameters) {
      try output(results: daemonResults)
      return
    }

    let workspaceDescription = try WorkspaceLocator.locate(
      explicitWorkspacePath: resolvedWorkspace,
      filePath: resolvedWorkspace ?? FileManager.default.currentDirectoryPath
    )
    let session = LspSession(workspace: workspaceDescription)
    let results = try await session.searchSymbols(matching: query, limit: limit, enrich: enrich)
    try output(results: results)
  }

  /// Prints the results in the requested format.
  ///
  /// - Parameter results: Symbol search results to render.
  private func output(results: [SymbolSearchResult]) throws {
    if json {
      try printJSON(results)
    } else {
      HumanReadablePrinter.printSymbolSearchResults(results)
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
