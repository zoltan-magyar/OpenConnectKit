//
//  LogEntry.swift
//  OpenConnectKit
//
//  Structured log entry for VPN session logging
//

import Foundation

/// A structured log entry from the VPN session.
///
/// Log entries are emitted by the OpenConnect library during connection
/// and mainloop operation. Read them from `VPNSession.logs`, an `AsyncStream`.
public struct LogEntry: Sendable, Identifiable {
  public let id: UUID
  public let timestamp: Date
  public let level: LogLevel
  public let message: String

  public init(level: LogLevel, message: String) {
    self.id = UUID()
    self.timestamp = Date()
    self.level = level
    self.message = message
  }
}
