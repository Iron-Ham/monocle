// By Dennis Müller

import Foundation
import LanguageClient
import LanguageServerProtocol

/// Manages the lifetime of a single SourceKit-LSP session.
public actor LspSession {
  private let workspace: Workspace
  private let toolchain: ToolchainConfiguration?
  private let sourceKitService: SourceKitService
  private var server: InitializingServer?
  private var openedDocuments: Set<String> = []

  /// Creates a session bound to a workspace with an optional toolchain override.
  ///
  /// - Parameters:
  ///   - workspace: Workspace description that determines how SourceKit-LSP should start.
  ///   - toolchain: Optional toolchain configuration to pass through to SourceKit-LSP.
  public init(workspace: Workspace, toolchain: ToolchainConfiguration? = nil) {
    self.workspace = workspace
    self.toolchain = toolchain
    sourceKitService = SourceKitService()
  }

  /// Provides a combined definition and hover view for a symbol.
  public func inspectSymbol(file: String, line: Int, column: Int) async throws -> SymbolInfo {
    let connection = try await ensureSessionReady()
    let definitionInfo = try await fetchDefinition(connection: connection, file: file, line: line, column: column)
    let hoverInfo = try await fetchHover(connection: connection, file: file, line: line, column: column)

    return SymbolInfo(
      symbol: hoverInfo.symbol ?? definitionInfo.symbol,
      kind: definitionInfo.kind ?? hoverInfo.kind,
      module: definitionInfo.module ?? hoverInfo.module,
      definition: definitionInfo.definition,
      signature: hoverInfo.signature ?? definitionInfo.signature,
      documentation: hoverInfo.documentation ?? definitionInfo.documentation,
    )
  }

  /// Returns definition-only information for a symbol.
  public func definition(file: String, line: Int, column: Int) async throws -> SymbolInfo {
    let connection = try await ensureSessionReady()
    return try await fetchDefinition(connection: connection, file: file, line: line, column: column)
  }

  /// Returns hover-only information for a symbol.
  public func hover(file: String, line: Int, column: Int) async throws -> SymbolInfo {
    let connection = try await ensureSessionReady()
    return try await fetchHover(connection: connection, file: file, line: line, column: column)
  }

  /// Gracefully stops the LSP session.
  public func shutdown() async {
    await sourceKitService.shutdown()
    server = nil
  }

  // MARK: - Private helpers

  /// Ensures there is an initialized SourceKit-LSP connection, starting one if necessary.
  ///
  /// - Returns: An initialized server connection ready for requests.
  private func ensureSessionReady() async throws -> InitializingServer {
    if let existing = server {
      return existing
    }
    let initialized = try await sourceKitService.start(workspace: workspace, toolchain: toolchain)
    server = initialized
    return initialized
  }

  /// Looks up definition information for the provided location.
  ///
  /// - Parameters:
  ///   - connection: Active SourceKit-LSP server connection.
  ///   - file: Absolute path to the Swift source file.
  ///   - line: One-based line number where the symbol resides.
  ///   - column: One-based column number within the line.
  /// - Returns: Symbol metadata describing the resolved definition.
  /// - Throws: `MonocleError.symbolNotFound` when no definition is returned.
  private func fetchDefinition(connection: InitializingServer, file: String, line: Int,
                               column: Int) async throws -> SymbolInfo {
    let textDocumentParams = try makeTextDocumentPosition(file: file, line: line, column: column)
    try await openIfNeeded(connection: connection, file: file)
    let retryPolicy = makeRetryPolicy()
    guard let response = try await performWithRetries(
      maxAttempts: retryPolicy.maxAttempts,
      delayNanoseconds: retryPolicy.delayNanoseconds,
      {
        try await connection.definition(textDocumentParams)
      },
    ) else {
      throw MonocleError.symbolNotFound
    }

    let location = try resolveLocation(from: response)
    return SymbolInfo(
      symbol: location.symbolName,
      kind: location.kind,
      module: location.moduleName,
      definition: location.info,
      signature: nil,
      documentation: nil,
    )
  }

  /// Retrieves hover content for the provided location.
  ///
  /// - Parameters:
  ///   - connection: Active SourceKit-LSP server connection.
  ///   - file: Absolute path to the Swift source file.
  ///   - line: One-based line number where the symbol resides.
  ///   - column: One-based column number within the line.
  /// - Returns: Symbol metadata derived from hover information.
  /// - Throws: `MonocleError.symbolNotFound` when hover data is unavailable.
  private func fetchHover(connection: InitializingServer, file: String, line: Int,
                          column: Int) async throws -> SymbolInfo {
    let textDocumentParams = try makeTextDocumentPosition(file: file, line: line, column: column)
    try await openIfNeeded(connection: connection, file: file)
    let retryPolicy = makeRetryPolicy()
    guard let hoverResponse = try await performWithRetries(
      maxAttempts: retryPolicy.maxAttempts,
      delayNanoseconds: retryPolicy.delayNanoseconds,
      {
        try await connection.hover(textDocumentParams)
      },
    ) else {
      throw MonocleError.symbolNotFound
    }

    let rendered = renderHover(hoverResponse)
    return SymbolInfo(
      symbol: rendered.symbol,
      kind: rendered.kind,
      module: rendered.module,
      definition: nil,
      signature: rendered.signature,
      documentation: rendered.documentation,
    )
  }

  /// Builds a text document position request after validating line and column values.
  ///
  /// - Parameters:
  ///   - file: Absolute path to the Swift source file.
  ///   - line: One-based line number of the requested position.
  ///   - column: One-based column number of the requested position.
  /// - Returns: A `TextDocumentPositionParams` ready for LSP requests.
  /// - Throws: `MonocleError.ioError` when line or column are invalid.
  private func makeTextDocumentPosition(file: String, line: Int, column: Int) throws -> TextDocumentPositionParams {
    guard line > 0, column > 0 else {
      throw MonocleError.ioError("Line and column must be one-based positive values.")
    }

    let uri = URL(fileURLWithPath: file).absoluteString
    let position = Position(line: line - 1, character: column - 1)
    return TextDocumentPositionParams(textDocument: TextDocumentIdentifier(uri: uri), position: position)
  }

  /// Opens the document in the LSP session if it has not been opened already.
  ///
  /// - Parameters:
  ///   - connection: Active SourceKit-LSP server connection.
  ///   - file: Absolute path to the Swift source file.
  private func openIfNeeded(connection: InitializingServer, file: String) async throws {
    let uri = URL(fileURLWithPath: file).absoluteString
    if openedDocuments.contains(uri) { return }
    let text = try String(contentsOfFile: file)
    let item = TextDocumentItem(uri: uri, languageId: "swift", version: 1, text: text)
    try await connection.textDocumentDidOpen(DidOpenTextDocumentParams(textDocument: item))
    openedDocuments.insert(uri)
  }

  /// Resolves a usable location and symbol metadata from a `DefinitionResponse`.
  ///
  /// - Parameter response: The raw LSP definition response.
  /// - Returns: Tuple containing a prepared location and optional symbol metadata.
  /// - Throws: `MonocleError.symbolNotFound` when the response is empty.
  private func resolveLocation(from response: DefinitionResponse) throws
    -> (info: SymbolInfo.Location, symbolName: String?, kind: String?, moduleName: String?) {
    switch response {
    case let .optionA(singleLocation):
      let locationInfo = try makeLocation(singleLocation)
      return (locationInfo, nil, nil, nil)
    case let .optionB(locations):
      guard let first = locations.first else { throw MonocleError.symbolNotFound }

      let locationInfo = try makeLocation(first)
      return (locationInfo, nil, nil, nil)
    case let .optionC(links):
      guard let first = links.first else { throw MonocleError.symbolNotFound }

      let location = first.targetSelectionRange
      let uri = URL(string: first.targetUri) ?? URL(fileURLWithPath: first.targetUri)
      let locationInfo = SymbolInfo.Location(
        uri: uri,
        startLine: location.start.line + 1,
        startCharacter: location.start.character + 1,
        endLine: location.end.line + 1,
        endCharacter: location.end.character + 1,
        snippet: extractSnippet(from: uri, range: location),
      )
      return (locationInfo, nil, nil, nil)
    case .none:
      throw MonocleError.symbolNotFound
    }
  }

  /// Converts an LSP `Location` into the `SymbolInfo.Location` representation.
  ///
  /// - Parameter location: LSP location containing URI and range.
  /// - Returns: A converted location with one-based line and column values.
  /// - Throws: `MonocleError.symbolNotFound` when the URI is malformed.
  private func makeLocation(_ location: Location) throws -> SymbolInfo.Location {
    let uri = URL(string: location.uri) ?? URL(fileURLWithPath: location.uri)
    return SymbolInfo.Location(
      uri: uri,
      startLine: location.range.start.line + 1,
      startCharacter: location.range.start.character + 1,
      endLine: location.range.end.line + 1,
      endCharacter: location.range.end.character + 1,
      snippet: extractSnippet(from: uri, range: location.range),
    )
  }

  /// Extracts a code snippet for the given URI and LSP range, if the URI is file-based.
  ///
  /// - Parameters:
  ///   - uri: URI pointing to a file on disk.
  ///   - range: Zero-based LSP range describing the snippet bounds.
  /// - Returns: The joined snippet text or `nil` when the file cannot be read.
  private func extractSnippet(from uri: URL, range: LSPRange) -> String? {
    guard uri.isFileURL else { return nil }
    guard let contents = try? String(contentsOf: uri) else { return nil }

    let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
    guard range.start.line < lines.count, range.end.line < lines.count else { return nil }

    let slice = lines[range.start.line...range.end.line]
    return slice.joined(separator: "\n")
  }

  private struct HoverRender {
    /// Rendered signature text extracted from hover content.
    var signature: String?
    /// Documentation body extracted from hover content.
    var documentation: String?
    /// Symbol display name when available from hover content.
    var symbol: String?
    /// Symbol kind when available from hover content.
    var kind: String?
    /// Module name when available from hover content.
    var module: String?
  }

  /// Splits hover content into signature and documentation components.
  ///
  /// - Parameter hover: Raw hover response returned by SourceKit-LSP.
  /// - Returns: A structured render containing signature and documentation text when present.
  private func renderHover(_ hover: Hover) -> HoverRender {
    let value: String = switch hover.contents {
    case let .optionA(marked):
      marked.value
    case let .optionB(markedArray):
      markedArray.map(\.value).joined(separator: "\n")
    case let .optionC(markup):
      markup.value
    }
    // Heuristically split signature from docs if possible.
    let components = value.components(separatedBy: "\n\n")
    let signature = components.first
    let documentation = components.dropFirst().joined(separator: "\n\n")
    return HoverRender(
      signature: signature,
      documentation: documentation.isEmpty ? nil : documentation,
      symbol: nil,
      kind: nil,
      module: nil,
    )
  }

  /// Repeatedly executes an async operation until it produces a value or attempts are exhausted.
  ///
  /// - Parameters:
  ///   - maxAttempts: Maximum number of attempts to make.
  ///   - delayNanoseconds: Delay inserted between attempts.
  ///   - operation: Async operation that returns an optional value.
  /// - Returns: The first non-`nil` result or `nil` when attempts are exhausted.
  private func performWithRetries<T>(
    maxAttempts: Int,
    delayNanoseconds: UInt64,
    _ operation: @escaping () async throws -> T?,
  ) async throws -> T? {
    var attempt = 0
    while attempt < maxAttempts {
      if let result = try await operation() {
        return result
      }
      attempt += 1
      try await Task.sleep(nanoseconds: delayNanoseconds) // allow build settings to arrive from build server
    }
    return nil
  }

  /// Chooses retry behavior tuned to the workspace kind.
  ///
  /// - Returns: Attempt and delay values suitable for SourceKit-LSP readiness.
  private func makeRetryPolicy() -> (maxAttempts: Int, delayNanoseconds: UInt64) {
    switch workspace.kind {
    case .swiftPackage:
      (maxAttempts: 15, delayNanoseconds: 800_000_000) // SwiftPM often needs extra time to surface build settings
    case .xcodeProject, .xcodeWorkspace:
      (maxAttempts: 5, delayNanoseconds: 350_000_000)
    }
  }
}
