// By Dennis Müller

import Darwin
import Foundation
@testable import MonocleCore
import Testing

final class FileDescriptorIOTests {
  @Test func readAllWithTimeoutThrowsWhenNoBytesArrive() async throws {
    var descriptors: [Int32] = [0, 0]
    let result = socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors)
    #expect(result == 0)

    let readerDescriptor = descriptors[0]
    let writerDescriptor = descriptors[1]
    defer { close(readerDescriptor) }
    defer { close(writerDescriptor) }

    let startDate = Date()
    do {
      _ = try await Task.detached {
        try FileDescriptorIO.readAll(from: readerDescriptor, timeout: 0.2)
      }.value
      Issue.record("Expected readAll(from:timeout:) to throw ETIMEDOUT when no bytes arrive.")
    } catch let error as POSIXError {
      #expect(error.code == .ETIMEDOUT)
    } catch {
      Issue.record("Expected POSIXError, got \(error).")
    }

    let elapsedSeconds = Date().timeIntervalSince(startDate)
    #expect(elapsedSeconds < 2)
  }

  @Test func readAllWithoutTimeoutReadsUntilEOF() async throws {
    var descriptors: [Int32] = [0, 0]
    let result = socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors)
    #expect(result == 0)

    let readerDescriptor = descriptors[0]
    let writerDescriptor = descriptors[1]
    defer { close(readerDescriptor) }
    defer { close(writerDescriptor) }

    let payload = Data("hello".utf8)
    try FileDescriptorIO.writeAll(payload, to: writerDescriptor)
    _ = Darwin.shutdown(writerDescriptor, SHUT_WR)

    let readPayload = try await Task.detached {
      try FileDescriptorIO.readAll(from: readerDescriptor)
    }.value

    #expect(readPayload == payload)
  }
}
