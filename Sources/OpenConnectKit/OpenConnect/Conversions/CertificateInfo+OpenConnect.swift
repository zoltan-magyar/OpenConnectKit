//
//  CertificateInfo+OpenConnect.swift
//  OpenConnectKit
//
//  Building CertificateInfo from openconnect's peer certificate
//

import COpenConnect
import Foundation

extension CertificateInfo {
  /// Collects the server certificate's details and the system's verdict on it.
  ///
  /// Only valid inside openconnect's certificate callback, on the connection thread: that's
  /// where openconnect guarantees the certificate is available. Blocks while the system
  /// evaluates the chain.
  internal init(vpnInfo: OpaquePointer) {
    // Both buffers are allocated by openconnect and must be freed with
    // openconnect_free_cert_info().
    var derData: Data?
    var derBuffer: UnsafeMutablePointer<UInt8>?
    let derLength = openconnect_get_peer_cert_DER(vpnInfo, &derBuffer)
    if let derBuffer {
      if derLength > 0 {
        derData = Data(bytes: derBuffer, count: Int(derLength))
      }
      openconnect_free_cert_info(vpnInfo, derBuffer)
    }

    var details: String?
    if let detailsBuffer = openconnect_get_peer_cert_details(vpnInfo) {
      details = String(cString: detailsBuffer)
      openconnect_free_cert_info(vpnInfo, detailsBuffer)
    }

    self.init(
      systemTrust: SystemTrust(vpnInfo: vpnInfo),
      hostname: openconnect_get_dnsname(vpnInfo).map { String(cString: $0) },
      // Owned by openconnect, valid while the connection lasts; copied here.
      pin: openconnect_get_peer_cert_hash(vpnInfo).map { String(cString: $0) },
      derData: derData,
      details: details
    )
  }
}
