//
//  VPNStats.swift
//  OpenConnectKit
//
//  VPN traffic statistics model
//

import Foundation

/// Traffic statistics for a VPN connection.
///
/// This structure contains information about data transferred through the VPN,
/// including both packet counts and byte counts for transmitted and received data.
///
/// Statistics are cumulative since the connection was established and persist
/// across reconnections during the same session.
///
/// `VPNSession` requests them every 5 seconds while connected and publishes them as its
/// observable `stats` property.
///
/// ## Example Usage
///
/// ```swift
/// if let stats = session.stats {
///     let sent = Int64(clamping: stats.txBytes).formatted(.byteCount(style: .binary))
///     Text("Sent: \(sent) in \(stats.txPackets) packets")
/// }
/// ```
public struct VPNStats: Hashable, Sendable {
  // MARK: - Properties

  /// Number of packets transmitted (sent) through the VPN.
  public let txPackets: UInt64

  /// Number of bytes transmitted (sent) through the VPN.
  public let txBytes: UInt64

  /// Number of packets received through the VPN.
  public let rxPackets: UInt64

  /// Number of bytes received through the VPN.
  public let rxBytes: UInt64

  // MARK: - Initialization

  /// Creates VPN statistics.
  ///
  /// - Parameters:
  ///   - txPackets: Number of transmitted packets
  ///   - txBytes: Number of transmitted bytes
  ///   - rxPackets: Number of received packets
  ///   - rxBytes: Number of received bytes
  public init(txPackets: UInt64, txBytes: UInt64, rxPackets: UInt64, rxBytes: UInt64) {
    self.txPackets = txPackets
    self.txBytes = txBytes
    self.rxPackets = rxPackets
    self.rxBytes = rxBytes
  }

  // MARK: - Computed Properties

  /// Total number of packets (sent + received).
  public var totalPackets: UInt64 {
    txPackets + rxPackets
  }

  /// Total number of bytes (sent + received).
  public var totalBytes: UInt64 {
    txBytes + rxBytes
  }
}
