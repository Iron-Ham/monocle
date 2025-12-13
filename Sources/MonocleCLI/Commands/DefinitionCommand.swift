// By Dennis Müller

import ArgumentParser
import Foundation
import MonocleCore

/// Resolves the definition location for a Swift symbol.
struct DefinitionCommand: AsyncParsableCommand {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "definition",
      abstract: "Resolve the definition of a Swift symbol.",
    )
  }

  /// Optional workspace root path that overrides auto-detection.
  @Option(
    name: [.customShort("w"), .long, .customLong("project")],
    help: "Workspace root path (Package.swift, .xcodeproj, or .xcworkspace). Alias: --project.",
  )
  var workspace: String?

  /// Swift source file that contains the target symbol.
  @Option(name: [.customShort("f"), .long], help: "Swift source file path.")
  var file: String

  /// One-based line number of the symbol location.
  @Option(name: [.customShort("l"), .long], help: "One-based line number of the symbol position.")
  var line: Int

  /// One-based column number of the symbol location.
  @Option(name: [.customShort("c"), .long], help: "One-based column number of the symbol position.")
  var column: Int

  /// Outputs JSON when `true`; otherwise prints human-readable text.
  @Flag(name: .long, help: "Emit JSON output instead of human-readable text.")
  var json: Bool = false

  /// Runs the definition command and prints results in the requested format.
  mutating func run() async throws {
    let info = try await SymbolCommandRunner.perform(
      method: .definition,
      workspace: workspace,
      file: file,
      line: line,
      column: column,
    )

    if json {
      try printJSON(info)
    } else {
      HumanReadablePrinter.printSymbolInfo(info)
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
