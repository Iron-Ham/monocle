# Monocle MVP Scaffolding Progress (2025-12-08)

- Added SwiftPM products and targets for `MonocleCore` (library) and `MonocleCLI` (executable `monocle`).
- Declared dependencies on ArgumentParser, LanguageServerProtocol, and LanguageClient per architecture plan.
- Implemented workspace detection (`WorkspaceLocator`) and models (`Workspace`, `SymbolInfo`, `MonocleError`, `ToolchainConfiguration`).
- Wired SourceKit-LSP: `SourceKitService` now spawns `xcrun sourcekit-lsp` via LanguageClient's `DataChannel.localProcessChannel`, initializes with client capabilities, and provides shutdown handling plus version probing.
- `LspSession` is now an actor that starts the service, sends `didOpen`, and serves `inspect`, `definition`, and `hover` by forwarding LSP requests and returning snippets.
- CLI commands now use the real session and JSON encoder; `version` reports the detected SourceKit-LSP version.
- Ensured Sendable conformance for workspace and symbol models to satisfy Swift 6 concurrency checks.
- Added daemon mode: Unix-domain-socket server that pools `LspSession` instances with idle reaping, plus CLI `serve` command and daemon-aware inspect/definition/hover commands that fall back to direct LSP if the daemon is unavailable.
- Current status (2025-12-08): `swift build --quiet` succeeds with functional LSP-backed inspect/definition/hover paths and the new daemon server/client flow for faster repeat calls.
