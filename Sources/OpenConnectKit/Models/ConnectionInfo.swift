//
//  ConnectionInfo.swift
//  OpenConnectKit
//
//  Details of an established VPN connection
//

import Foundation

/// Details of an established VPN connection.
public struct ConnectionInfo: Hashable, Sendable {
  /// The tunnel's network interface, for example `utun5`.
  public let interfaceName: String?

  /// The host name of the server the connection was made to. This can differ from the host in
  /// the configured server URL if the server redirected the client.
  public let serverName: String?

  /// The IP address of that server, in the form a URL would use (IPv6 addresses in brackets).
  /// Behind a proxy, openconnect reports the host name here instead.
  public let serverAddress: String?

  /// When the connection was established.
  public let connectedAt: Date

  /// Creates connection details. Useful for previews and tests; `VPNSession` creates these
  /// itself.
  public init(
    interfaceName: String?, serverName: String?, serverAddress: String?, connectedAt: Date
  ) {
    self.interfaceName = interfaceName
    self.serverName = serverName
    self.serverAddress = serverAddress
    self.connectedAt = connectedAt
  }
}
