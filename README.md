# monocle

A read-only CLI for Swift symbol lookup via SourceKit-LSP, designed specifically for coding agents. Point it at a file, line, and column, and monocle resolves the symbol and returns its definition location, signature, and documentation—perfect for agents that need to understand unfamiliar APIs, including types from external Swift packages, without opening Xcode.

## Why monocle

- **Built for agents:** Stable, pretty-printed JSON output (`--json`) mirrors the internal `SymbolInfo` model, making it easy for tools and agents to parse.
- **Everything in one call:** `monocle inspect` returns both definition and docs together—ideal for grabbing signatures and docstrings from third-party packages or unfamiliar frameworks.
- **Fast lookups across dependencies:** Resolve symbols from your dependencies (SwiftPM or Xcode) without firing up an IDE. Great when agents need the actual implementation file and docstring.
- **Keep it warm:** Optional `monocle serve` keeps SourceKit-LSP running to eliminate cold starts during repeated agent calls.
- **Workspace aware:** Automatically finds your `Package.swift`, `.xcodeproj`, or `.xcworkspace` when you don't specify `--workspace`.
- **Works everywhere:** Supports both Swift packages and Xcode projects/workspaces.

## Installation

### Homebrew (recommended)
```bash
brew install SwiftedMind/tap/monocle
```

### From source
```bash
git clone https://github.com/SwiftedMind/monocle.git
cd monocle
swift build --configuration release
# optional: make it globally available
cp .build/release/monocle /usr/local/bin/
```

## Requirements

- macOS 13 or newer
- Xcode or a Swift toolchain that provides `sourcekit-lsp` on your PATH (monocle uses `xcrun sourcekit-lsp`)

## Quick start

Inspect the symbol under the cursor (human-readable output):
```bash
monocle inspect --file Sources/App/FooView.swift --line 42 --column 17
```

Same call with JSON output for agents and tools:
```bash
monocle inspect --file Sources/App/FooView.swift --line 42 --column 17 --json
```

If you prefer shorter commands, `inspect` is the default subcommand:
```bash
monocle --file Sources/App/FooView.swift --line 42 --column 17
```

### What agents get

- Symbol name, kind, and module
- Definition URI with line/column range, plus an extracted snippet
- Signature and rendered doc comment (when available)
- Stable JSON shape (`SymbolInfo`) that's easy to ingest for retrieval-augmented workflows or code-review bots

Example JSON output:
```json
{
  "symbol": "FancyService.loadData(_:)",
  "definition": {
    "uri": "file:///.../Sources/FancyService.swift",
    "startLine": 10,
    "endLine": 24,
    "snippet": "public func loadData(_ id: ID) async throws -> Response { ... }"
  },
  "signature": "public func loadData(_ id: ID) async throws -> Response",
  "documentation": "/// Loads data from the backend."
}
```

## Commands

- `inspect` — get definition and hover information together
- `definition` — get just the definition location and snippet
- `hover` — get just the signature and documentation
- `serve` — start the persistent daemon
- `status` — show daemon socket, idle timeout, and active LSP sessions
- `stop` — stop the daemon
- `version` — print monocle and SourceKit-LSP versions

Common options for symbol commands:
- `--workspace /path/to/root` (optional) – override automatic workspace detection
- `--file /path/to/File.swift` – source file containing the symbol
- `--line <int>` and `--column <int>` – one-based position of the symbol
- `--json` – output pretty-printed JSON instead of text

## Daemon mode

Speed up repeated lookups by keeping SourceKit-LSP alive:
```bash
monocle serve --idle-timeout 900
```

- Default socket: `~/Library/Caches/monocle/daemon.sock` (customize with `--socket`)
- CLI commands automatically connect to the daemon when the socket exists, falling back to a one-shot session if unreachable
- Check status: `monocle status` or `monocle status --json`
- Stop the daemon: `monocle stop`

## Output details

Human-readable output prints the symbol name, kind, module, signature, definition path with range, and an optional snippet and documentation. JSON output mirrors the `SymbolInfo` structure used internally, making it convenient for tools and CI pipelines.

## Troubleshooting

- Make sure `sourcekit-lsp` works by running `xcrun sourcekit-lsp --version` manually. If it fails, install Xcode or the Swift toolchain.
- For SwiftPM workspaces, monocle creates a scratch directory at `.sourcekit-lsp-scratch` under the workspace root. You can safely remove it if you need a clean slate.
- If monocle can't find your workspace, use `--workspace` to point directly at your package or Xcode project.
