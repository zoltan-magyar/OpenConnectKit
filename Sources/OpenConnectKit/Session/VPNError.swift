//
//  VPNError.swift
//  OpenConnectKit
//
//  Error types for VPN operations
//

import Foundation

/// Errors that can occur during VPN operations.
///
/// Where openconnect explains a failure, `reason` is its own last error message for that step,
/// for example "Failed to connect to host vpn.example.com". These are the messages openconnect's
/// command-line client shows; the full detail is in `VPNSession.logs`.
public enum VPNError: Error, Hashable, Sendable {
  /// `connect` was called while a connection was being set up, was up, or was being shut down.
  case alreadyActive

  /// The configuration can't be used, for example because the server URL is invalid.
  case invalidConfiguration(reason: String)

  /// The connection attempt was cancelled: by `disconnect()`, by cancelling the task that
  /// called `connect`, or by answering an authentication prompt with `nil`.
  case cancelled

  /// The server's certificate was rejected.
  case certificateRejected

  /// Reaching the server or logging in failed: the server was unreachable, the TLS connection
  /// failed, or the login was refused.
  case authenticationFailed(reason: String)

  /// The login succeeded, but the tunnel to the server couldn't be established.
  case tunnelFailed(reason: String)

  /// The local network interface couldn't be configured.
  case networkConfigurationFailed(reason: String)

  /// The server ended the session, or the session expired.
  case sessionEnded

  /// The connection was lost and couldn't be re-established within the configured
  /// reconnect timeout.
  case connectionLost(reason: String)

  /// openconnect couldn't be set up. Not expected to happen in practice.
  case internalError(reason: String)
}

// MARK: - LocalizedError

extension VPNError: LocalizedError {
  /// A localized message describing what error occurred.
  public var errorDescription: String? {
    switch self {
    case .alreadyActive:
      return "A VPN connection is already active"
    case .invalidConfiguration(let reason):
      return "Invalid configuration: \(reason)"
    case .cancelled:
      return "The connection was cancelled"
    case .certificateRejected:
      return "The server's certificate was rejected"
    case .authenticationFailed(let reason):
      return "Authentication failed: \(reason)"
    case .tunnelFailed(let reason):
      return "Could not establish the VPN tunnel: \(reason)"
    case .networkConfigurationFailed(let reason):
      return "Could not configure the network: \(reason)"
    case .sessionEnded:
      return "The VPN session expired or was ended by the server"
    case .connectionLost(let reason):
      return "Connection lost: \(reason)"
    case .internalError(let reason):
      return "Internal error: \(reason)"
    }
  }
}
