//
//  SystemTrust.swift
//  OpenConnectKit
//
//  The system's verdict on a server certificate
//

import Foundation

/// Whether the system trusts a server certificate for the server's host name.
///
/// The session asks the system about every server certificate and reports the answer in
/// `CertificateInfo.systemTrust`; the delegate decides what to do with it. The system uses the
/// same trust settings as the rest of the Mac, including the user's own: a company root marked
/// "Always Trust" in Keychain Access counts, a root that's merely in the keychain doesn't.
public enum SystemTrust: Hashable, Sendable {
  /// The system trusts the certificate.
  case trusted

  /// The system doesn't trust the certificate, with its explanation, for example
  /// "“vpn.example.com” certificate is not trusted".
  case untrusted(reason: String)
}
