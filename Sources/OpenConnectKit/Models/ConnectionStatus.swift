//
//  ConnectionStatus.swift
//  OpenConnectKit
//
//  Connection status types for VPN sessions
//

import Foundation

/// The state of a VPN session's connection.
///
/// Why the last connection failed, if it did, is in `VPNSession.lastError`.
///
/// ## Example Usage
///
/// ```swift
/// switch session.status {
/// case .disconnected:
///     print(session.lastError?.localizedDescription ?? "Disconnected")
/// case .connecting(let stage):
///     print("Connecting: \(stage)")
/// case .connected(let info):
///     print("Connected through \(info.interfaceName ?? "an unknown interface")")
/// case .reconnecting:
///     print("Reconnecting...")
/// case .disconnecting:
///     print("Disconnecting...")
/// }
/// ```
public enum ConnectionStatus: Hashable, Sendable {
  /// Not connected. If the last connection failed, `VPNSession.lastError` says why.
  case disconnected

  /// A connection is being set up; the associated value is the current step.
  case connecting(ConnectionStage)

  /// The tunnel is up.
  case connected(ConnectionInfo)

  /// The connection was lost and openconnect is trying to re-establish it. The tunnel's
  /// details stay valid meanwhile.
  ///
  /// - Note: Not reported yet. openconnect reconnects inside its mainloop and only says so once
  ///   a reconnect has succeeded, so until it can also report the start of one, the status
  ///   stays `.connected` during an outage.
  case reconnecting(ConnectionInfo)

  /// The connection is being shut down. The status becomes `.disconnected` once that's done.
  case disconnecting
}

// MARK: - Convenience

extension ConnectionStatus {
  /// The tunnel's details while connected or reconnecting, otherwise `nil`.
  public var connectionInfo: ConnectionInfo? {
    switch self {
    case .connected(let info), .reconnecting(let info):
      info
    case .disconnected, .connecting, .disconnecting:
      nil
    }
  }

  /// Whether a connection is being set up, is up, or is being shut down. `connect` only works
  /// while this is `false`.
  public var isActive: Bool {
    self != .disconnected
  }
}
