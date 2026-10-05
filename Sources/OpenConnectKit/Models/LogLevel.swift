//
//  LogLevel.swift
//  OpenConnectKit
//
//  Log level enumeration for VPN session messages
//

import Foundation

/// Log level for VPN session messages.
///
/// Controls the verbosity of logging output from the VPN session.
/// Higher levels include messages from lower levels (e.g., `.debug` includes `.info` and `.error`).
///
/// Levels compare by verbosity, `.error < .info < .debug < .trace`, so
/// `entries.filter { $0.level <= .info }` keeps errors and informational messages.
public enum LogLevel: String, Codable, Sendable, CaseIterable, Comparable {
  /// Error messages only - critical issues that prevent operation.
  case error

  /// Informational messages - normal operation events.
  case info

  /// Debug messages - detailed information for troubleshooting.
  case debug

  /// Verbose trace messages - extremely detailed execution flow, including the HTTP traffic of
  /// the login, credentials and all.
  case trace

  public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
    lhs.openConnectLevel < rhs.openConnectLevel
  }
}
