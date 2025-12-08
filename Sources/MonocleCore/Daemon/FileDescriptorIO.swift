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
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    let bufferLength = buffer.count
    let startDate = timeout.map { _ in Date() }

    while true {
      if let timeout, let startDate, Date().timeIntervalSince(startDate) > timeout {
        throw POSIXError(.ETIMEDOUT)
      }
      let readCount = buffer.withUnsafeMutableBytes { pointer -> Int in
        guard let baseAddress = pointer.baseAddress else { return 0 }

        return Darwin.read(descriptor, baseAddress, bufferLength)
      }
      if readCount > 0 {
        data.append(buffer, count: readCount)
      } else {
        break
      }
    }

    return data
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
          throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        remainingByteCount -= written
        offset += written
      }
    }
  }
}
