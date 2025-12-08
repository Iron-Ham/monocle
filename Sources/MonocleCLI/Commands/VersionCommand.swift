// By Dennis Müller

import ArgumentParser
import Foundation
import MonocleCore

struct VersionCommand: ParsableCommand {
  static var configuration: CommandConfiguration {
    CommandConfiguration(
      commandName: "version",
      abstract: "Show version information.",
    )
  }

  func run() throws {
    let toolVersion = MonocleVersion.current
    let sourceKitVersion = try SourceKitService.detectSourceKitVersion()
    print("monocle \(toolVersion)")
    print("SourceKit-LSP: \(sourceKitVersion)")
  }
}
