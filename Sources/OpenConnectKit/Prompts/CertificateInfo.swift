//
//  CertificateInfo.swift
//  OpenConnectKit
//
//  Certificate validation information
//

import Foundation

/// The server's certificate, and whether the system trusts it.
///
/// `VPNSessionDelegate.vpnSession(_:shouldAcceptCertificate:)` gets one for every server, and
/// uses it to decide whether to accept the certificate.
///
/// ## Example
///
/// ```swift
/// func vpnSession(
///     _ session: VPNSession,
///     shouldAcceptCertificate info: CertificateInfo
/// ) async -> Bool {
///     guard case .untrusted(let reason) = info.systemTrust else {
///         return true  // the system trusts it
///     }
///     if let pin = info.pin, trustedPins[info.hostname ?? ""] == pin {
///         return true  // accepted before, same certificate
///     }
///     return await askUserToTrust(info, because: reason)
/// }
/// ```
public struct CertificateInfo: Hashable, Sendable {
  // MARK: - Properties

  /// Whether the system trusts the certificate for the server's host name, and if not, why.
  public let systemTrust: SystemTrust

  /// The server's host name.
  public let hostname: String?

  /// The certificate's public-key pin in openconnect's format: `pin-sha256:` followed by a
  /// base64 SHA-256 hash. It's the value openconnect's `--servercert` option takes.
  ///
  /// This is the key for remembering a decision. Store it together with the host name, never on
  /// its own, and compare it with the next certificate's pin.
  public let pin: String?

  /// The certificate in DER encoding. `SecCertificateCreateWithData` turns it into a
  /// `SecCertificate`, for example to show it in the system's certificate view.
  public let derData: Data?

  /// The certificate's fields as text, formatted by openconnect.
  public let details: String?

  // MARK: - Initialization

  /// Creates certificate information. `VPNSession` creates these itself; this is for previews
  /// and tests.
  public init(
    systemTrust: SystemTrust, hostname: String? = nil, pin: String? = nil, derData: Data? = nil,
    details: String? = nil
  ) {
    self.systemTrust = systemTrust
    self.hostname = hostname
    self.pin = pin
    self.derData = derData
    self.details = details
  }
}
