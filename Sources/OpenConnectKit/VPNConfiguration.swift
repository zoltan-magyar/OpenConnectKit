//
//  VPNConfiguration.swift
//  OpenConnectKit
//
//  Configuration for VPN sessions
//

import Foundation

/// Configuration for establishing a VPN connection.
///
/// Use this structure to specify the settings for a VPN connection: the server,
/// protocol, logging, tunnel and reconnection behaviour. Credentials and certificate
/// decisions come from the session's `VPNSessionDelegate` instead.
///
/// ## Example
///
/// ```swift
/// let config = VPNConfiguration(
///     serverURL: URL(string: "https://vpn.example.com")!,
///     vpnProtocol: .anyConnect,
///     logLevel: .info
/// )
/// ```
public struct VPNConfiguration: Hashable, Codable, Sendable {
  // MARK: - Properties

  /// The VPN server URL (e.g., `https://vpn.example.com`).
  public var serverURL: URL

  /// The VPN protocol to use.
  public var vpnProtocol: VPNProtocol

  /// Log level for VPN messages.
  public var logLevel: LogLevel

  // MARK: - TUN Device Configuration

  /// Path to a custom vpnc-script to use for network interface configuration.
  ///
  /// If `nil` (the default), the bundled vpnc-script is used automatically.
  /// Only set this if you need to override the bundled script with a custom one.
  ///
  /// The vpnc-script handles network configuration tasks such as:
  /// - Setting up routes
  /// - Configuring DNS
  /// - Setting up the network interface
  ///
  /// If you specify a path, ensure the script is executable.
  public var vpncScript: String?

  /// Name for the TUN/TAP network interface.
  ///
  /// If `nil`, the system will choose an available interface name automatically
  /// (e.g., `tun0`, `utun0`, etc.).
  ///
  /// Default is `nil` (auto-assign).
  public var interfaceName: String?

  // MARK: - Reconnection Configuration
  //
  // Possible next step: `Duration`'s built-in `Codable` format is a pair of numbers counting
  // attoseconds (120 s encodes as `[6, 9319535557742690304]`). It's stable but unreadable in a
  // saved profile; a custom `Codable` implementation could store these two as whole seconds.

  /// How long to keep trying to reconnect before giving up.
  ///
  /// If the VPN connection drops, OpenConnect will attempt to reconnect.
  /// This is the total time budget for those attempts, in whole seconds.
  ///
  /// Default is 300 seconds (5 minutes).
  public var reconnectTimeout: Duration

  /// The wait before the second reconnection attempt.
  ///
  /// After each failed attempt, OpenConnect waits a little longer: the wait grows by this
  /// value every time, up to 100 seconds (10 s, 20 s, 30 s, … with the default). Whole seconds.
  ///
  /// Default is 10 seconds.
  public var reconnectInterval: Duration

  // MARK: - Initialization

  /// Creates a VPN configuration.
  ///
  /// - Parameters:
  ///   - serverURL: The VPN server URL
  ///   - vpnProtocol: The VPN protocol (default: `.anyConnect`)
  ///   - logLevel: The log level (default: `.info`)
  ///   - vpncScript: Path to vpnc-script (default: `nil` for auto-detect)
  ///   - interfaceName: Network interface name (default: `nil` for auto-assign)
  ///   - reconnectTimeout: Timeout for reconnection attempts (default: 300 seconds)
  ///   - reconnectInterval: Interval between reconnection attempts (default: 10 seconds)
  public init(
    serverURL: URL,
    vpnProtocol: VPNProtocol = .anyConnect,
    logLevel: LogLevel = .info,
    vpncScript: String? = nil,
    interfaceName: String? = nil,
    reconnectTimeout: Duration = .seconds(300),
    reconnectInterval: Duration = .seconds(10)
  ) {
    self.serverURL = serverURL
    self.vpnProtocol = vpnProtocol
    self.logLevel = logLevel
    self.vpncScript = vpncScript
    self.interfaceName = interfaceName
    self.reconnectTimeout = reconnectTimeout
    self.reconnectInterval = reconnectInterval
  }
}

// MARK: - VPNProtocol

/// The VPN protocols openconnect supports. The raw values are openconnect's protocol names.
public enum VPNProtocol: String, Hashable, Codable, Sendable, CaseIterable, Identifiable {
  /// Cisco AnyConnect, and the open-source ocserv
  case anyConnect = "anyconnect"

  /// Palo Alto Networks GlobalProtect
  case globalProtect = "gp"

  /// Pulse Connect Secure (now Ivanti Connect Secure)
  case pulse = "pulse"

  /// Juniper Network Connect
  case juniper = "nc"

  /// F5 BIG-IP SSL VPN
  case f5 = "f5"

  /// Fortinet SSL VPN
  case fortinet = "fortinet"

  /// Array Networks SSL VPN
  case array = "array"

  public var id: Self { self }

  /// The protocol's name as openconnect shows it, for example
  /// "Palo Alto Networks GlobalProtect".
  public var displayName: String {
    switch self {
    case .anyConnect: "Cisco AnyConnect or OpenConnect"
    case .globalProtect: "Palo Alto Networks GlobalProtect"
    case .pulse: "Pulse Connect Secure"
    case .juniper: "Juniper Network Connect"
    case .f5: "F5 BIG-IP SSL VPN"
    case .fortinet: "Fortinet SSL VPN"
    case .array: "Array SSL VPN"
    }
  }
}
