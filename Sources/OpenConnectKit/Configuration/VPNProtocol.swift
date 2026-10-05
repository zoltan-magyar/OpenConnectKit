//
//  VPNProtocol.swift
//  OpenConnectKit
//
//  The VPN protocols openconnect supports
//

import Foundation

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
