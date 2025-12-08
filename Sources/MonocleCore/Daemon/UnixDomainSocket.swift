// By Dennis Müller

import Darwin
import Foundation

/// Thin wrappers around Unix domain sockets so the rest of the daemon code does not touch `sockaddr_un`.
enum UnixDomainSocket {
  /// Creates a connected client descriptor for the given path.
  /// The caller is responsible for closing the returned descriptor.
  ///
  /// - Parameter path: Filesystem path of the Unix domain socket.
  /// - Returns: Connected client descriptor.
  /// - Throws: `POSIXError` when the socket cannot be opened or connected.
  static func connect(path: String) throws -> Int32 {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathData = path.utf8CString
    guard pathData.count <= MemoryLayout.size(ofValue: address.sun_path) else {
      close(descriptor)
      throw POSIXError(.ENAMETOOLONG)
    }

    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
      pointer.withMemoryRebound(to: CChar.self, capacity: pathData.count) { destination in
        _ = pathData.withUnsafeBufferPointer { source in
          memcpy(destination, source.baseAddress, source.count)
        }
      }
    }

    let length = socklen_t(MemoryLayout.size(ofValue: address.sun_family) + pathData.count)
    let connectionResult = withUnsafePointer(to: &address) { pointer -> Int32 in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        Darwin.connect(descriptor, sockaddrPointer, length)
      }
    }
    guard connectionResult == 0 else {
      let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      close(descriptor)
      throw error
    }

    return descriptor
  }

  /// Creates, binds, and listens on a Unix domain socket at `path`.
  /// Returns the listening descriptor; the caller is responsible for closing it.
  ///
  /// - Parameter path: Filesystem path of the Unix domain socket.
  /// - Returns: Listening socket descriptor.
  /// - Throws: `POSIXError` when creation, bind, or listen fails.
  static func openListener(at path: String) throws -> Int32 {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathData = path.utf8CString
    guard pathData.count <= MemoryLayout.size(ofValue: address.sun_path) else {
      close(descriptor)
      throw POSIXError(.ENAMETOOLONG)
    }

    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
      pointer.withMemoryRebound(to: CChar.self, capacity: pathData.count) { destination in
        _ = pathData.withUnsafeBufferPointer { source in
          memcpy(destination, source.baseAddress, source.count)
        }
      }
    }

    let length = socklen_t(MemoryLayout.size(ofValue: address.sun_family) + pathData.count)
    let bindResult = withUnsafePointer(to: &address) { pointer -> Int32 in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        Darwin.bind(descriptor, sockaddrPointer, length)
      }
    }
    guard bindResult == 0 else {
      let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      close(descriptor)
      throw error
    }
    guard listen(descriptor, 8) == 0 else {
      let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      close(descriptor)
      throw error
    }

    return descriptor
  }

  /// Accepts a single connection from a listening descriptor, returning the client descriptor.
  ///
  /// - Parameter descriptor: Listening socket descriptor returned by `openListener`.
  /// - Returns: Connected client descriptor.
  /// - Throws: `POSIXError` when accept fails.
  static func accept(from descriptor: Int32) throws -> Int32 {
    var address = sockaddr()
    var length = socklen_t(MemoryLayout<sockaddr>.size)
    let clientDescriptor = withUnsafeMutablePointer(to: &address) { pointer -> Int32 in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        Darwin.accept(descriptor, sockaddrPointer, &length)
      }
    }
    guard clientDescriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    return clientDescriptor
  }
}
