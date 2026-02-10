//
//  VpnConfiguration.swift
//  OpenConnectKit
//
//  Configuration for VPN sessions
//

import Foundation

/// Configuration for establishing a VPN connection.
///
/// Use this structure to specify all settings for a VPN session, including
/// server details, protocol, credentials, and security preferences.
///
/// ## Example
///
/// ```swift
/// let config = VpnConfiguration(
///     serverURL: URL(string: "https://vpn.example.com")!,
///     vpnProtocol: .anyConnect,
///     logLevel: .info
/// )
/// ```
public struct VpnConfiguration: Sendable {
  // MARK: - Properties

  /// The VPN server URL (e.g., `https://vpn.example.com`).
  public var serverURL: URL

  /// The VPN protocol to use.
  public var vpnProtocol: VpnProtocol

  /// Log level for VPN messages.
  public var logLevel: LogLevel

  /// Whether to allow connections with invalid or self-signed certificates.
  ///
  /// Default is `false` (reject invalid certificates).
  /// Set to `true` only for testing or when you trust the server.
  public var allowInsecureCertificates: Bool

  // MARK: - TUN Device Configuration

  /// Path to the vpnc-script used to configure the network interface.
  ///
  /// If `nil`, the library will automatically search for vpnc-script in standard locations:
  /// - macOS Homebrew: `/opt/homebrew/etc/vpnc-scripts/vpnc-script` or `/usr/local/etc/vpnc-scripts/vpnc-script`
  /// - Linux: `/usr/share/vpnc-scripts/vpnc-script` or `/etc/vpnc/vpnc-script`
  ///
  /// The vpnc-script handles network configuration tasks such as:
  /// - Setting up routes
  /// - Configuring DNS
  /// - Setting up the network interface
  ///
  /// If you specify a path, ensure the script is executable. The connection will fail
  /// if no valid script can be found.
  ///
  /// Default is `nil` (auto-detect from standard locations).
  public var vpncScript: String?

  /// Name for the TUN/TAP network interface.
  ///
  /// If `nil`, the system will choose an available interface name automatically
  /// (e.g., `tun0`, `utun0`, etc.).
  ///
  /// Default is `nil` (auto-assign).
  public var interfaceName: String?

  // MARK: - Reconnection Configuration

  /// Timeout in seconds before giving up on reconnection attempts.
  ///
  /// If the VPN connection drops, OpenConnect will attempt to reconnect.
  /// This value specifies how long to keep trying before giving up.
  ///
  /// Valid range: 10-100 seconds (enforced by OpenConnect)
  /// Default is `300` seconds (5 minutes).
  public var reconnectTimeout: Int32

  /// Interval in seconds between reconnection attempts.
  ///
  /// When the connection drops, OpenConnect will wait this long between
  /// each reconnection attempt.
  ///
  /// Valid range: 10-100 seconds (enforced by OpenConnect)
  /// Default is `10` seconds.
  public var reconnectInterval: Int32

  // MARK: - Initialization

  /// Creates a VPN configuration.
  ///
  /// - Parameters:
  ///   - serverURL: The VPN server URL
  ///   - vpnProtocol: The VPN protocol (default: `.anyConnect`)
  ///   - logLevel: The log level (default: `.info`)
  ///   - allowInsecureCertificates: Whether to allow invalid certificates (default: `false`)
  ///   - vpncScript: Path to vpnc-script (default: `nil` for auto-detect)
  ///   - interfaceName: Network interface name (default: `nil` for auto-assign)
  ///   - reconnectTimeout: Timeout for reconnection attempts (default: `300` seconds)
  ///   - reconnectInterval: Interval between reconnection attempts (default: `10` seconds)
  public init(
    serverURL: URL,
    vpnProtocol: VpnProtocol = .anyConnect,
    logLevel: LogLevel = .info,
    allowInsecureCertificates: Bool = false,
    vpncScript: String? = nil,
    interfaceName: String? = nil,
    reconnectTimeout: Int32 = 300,
    reconnectInterval: Int32 = 10
  ) {
    self.serverURL = serverURL
    self.vpnProtocol = vpnProtocol
    self.logLevel = logLevel
    self.allowInsecureCertificates = allowInsecureCertificates
    self.vpncScript = vpncScript
    self.interfaceName = interfaceName
    self.reconnectTimeout = reconnectTimeout
    self.reconnectInterval = reconnectInterval
  }
}

// MARK: - VpnProtocol

/// Supported VPN protocols.
public enum VpnProtocol: String, Sendable, CaseIterable {
  /// Cisco AnyConnect
  case anyConnect = "anyconnect"

  /// Palo Alto Networks GlobalProtect
  case globalProtect = "gp"

  /// Pulse Secure
  case pulse = "pulse"

  /// Juniper Network Connect
  case nc = "nc"

  /// Array Networks SSL VPN
  case array = "array"
}
