// By Dennis Müller

import Darwin
import Foundation

/// Utilities for fully reading from and writing to POSIX file descriptors.
/// Centralizes the low-level loops so the rest of the daemon code can stay free of `Darwin` calls.
enum FileDescriptorIO {
  /// Reads all available bytes from the descriptor until EOF or until the optional timeout expires.
  /// - Parameters:
  ///   - descriptor: An open file descriptor to read from.
  ///   - timeout: Optional duration after which the read will abort with `.ETIMEDOUT`.
  /// - Returns: The accumulated data.
  static func readAll(from descriptor: Int32, timeout: TimeInterval? = nil) throws -> Data {
    if let timeout {
      return try readAllWithTimeout(from: descriptor, timeout: timeout)
    }

    return try readAllWithoutTimeout(from: descriptor)
  }

  /// Writes the complete data buffer to the descriptor, retrying partial writes until finished.
  /// - Parameters:
  ///   - data: The bytes to write.
  ///   - descriptor: An open file descriptor to write to.
  static func writeAll(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { pointer in
      guard let baseAddress = pointer.baseAddress else { return }

      var remainingByteCount = pointer.count
      var offset = 0
      while remainingByteCount > 0 {
        let written = Darwin.write(descriptor, baseAddress.advanced(by: offset), remainingByteCount)
        if written < 0 {
          let currentError = POSIXErrorCode(rawValue: errno) ?? .EIO
          if currentError == .EINTR {
            continue
          }
          throw POSIXError(currentError)
        }
        remainingByteCount -= written
        offset += written
      }
    }
  }

  // MARK: - Private

  private static func readAllWithoutTimeout(from descriptor: Int32) throws -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)

    while true {
      let readCount = buffer.withUnsafeMutableBytes { pointer -> Int in
        guard let baseAddress = pointer.baseAddress else { return 0 }

        return Darwin.read(descriptor, baseAddress, pointer.count)
      }

      if readCount > 0 {
        data.append(buffer, count: readCount)
        continue
      }

      if readCount == 0 {
        break
      }

      let currentError = POSIXErrorCode(rawValue: errno) ?? .EIO
      if currentError == .EINTR {
        continue
      }
      throw POSIXError(currentError)
    }

    return data
  }

  private static func readAllWithTimeout(from descriptor: Int32, timeout: TimeInterval) throws -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)

    let deadline = Date().addingTimeInterval(timeout)
    let originalFlags = fcntl(descriptor, F_GETFL)
    if originalFlags >= 0 {
      _ = fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK)
    }
    defer {
      if originalFlags >= 0 {
        _ = fcntl(descriptor, F_SETFL, originalFlags)
      }
    }

    while true {
      let readCount = buffer.withUnsafeMutableBytes { pointer -> Int in
        guard let baseAddress = pointer.baseAddress else { return 0 }

        return Darwin.read(descriptor, baseAddress, pointer.count)
      }

      if readCount > 0 {
        data.append(buffer, count: readCount)
        continue
      }

      if readCount == 0 {
        break
      }

      let currentError = POSIXErrorCode(rawValue: errno) ?? .EIO
      if currentError == .EINTR {
        continue
      }

      if currentError == .EAGAIN || currentError == .EWOULDBLOCK {
        let remainingTime = deadline.timeIntervalSinceNow
        if remainingTime <= 0 {
          throw POSIXError(.ETIMEDOUT)
        }

        var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        let timeoutMilliseconds = Int32(remainingTime * 1000)
        let pollResult = Darwin.poll(&pollDescriptor, 1, timeoutMilliseconds)
        if pollResult == 0 {
          throw POSIXError(.ETIMEDOUT)
        }
        if pollResult < 0 {
          let pollError = POSIXErrorCode(rawValue: errno) ?? .EIO
          if pollError == .EINTR {
            continue
          }
          throw POSIXError(pollError)
        }

        continue
      }

      throw POSIXError(currentError)
    }

    return data
  }
}
