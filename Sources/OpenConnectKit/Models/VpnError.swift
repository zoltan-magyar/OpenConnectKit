//
//  VpnError.swift
//  OpenConnectKit
//
//  Error types for VPN operations
//

import Foundation

/// Errors that can occur during VPN operations.
public enum VpnError: Error, Sendable {
  /// Failed to connect to the VPN server.
  ///
  /// - Parameter reason: A description of why the connection failed
  case connectionFailed(reason: String)

  /// Authentication failed.
  ///
  /// - Parameter reason: A description of the authentication failure
  case authenticationFailed(reason: String)

  /// Invalid configuration provided.
  ///
  /// - Parameter reason: A description of the configuration issue
  case invalidConfiguration(reason: String)

  /// Failed to obtain authentication cookie from the server.
  case cookieObtainFailed

  /// Failed to establish CSTP (Control and Provisioning of Wireless Access Points) connection.
  case cstpConnectionFailed

  /// Failed to setup DTLS (Datagram Transport Layer Security).
  case dtlsSetupFailed

  /// Certificate validation failed.
  ///
  /// - Parameter reason: A description of the validation failure
  case certificateValidationFailed(reason: String)

  /// VPN context not initialized.
  case notInitialized

  /// Operation cancelled by user.
  case cancelled

  /// Failed to setup command pipe for controlling the VPN connection.
  case cmdPipeSetupFailed

  /// Failed to setup TUN device.
  case tunSetupFailed

  /// Failed to find or execute vpnc-script.
  case vpncScriptFailed

  /// VPN is already connected.
  case alreadyConnected
}

// MARK: - LocalizedError

extension VpnError: LocalizedError {
  /// A localized message describing what error occurred.
  public var errorDescription: String? {
    switch self {
    case .connectionFailed(let reason):
      return "Connection failed: \(reason)"
    case .authenticationFailed(let reason):
      return "Authentication failed: \(reason)"
    case .invalidConfiguration(let reason):
      return "Invalid configuration: \(reason)"
    case .cookieObtainFailed:
      return "Failed to obtain authentication cookie"
    case .cstpConnectionFailed:
      return "Failed to establish CSTP connection"
    case .dtlsSetupFailed:
      return "Failed to setup DTLS"
    case .certificateValidationFailed(let reason):
      return "Certificate validation failed: \(reason)"
    case .notInitialized:
      return "VPN context not initialized"
    case .cancelled:
      return "Operation cancelled"
    case .cmdPipeSetupFailed:
      return "Failed to setup command pipe for VPN control"
    case .tunSetupFailed:
      return "Failed to setup TUN device for VPN tunnel"
    case .vpncScriptFailed:
      return "Failed to find or execute vpnc-script"
    case .alreadyConnected:
      return "VPN is already connected"
    }
  }
}
