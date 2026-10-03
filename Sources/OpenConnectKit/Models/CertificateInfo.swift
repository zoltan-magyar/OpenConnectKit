//
//  CertificateInfo.swift
//  OpenConnectKit
//
//  Certificate validation information
//

import Foundation

/// Information about a server certificate that needs validation.
///
/// This structure contains details about a certificate presented by the VPN server
/// that requires validation. Use it in
/// `VPNSessionDelegate.vpnSession(_:shouldAcceptCertificate:)` to decide whether to accept
/// or reject the certificate.
///
/// ## Example
///
/// ```swift
/// func vpnSession(
///     _ session: VPNSession,
///     shouldAcceptCertificate info: CertificateInfo
/// ) async -> Bool {
///     print("Certificate issue: \(info.reason)")
///     return await askUserToTrust(info)
/// }
/// ```
public struct CertificateInfo: Sendable {
  // MARK: - Properties

  /// The validation failure reason provided by OpenConnect.
  ///
  /// This describes why the certificate failed validation (e.g., expired,
  /// self-signed, hostname mismatch).
  public let reason: String

  /// The server hostname, if available.
  public let hostname: String?

  /// Raw certificate data, if available.
  public let rawData: Data?

  // MARK: - Initialization

  /// Creates certificate information.
  ///
  /// - Parameters:
  ///   - reason: The validation failure reason
  ///   - hostname: The server hostname (optional)
  ///   - rawData: Raw certificate data (optional)
  public init(reason: String, hostname: String? = nil, rawData: Data? = nil) {
    self.reason = reason
    self.hostname = hostname
    self.rawData = rawData
  }
}
