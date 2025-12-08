// By Dennis Müller

import Foundation
import MonocleCore

/// Renders SymbolInfo and daemon status results in a human-friendly format.
enum HumanReadablePrinter {
  /// Prints symbol information to stdout in a readable layout.
  ///
  /// - Parameter info: Symbol description returned by monocle.
  static func printSymbolInfo(_ info: SymbolInfo) {
    if let symbolName = info.symbol {
      print("Symbol: \(symbolName)")
    }
    if let kind = info.kind {
      print("Kind: \(kind)")
    }
    if let module = info.module {
      print("Module: \(module)")
    }
    if let signature = info.signature {
      print("\nSignature:\n\(signature)")
    }
    if let definition = info.definition {
      print("\nDefinition: \(definition.uri.absoluteString):\(definition.startLine)-\(definition.endLine)")
      if let snippet = definition.snippet {
        print("\nSnippet:\n\(snippet)")
      }
    }
    if let documentation = info.documentation {
      print("\nDocumentation:\n\(documentation)")
    }

    if info.symbol == nil, info.signature == nil, info.documentation == nil {
      print("Symbol resolution is not implemented yet.")
    }
  }

  /// Prints daemon status details to stdout.
  ///
  /// - Parameter status: Daemon status payload returned by the server.
  static func printDaemonStatus(_ status: DaemonStatus) {
    print("Daemon socket: \(status.socketPath)")
    print("Idle session timeout: \(status.idleSessionTimeoutSeconds)s")
    print("Logs: \(status.logFilePath)")
    if status.activeSessions.isEmpty {
      print("Active sessions: none")
      return
    }
    print("Active sessions (\(status.activeSessions.count)):")
    for session in status.activeSessions {
      print(" - \(session.workspaceRootPath) [\(session.kind.rawValue)] last used \(session.lastUsedISO8601)")
    }
  }
}
