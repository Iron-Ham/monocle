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
  
  public init(workspace: Workspace, toolchain: ToolchainConfiguration? = nil) {
    self.workspace = workspace
    self.toolchain = toolchain
    self.sourceKitService = SourceKitService()
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
      documentation: hoverInfo.documentation ?? definitionInfo.documentation
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
  
  private func ensureSessionReady() async throws -> InitializingServer {
    if let existing = server {
      return existing
    }
    let initialized = try await sourceKitService.start(workspace: workspace, toolchain: toolchain)
    server = initialized
    return initialized
  }
  
  private func fetchDefinition(connection: InitializingServer, file: String, line: Int, column: Int) async throws -> SymbolInfo {
    let textDocumentParams = try makeTextDocumentPosition(file: file, line: line, column: column)
    try await openIfNeeded(connection: connection, file: file)
    let retryPolicy = makeRetryPolicy()
    guard let response = try await performWithRetries(maxAttempts: retryPolicy.maxAttempts, delayNanoseconds: retryPolicy.delayNanoseconds, {
      try await connection.definition(textDocumentParams)
    }) else {
      throw MonocleError.symbolNotFound
    }
    let location = try resolveLocation(from: response)
    return SymbolInfo(
      symbol: location.symbolName,
      kind: location.kind,
      module: location.moduleName,
      definition: location.info,
      signature: nil,
      documentation: nil
    )
  }
  
  private func fetchHover(connection: InitializingServer, file: String, line: Int, column: Int) async throws -> SymbolInfo {
    let textDocumentParams = try makeTextDocumentPosition(file: file, line: line, column: column)
    try await openIfNeeded(connection: connection, file: file)
    let retryPolicy = makeRetryPolicy()
    guard let hoverResponse = try await performWithRetries(maxAttempts: retryPolicy.maxAttempts, delayNanoseconds: retryPolicy.delayNanoseconds, {
      try await connection.hover(textDocumentParams)
    }) else {
      throw MonocleError.symbolNotFound
    }
    let rendered = renderHover(hoverResponse)
    return SymbolInfo(
      symbol: rendered.symbol,
      kind: rendered.kind,
      module: rendered.module,
      definition: nil,
      signature: rendered.signature,
      documentation: rendered.documentation
    )
  }
  
  private func makeTextDocumentPosition(file: String, line: Int, column: Int) throws -> TextDocumentPositionParams {
    guard line > 0, column > 0 else {
      throw MonocleError.ioError("Line and column must be one-based positive values.")
    }
    let uri = URL(fileURLWithPath: file).absoluteString
    let position = Position(line: line - 1, character: column - 1)
    return TextDocumentPositionParams(textDocument: TextDocumentIdentifier(uri: uri), position: position)
  }
  
  private func openIfNeeded(connection: InitializingServer, file: String) async throws {
    let uri = URL(fileURLWithPath: file).absoluteString
    if openedDocuments.contains(uri) { return }
    let text = try String(contentsOfFile: file)
    let item = TextDocumentItem(uri: uri, languageId: "swift", version: 1, text: text)
    try await connection.textDocumentDidOpen(DidOpenTextDocumentParams(textDocument: item))
    openedDocuments.insert(uri)
  }
  
  private func resolveLocation(from response: DefinitionResponse) throws -> (info: SymbolInfo.Location, symbolName: String?, kind: String?, moduleName: String?) {
    switch response {
    case .optionA(let singleLocation):
      let locationInfo = try makeLocation(singleLocation)
      return (locationInfo, nil, nil, nil)
    case .optionB(let locations):
      guard let first = locations.first else { throw MonocleError.symbolNotFound }
      let locationInfo = try makeLocation(first)
      return (locationInfo, nil, nil, nil)
    case .optionC(let links):
      guard let first = links.first else { throw MonocleError.symbolNotFound }
      let location = first.targetSelectionRange
      let uri = URL(string: first.targetUri) ?? URL(fileURLWithPath: first.targetUri)
      let locationInfo = SymbolInfo.Location(
        uri: uri,
        startLine: location.start.line + 1,
        startCharacter: location.start.character + 1,
        endLine: location.end.line + 1,
        endCharacter: location.end.character + 1,
        snippet: extractSnippet(from: uri, range: location)
      )
      return (locationInfo, nil, nil, nil)
    case .none:
      throw MonocleError.symbolNotFound
    }
  }
  
  private func makeLocation(_ location: Location) throws -> SymbolInfo.Location {
    let uri = URL(string: location.uri) ?? URL(fileURLWithPath: location.uri)
    return SymbolInfo.Location(
      uri: uri,
      startLine: location.range.start.line + 1,
      startCharacter: location.range.start.character + 1,
      endLine: location.range.end.line + 1,
      endCharacter: location.range.end.character + 1,
      snippet: extractSnippet(from: uri, range: location.range)
    )
  }
  
  private func extractSnippet(from uri: URL, range: LSPRange) -> String? {
    guard uri.isFileURL else { return nil }
    guard let contents = try? String(contentsOf: uri) else { return nil }
    let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
    guard range.start.line < lines.count, range.end.line < lines.count else { return nil }
    let slice = lines[range.start.line...range.end.line]
    return slice.joined(separator: "\n")
  }
  
  private struct HoverRender {
    var signature: String?
    var documentation: String?
    var symbol: String?
    var kind: String?
    var module: String?
  }
  
  private func renderHover(_ hover: Hover) -> HoverRender {
    let value: String
    switch hover.contents {
    case .optionA(let marked):
      value = marked.value
    case .optionB(let markedArray):
      value = markedArray.map { $0.value }.joined(separator: "\n")
    case .optionC(let markup):
      value = markup.value
    }
    // Heuristically split signature from docs if possible.
    let components = value.components(separatedBy: "\n\n")
    let signature = components.first
    let documentation = components.dropFirst().joined(separator: "\n\n")
    return HoverRender(signature: signature, documentation: documentation.isEmpty ? nil : documentation, symbol: nil, kind: nil, module: nil)
  }

  private func performWithRetries<T>(maxAttempts: Int, delayNanoseconds: UInt64, _ operation: @escaping () async throws -> T?) async throws -> T? {
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

  private func makeRetryPolicy() -> (maxAttempts: Int, delayNanoseconds: UInt64) {
    switch workspace.kind {
    case .swiftPackage:
      return (maxAttempts: 15, delayNanoseconds: 800_000_000) // SwiftPM often needs extra time to surface build settings
    case .xcodeProject, .xcodeWorkspace:
      return (maxAttempts: 5, delayNanoseconds: 350_000_000)
    }
  }
}
