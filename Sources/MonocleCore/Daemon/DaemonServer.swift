// By Dennis Müller

import Darwin
import Foundation

/// Flow overview:
/// CLI -> DaemonClient (encodes JSON) -> Unix socket -> DaemonServer -> DaemonRequestHandler -> DaemonSessionManager ->
/// LspSession.
/// Only this file and `UnixDomainSocket.swift` touch POSIX APIs; everything else is transport agnostic.
public final class DaemonServer: @unchecked Sendable {
  private let socketURL: URL
  private let idleSessionTimeout: TimeInterval
  private let sessionManager: DaemonSessionManager
  private var serverDescriptor: Int32 = -1
  private var lockFileDescriptor: Int32 = -1
  private var acceptTask: Task<Void, Never>?
  private var reapTask: Task<Void, Never>?
  private var shutdownContinuation: CheckedContinuation<Void, Never>?
  private var isStopping = false

  /// Creates a daemon server that listens for monocle requests.
  ///
  /// - Parameters:
  ///   - socketURL: Filesystem URL where the Unix domain socket should be created.
  ///   - idleSessionTimeout: Duration, in seconds, after which idle sessions are reaped.
  ///   - toolchain: Optional toolchain configuration forwarded to new sessions.
  public init(
    socketURL: URL = DaemonSocketConfiguration.defaultSocketURL,
    idleSessionTimeout: TimeInterval = 600,
    toolchain: ToolchainConfiguration? = nil,
  ) {
    self.socketURL = socketURL
    self.idleSessionTimeout = idleSessionTimeout
    sessionManager = DaemonSessionManager(toolchain: toolchain)
  }

  /// Starts the server and suspends until a shutdown request is received or stop() is called.
  public func run() async throws {
    try acquireProcessLock()

    do {
      try prepareSocketPath()
      serverDescriptor = try UnixDomainSocket.openListener(at: socketURL.path)
      try writePidFile()
    } catch {
      releaseProcessLock()
      removeSocketFile()
      removePidFile()
      throw error
    }

    acceptTask = Task.detached { [weak self] in
      guard let self else { return }

      await acceptLoop()
    }

    reapTask = Task.detached { [weak self] in
      guard let self else { return }

      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
        await sessionManager.reapIdleSessions(olderThan: idleSessionTimeout)
      }
    }

    await withCheckedContinuation { continuation in
      shutdownContinuation = continuation
    }
  }

  /// Triggers a graceful shutdown.
  public func stop() {
    guard !isStopping else { return }

    isStopping = true
    acceptTask?.cancel()
    reapTask?.cancel()
    if serverDescriptor >= 0 {
      close(serverDescriptor)
      serverDescriptor = -1
    }
    Task.detached { [sessionManager] in
      await sessionManager.shutdownAll()
    }
    shutdownContinuation?.resume()
    shutdownContinuation = nil
    removeSocketFile()
    removePidFile()
    releaseProcessLock()
  }

  // MARK: - Private helpers

  private func acquireProcessLock() throws {
    let lockFileURL = DaemonRuntimeConfiguration.lockFileURL
    try? FileManager.default.createDirectory(
      at: lockFileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )

    lockFileDescriptor = Darwin.open(lockFileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard lockFileDescriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    let lockResult = flock(lockFileDescriptor, LOCK_EX | LOCK_NB)
    guard lockResult == 0 else {
      let errorCode = POSIXErrorCode(rawValue: errno) ?? .EIO
      close(lockFileDescriptor)
      lockFileDescriptor = -1

      if errorCode == .EWOULDBLOCK {
        throw MonocleError.ioError("Another monocle daemon instance appears to be running.")
      }

      throw POSIXError(errorCode)
    }
  }

  private func releaseProcessLock() {
    guard lockFileDescriptor >= 0 else { return }

    _ = flock(lockFileDescriptor, LOCK_UN)
    close(lockFileDescriptor)
    lockFileDescriptor = -1
  }

  private func writePidFile() throws {
    let pidFileURL = DaemonRuntimeConfiguration.pidFileURL
    try? FileManager.default.createDirectory(
      at: pidFileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )

    let processIdentifier = ProcessInfo.processInfo.processIdentifier
    try String(processIdentifier).write(to: pidFileURL, atomically: true, encoding: .utf8)
  }

  private func removePidFile() {
    let pidFileURL = DaemonRuntimeConfiguration.pidFileURL
    if FileManager.default.fileExists(atPath: pidFileURL.path) {
      try? FileManager.default.removeItem(at: pidFileURL)
    }
  }

  /// Accepts incoming socket connections and hands them to `handleClient`.
  private func acceptLoop() async {
    while !Task.isCancelled {
      do {
        let clientDescriptor = try UnixDomainSocket.accept(from: serverDescriptor)
        Task.detached { [weak self] in
          await self?.handleClient(descriptor: clientDescriptor)
        }
      } catch let error as POSIXError where error.code == .EINTR || error.code == .EAGAIN {
        continue
      } catch {
        stop()
        return
      }
    }
  }

  /// Handles a single client connection from request decoding to response writing.
  ///
  /// - Parameter descriptor: Connected client file descriptor.
  private func handleClient(descriptor: Int32) async {
    defer { close(descriptor) }

    do {
      let requestData = try FileDescriptorIO.readAll(from: descriptor)
      let decodedRequest = try JSONDecoder().decode(DaemonRequest.self, from: requestData)
      let handler = DaemonRequestHandler(
        sessionManager: sessionManager,
        socketPath: socketURL.path,
        idleSessionTimeout: idleSessionTimeout,
      )
      let response = await handler.handle(decodedRequest)
      try FileDescriptorIO.writeAll(JSONEncoder().encode(response), to: descriptor)

      if decodedRequest.method == .shutdown {
        stop()
      }
    } catch let decodingError as DecodingError {
      let response = DaemonResponse(
        id: UUID(),
        error: DaemonErrorPayload(code: "decode_error", message: decodingError.localizedDescription),
      )
      try? FileDescriptorIO.writeAll(try JSONEncoder().encode(response), to: descriptor)
    } catch {
      let response = DaemonResponse(
        id: UUID(),
        error: DaemonErrorPayload(code: "server_error", message: error.localizedDescription),
      )
      try? FileDescriptorIO.writeAll(try JSONEncoder().encode(response), to: descriptor)
    }
  }

  /// Ensures the socket directory exists and removes any stale socket file.
  private func prepareSocketPath() throws {
    let directoryURL = socketURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: socketURL.path) {
      do {
        let descriptor = try UnixDomainSocket.connect(path: socketURL.path)
        close(descriptor)
        throw MonocleError.ioError("A daemon is already listening on \(socketURL.path).")
      } catch let error as POSIXError where error.code == .ECONNREFUSED || error.code == .ENOENT {
        try FileManager.default.removeItem(at: socketURL)
      }
    }
  }

  /// Deletes the socket file if it still exists.
  private func removeSocketFile() {
    if FileManager.default.fileExists(atPath: socketURL.path) {
      try? FileManager.default.removeItem(at: socketURL)
    }
  }
}
