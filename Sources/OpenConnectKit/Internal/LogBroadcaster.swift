//
//  LogBroadcaster.swift
//  OpenConnectKit
//
//  Fans log entries out to every VpnSession.logs stream
//

import Foundation
import Synchronization

// Hands each reader of `VpnSession.logs` its own stream and copies every entry into all of them.
//
// An `AsyncStream` supports one reader, and ends for good once that reader's task is cancelled,
// which happens whenever a SwiftUI `.task` restarts. A stream per reader avoids both.
//
// Entries are yielded straight from openconnect's thread, without a hop to the main actor:
// at trace level there can be a lot of them.
final class LogBroadcaster: Sendable {
  /// How far a reader can fall behind before its oldest entries are dropped.
  static let bufferSize = 1_000

  private let continuations = Mutex<[UUID: AsyncStream<LogEntry>.Continuation]>([:])

  /// A new stream that receives every entry from now on, until it's cancelled or `finish()`.
  func makeStream() -> AsyncStream<LogEntry> {
    let (stream, continuation) = AsyncStream.makeStream(
      of: LogEntry.self, bufferingPolicy: .bufferingNewest(Self.bufferSize))
    let id = UUID()
    continuation.onTermination = { [weak self] _ in
      self?.continuations.withLock { _ = $0.removeValue(forKey: id) }
    }
    continuations.withLock { $0[id] = continuation }
    return stream
  }

  func yield(_ entry: LogEntry) {
    // Yield outside the lock: a stream's onTermination handler takes it too.
    for continuation in continuations.withLock({ Array($0.values) }) {
      continuation.yield(entry)
    }
  }

  /// Ends every stream.
  func finish() {
    let all = continuations.withLock { continuations in
      defer { continuations.removeAll() }
      return Array(continuations.values)
    }
    for continuation in all {
      continuation.finish()
    }
  }
}
