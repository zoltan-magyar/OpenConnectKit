//
//  VpnStats.swift
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
/// ## Example Usage
///
/// ```swift
/// session.onStats = { stats in
///     print("Sent: \(stats.txBytes) bytes (\(stats.txPackets) packets)")
///     print("Received: \(stats.rxBytes) bytes (\(stats.rxPackets) packets)")
/// }
///
/// // Request statistics
/// session.requestStats()
/// ```
public struct VpnStats: Sendable {
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
    return txPackets + rxPackets
  }

  /// Total number of bytes (sent + received).
  public var totalBytes: UInt64 {
    return txBytes + rxBytes
  }

  // MARK: - Formatting Helpers

  /// Returns a human-readable string representation of bytes (e.g., "1.5 MB").
  ///
  /// - Parameter bytes: The number of bytes to format
  /// - Returns: A formatted string with appropriate unit
  public static func formatBytes(_ bytes: UInt64) -> String {
    let kb: Double = 1024
    let mb: Double = kb * 1024
    let gb: Double = mb * 1024

    let value = Double(bytes)

    if value >= gb {
      return String(format: "%.2f GB", value / gb)
    } else if value >= mb {
      return String(format: "%.2f MB", value / mb)
    } else if value >= kb {
      return String(format: "%.2f KB", value / kb)
    } else {
      return "\(bytes) bytes"
    }
  }

  /// Returns a human-readable string representation of transmitted bytes.
  public var formattedTxBytes: String {
    return VpnStats.formatBytes(txBytes)
  }

  /// Returns a human-readable string representation of received bytes.
  public var formattedRxBytes: String {
    return VpnStats.formatBytes(rxBytes)
  }

  /// Returns a human-readable string representation of total bytes.
  public var formattedTotalBytes: String {
    return VpnStats.formatBytes(totalBytes)
  }
}

// MARK: - CustomStringConvertible

extension VpnStats: CustomStringConvertible {
  /// A textual representation of the VPN statistics.
  public var description: String {
    return """
      VPN Statistics:
        TX: \(formattedTxBytes) (\(txPackets) packets)
        RX: \(formattedRxBytes) (\(rxPackets) packets)
        Total: \(formattedTotalBytes) (\(totalPackets) packets)
      """
  }
}

// MARK: - Equatable

extension VpnStats: Equatable {
  public static func == (lhs: VpnStats, rhs: VpnStats) -> Bool {
    return lhs.txPackets == rhs.txPackets && lhs.txBytes == rhs.txBytes
      && lhs.rxPackets == rhs.rxPackets && lhs.rxBytes == rhs.rxBytes
  }
}
