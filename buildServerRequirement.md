
• - What changed: When we launch sourcekit-lsp we now pass --default-workspace-type buildServer if we detect a buildServer.json at the workspace root and the workspace isn’t a SwiftPM package. That tells SourceKit-LSP to talk to the Xcode build
    server instead of treating the project like a plain SwiftPM workspace.
  - Why it fixes the issue:
      - In an Xcode workspace, build settings (target triple, SDK, include paths, Swift macro plugins, derived data locations, SwiftPM dependencies, etc.) come from Xcode’s build system.
      - Without the build-server handshake, SourceKit-LSP fell back to a bare “syntax-only” open with just -sdk <macOS SDK> file.swift—no module search paths—so symbols that live in dependencies (your SQLiteData package) were invisible, leading
        to symbolNotFound.
      - With --default-workspace-type buildServer, SourceKit-LSP asks the Xcode build server for the full compile command. That includes the derived-data Build/Products and SourcePackages paths, so it can find SQLiteData (and other deps/macros),
        resolve the symbol, and return hover/definition data.
  - Do you need buildServer.json?
      - For Xcode workspaces/projects: yes, SourceKit-LSP relies on a build server to fetch accurate build settings. Xcode 15+ can generate buildServer.json (File > Packages > Generate Build Server Configuration…) or you can create it manually; you
        already have one in Noema/ so detection succeeds.
      - For pure SwiftPM packages: no—SourceKit-LSP reads Package.swift directly, so we skip the flag in that case.
      - If buildServer.json is missing in an Xcode project, SourceKit-LSP will default to SwiftPM mode and you’ll see the same missing-dependency behavior. Adding/generating the file (or invoking SourceKit-LSP with explicit --build-
        path/--configuration and a compilation database) is the proper fix.
  - Summary: The new flag makes monocle choose the Xcode build-server path when available, supplying the correct build settings for workspace targets and their SwiftPM dependencies, which is why dependency symbols now resolve.
