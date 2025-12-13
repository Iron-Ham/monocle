// By Dennis Müller

import Foundation
@testable import MonocleCore
import Testing

final class SourceKitServiceTests {
  @Test func xcodeWorkspaceWithoutBuildServerConfigurationThrowsHelpfulError() async throws {
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: temporaryDirectory) }

    try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

    let xcodeProjectDirectory = temporaryDirectory.appendingPathComponent("Example.xcodeproj", isDirectory: true)
    try fileManager.createDirectory(at: xcodeProjectDirectory, withIntermediateDirectories: true)

    let packageManifestURL = temporaryDirectory.appendingPathComponent("Package.swift")
    try """
    // swift-tools-version: 6.2
    import PackageDescription
    let package = Package(name: "Example", products: [], targets: [])
    """.write(to: packageManifestURL, atomically: true, encoding: .utf8)

    let workspace = Workspace(rootPath: temporaryDirectory.path, kind: .xcodeProject)
    let service = SourceKitService()

    do {
      _ = try await service.start(workspace: workspace, toolchain: nil)
      Issue.record("Expected start(workspace:) to throw when buildServer.json is missing.")
    } catch let error as MonocleError {
      switch error {
      case let .buildServerConfigurationMissing(workspaceRootPath):
        let resolvedWorkspaceRootPath = URL(fileURLWithPath: workspaceRootPath).resolvingSymlinksInPath().path
        let resolvedTemporaryRootPath = temporaryDirectory.resolvingSymlinksInPath().path
        #expect(resolvedWorkspaceRootPath == resolvedTemporaryRootPath)
      default:
        Issue.record("Expected buildServerConfigurationMissing, got \(error).")
      }
    } catch {
      Issue.record("Expected MonocleError, got \(error).")
    }
  }
}
