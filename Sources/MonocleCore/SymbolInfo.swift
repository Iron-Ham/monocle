// By Dennis Müller

import Foundation

/// Represents the resolved information for a Swift symbol.
public struct SymbolInfo: Codable, Sendable {
  /// A concrete source location describing where a symbol is defined.
  public struct Location: Codable, Sendable {
    /// Absolute URI of the file that contains the symbol.
    public var uri: URL
    /// One-based line where the symbol range starts.
    public var startLine: Int
    /// One-based character offset where the symbol range starts.
    public var startCharacter: Int
    /// One-based line where the symbol range ends.
    public var endLine: Int
    /// One-based character offset where the symbol range ends.
    public var endCharacter: Int
    /// Optional code excerpt surrounding the symbol range.
    public var snippet: String?

    /// Creates a location value describing the range of a symbol definition.
    ///
    /// - Parameters:
    ///   - uri: Absolute URI for the file containing the symbol.
    ///   - startLine: One-based starting line of the symbol range.
    ///   - startCharacter: One-based starting character within the starting line.
    ///   - endLine: One-based ending line of the symbol range.
    ///   - endCharacter: One-based ending character within the ending line.
    ///   - snippet: Optional code snippet covering the symbol range.
    public init(
      uri: URL,
      startLine: Int,
      startCharacter: Int,
      endLine: Int,
      endCharacter: Int,
      snippet: String? = nil,
    ) {
      self.uri = uri
      self.startLine = startLine
      self.startCharacter = startCharacter
      self.endLine = endLine
      self.endCharacter = endCharacter
      self.snippet = snippet
    }
  }

  /// Display name of the symbol, if provided by SourceKit-LSP.
  public var symbol: String?
  /// Symbol kind description such as "class" or "function".
  public var kind: String?
  /// Module that defines the symbol.
  public var module: String?
  /// Definition location metadata.
  public var definition: Location?
  /// Rendered signature for the symbol.
  public var signature: String?
  /// Documentation string gathered from hover or definition data.
  public var documentation: String?

  /// Creates an aggregated symbol description.
  ///
  /// - Parameters:
  ///   - symbol: Display name of the symbol.
  ///   - kind: Symbol kind description.
  ///   - module: Module that declares the symbol.
  ///   - definition: Source location where the symbol is defined.
  ///   - signature: Rendered signature suitable for display.
  ///   - documentation: Associated documentation content.
  public init(
    symbol: String? = nil,
    kind: String? = nil,
    module: String? = nil,
    definition: Location? = nil,
    signature: String? = nil,
    documentation: String? = nil,
  ) {
    self.symbol = symbol
    self.kind = kind
    self.module = module
    self.definition = definition
    self.signature = signature
    self.documentation = documentation
  }
}
