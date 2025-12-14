## [1.3.0]

### Added
- **Checked-out package listing**: Added `monocle packages` to list all SwiftPM package checkouts for the current workspace, including each checkout folder path and (when present) the README path. For Xcode workspaces/projects this uses `buildServer.json`’s `build_root` to locate DerivedData `SourcePackages/checkouts`; for pure SwiftPM packages it scans `./.build/checkouts`.

## [1.2.1]

### Fixed
- **Enriched symbol search timeouts**: `monocle symbol --enrich` no longer times out due to daemon socket request time limits; daemon requests now use operation-appropriate timeouts and the socket read timeout is enforced reliably.

## [1.2.0]

### Added
- **Workspace option alias**: Added `--project` as an alias for `--workspace` to make workspace selection more discoverable across commands.

### Enhanced
- **Actionable build server setup guidance**: Missing `buildServer.json` errors for Xcode workspaces/projects now include concrete next steps (including `xcode-build-server` examples).

### Fixed
- **Explicit Xcode bundle handling**: Passing an explicit `.xcodeproj` or `.xcworkspace` path no longer gets misclassified by workspace auto-detection.
- **Manifest path support**: Passing a `Package.swift` path now correctly resolves the workspace root for SwiftPM projects.

## [1.1.0]
### Added
- **Workspace symbol search command**: Added `monocle symbol` to query workspace symbols with a configurable limit and optional enriched output via the CLI and daemon.

### Enhanced
### Fixed
