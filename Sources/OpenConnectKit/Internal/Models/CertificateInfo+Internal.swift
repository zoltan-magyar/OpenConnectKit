//
//  CertificateInfo+Internal.swift
//  OpenConnectKit
//
//  Internal C interop extensions for CertificateInfo
//

import Foundation

extension CertificateInfo {
  // Create from C string pointer
  internal init(from cReason: UnsafePointer<CChar>?) {
    if let cReason = cReason {
      self.reason = String(cString: cReason)
    } else {
      self.reason = "Unknown certificate validation error"
    }
    self.hostname = nil
    self.rawData = nil
  }
}
