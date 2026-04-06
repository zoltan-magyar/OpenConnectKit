//
//  ConnectionStatus.swift
//  OpenConnectKit
//
//  Connection status types for VPN sessions
//

import Foundation

/// Represents the current status of a VPN connection.
///
/// This enum provides a type-safe way to track the connection lifecycle,
/// including any errors that caused disconnection and progress messages
/// during connection establishment.
///
/// ## Example Usage
///
/// ```swift
/// switch session.connectionStatus {
/// case .disconnected(let error):
///     if let error = error {
///         print("Disconnected due to error: \(error)")
///     } else {
///         print("Disconnected normally")
///     }
/// case .connecting(let stage):
///     print("Connecting: \(stage)")
/// case .connected:
///     print("Connected successfully")
/// case .reconnecting:
///     print("Attempting to reconnect...")
/// }
/// ```
public enum ConnectionStatus: Equatable, Sendable {
  /// The VPN is disconnected.
  ///
  /// The associated `VpnError` indicates why the disconnection occurred:
  /// - `nil` - User initiated disconnect or normal disconnection
  /// - Non-nil - Connection failed or was interrupted due to an error
  ///
  /// - Parameter error: Optional error that caused the disconnection
  case disconnected(error: VpnError?)

  /// The VPN is in the process of connecting.
  ///
  /// The associated string provides details about the current connection stage,
  /// such as:
  /// - "Authenticating..."
  /// - "Establishing CSTP connection"
  /// - "Setting up DTLS"
  /// - "Configuring tunnel"
  ///
  /// This allows for flexible progress reporting without requiring a fixed
  /// set of connection stages.
  ///
  /// - Parameter stage: Human-readable description of the current connection stage
  case connecting(stage: String)

  /// The VPN is fully connected and the mainloop is running.
  ///
  /// In this state, traffic is being routed through the VPN tunnel and
  /// the connection is actively maintained.
  case connected

  /// The VPN is in the process of disconnecting.
  ///
  /// A cancel command has been sent to the mainloop but it hasn't exited yet.
  /// Cleanup and resource release happen after the mainloop returns, at which
  /// point the status transitions to `.disconnected`.
  case disconnecting

  /// The VPN is attempting to reconnect after a connection loss.
  ///
  /// This state indicates that the connection was lost (e.g., due to network
  /// interruption) and OpenConnect is automatically attempting to re-establish
  /// the connection. This is different from the initial connection process.
  case reconnecting

}

// MARK: - Equatable Conformance

extension ConnectionStatus {
  public static func == (lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
    switch (lhs, rhs) {
    case (.disconnected(let lhsError), .disconnected(let rhsError)):
      // Compare errors by their localized description since VpnError doesn't conform to Equatable
      return lhsError?.localizedDescription == rhsError?.localizedDescription
    case (.connecting(let lhsStage), .connecting(let rhsStage)):
      return lhsStage == rhsStage
    case (.connected, .connected):
      return true
    case (.disconnecting, .disconnecting):
      return true
    case (.reconnecting, .reconnecting):
      return true
    default:
      return false
    }
  }
}
