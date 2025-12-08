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
  private var acceptTask: Task<Void, Never>?
  private var reapTask: Task<Void, Never>?
  private var shutdownContinuation: CheckedContinuation<Void, Never>?
  private var isStopping = false

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
    try prepareSocketPath()
    serverDescriptor = try UnixDomainSocket.openListener(at: socketURL.path)

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
  }

  // MARK: - Private helpers

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

  private func prepareSocketPath() throws {
    let directoryURL = socketURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    if FileManager.default.fileExists(atPath: socketURL.path) {
      try FileManager.default.removeItem(at: socketURL)
    }
  }

  private func removeSocketFile() {
    if FileManager.default.fileExists(atPath: socketURL.path) {
      try? FileManager.default.removeItem(at: socketURL)
    }
  }
}
