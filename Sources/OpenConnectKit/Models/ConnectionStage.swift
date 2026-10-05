//
//  ConnectionStage.swift
//  OpenConnectKit
//
//  The steps of setting up a VPN connection
//

import Foundation

/// A step in setting up a VPN connection. The cases are in the order they happen.
public enum ConnectionStage: Hashable, Sendable, CaseIterable {
  /// Contacting the server, checking its certificate and logging in. Authentication and
  /// certificate prompts happen during this step.
  case authenticating

  /// Opening the tunnel to the server (CSTP, over TLS).
  case establishingTunnel

  /// Setting up the faster UDP data channel (DTLS). If the server doesn't offer it, the
  /// connection carries on over the TLS tunnel.
  case settingUpDTLS

  /// Configuring the local network interface, routes and DNS.
  case configuringNetwork
}
