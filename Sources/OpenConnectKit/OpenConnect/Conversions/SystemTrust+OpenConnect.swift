//
//  SystemTrust+OpenConnect.swift
//  OpenConnectKit
//
//  Asking the system about the certificate chain openconnect received
//

import COpenConnect
import Foundation
import Security

extension SystemTrust {
  /// Evaluates the certificates the server presented against the host name from the server URL,
  /// with the system's trust settings.
  ///
  /// Only valid inside openconnect's certificate callback, on the connection thread: openconnect
  /// only hands out the chain there. It blocks while the system fetches missing intermediates or
  /// revocation information, which is fine on the connection thread and why it must never run
  /// on the main actor.
  internal init(vpnInfo: OpaquePointer) {
    guard let hostname = openconnect_get_dnsname(vpnInfo).map({ String(cString: $0) }) else {
      self = .untrusted(reason: "There is no host name to check the certificate against")
      return
    }
    let certificates = Self.peerCertificates(vpnInfo)
    guard !certificates.isEmpty else {
      self = .untrusted(reason: "The server's certificate couldn't be read")
      return
    }

    var trust: SecTrust?
    let policy = SecPolicyCreateSSL(true, hostname as CFString)
    guard
      SecTrustCreateWithCertificates(certificates as CFArray, policy, &trust) == errSecSuccess,
      let trust
    else {
      self = .untrusted(reason: "The server's certificate couldn't be evaluated")
      return
    }

    var error: CFError?
    if SecTrustEvaluateWithError(trust, &error) {
      self = .trusted
    } else {
      self = .untrusted(
        reason: error.map { CFErrorCopyDescription($0) as String }
          ?? "The server's certificate isn't trusted")
    }
  }

  /// The certificates the server sent, leaf first.
  private static func peerCertificates(_ vpnInfo: OpaquePointer) -> [SecCertificate] {
    var chain: UnsafeMutablePointer<oc_cert>?
    let count = openconnect_get_peer_cert_chain(vpnInfo, &chain)
    guard count > 0, let chain else { return [] }
    // openconnect's OpenSSL backend frees only the array here, not each certificate's DER
    // buffer: it counts them in a field that only its GnuTLS backend sets. That leaks a few
    // kilobytes once per connection. Freeing the buffers ourselves would double-free them once
    // openconnect is fixed.
    defer { openconnect_free_peer_cert_chain(vpnInfo, chain) }

    return (0..<Int(count)).compactMap { index in
      let certificate = chain[index]
      guard let derBytes = certificate.der_data, certificate.der_len > 0 else { return nil }
      let derData = Data(bytes: derBytes, count: Int(certificate.der_len))
      return SecCertificateCreateWithData(nil, derData as CFData)
    }
  }
}
