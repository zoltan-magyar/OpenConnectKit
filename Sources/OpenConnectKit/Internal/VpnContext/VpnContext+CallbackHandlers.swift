//
//  VpnContext+CallbackHandlers.swift
//  OpenConnectKit
//
//  OpenConnect C callback implementations
//

import COpenConnect
import Foundation

// MARK: - C Callback Result Codes

private enum AuthFormResult {
  static let ok: CInt = 0
  static let cancelled: CInt = 1
}

private enum CertResult {
  static let accept: CInt = 0
  static let reject: CInt = 1
}

// MARK: - C Callback Entry Points

// C callback for log messages. Called from C shim on mainloop thread.
@c(progressCallback)
internal func progressCallback(
  privdata: UnsafeMutableRawPointer?,
  level: CInt,
  formattedMessage: UnsafePointer<CChar>?
) {
  guard
    let privdata = privdata,
    let formattedMessage = formattedMessage
  else {
    return
  }

  let context = VpnContext.extractContext(from: privdata)

  var message = String(cString: formattedMessage)

  // Strip trailing newline
  if message.hasSuffix("\n") {
    message = String(message.dropLast())
  }

  // Convert C log level to Swift LogLevel
  let logLevel: LogLevel
  switch level {
  case 0: logLevel = .error
  case 1: logLevel = .info
  case 2: logLevel = .debug
  case 3: logLevel = .trace
  default: logLevel = .info
  }

  context.onLog?(logLevel, message)
}

/// C callback for certificate validation.
internal func validatePeerCertCallback(
  privdata: UnsafeMutableRawPointer?,
  reason: UnsafePointer<CChar>?
) -> CInt {
  guard let privdata = privdata else {
    return CertResult.reject
  }

  let context = VpnContext.extractContext(from: privdata)
  let certInfo = CertificateInfo(from: reason)

  if let onCert = context.onCert {
    return onCert(certInfo) ? CertResult.accept : CertResult.reject
  }

  // No callback set — fall back to configuration setting
  return context.configuration.allowInsecureCertificates ? CertResult.accept : CertResult.reject
}

/// C callback for authentication forms.
internal func processAuthFormCallback(
  privdata: UnsafeMutableRawPointer?,
  form: UnsafeMutablePointer<oc_auth_form>?
) -> CInt {
  guard
    let privdata = privdata,
    let form = form
  else {
    return AuthFormResult.cancelled
  }

  let context = VpnContext.extractContext(from: privdata)

  let authForm = AuthenticationForm(from: form)

  if let onAuth = context.onAuth {
    guard let filledForm = onAuth(authForm) else {
      return AuthFormResult.cancelled
    }
    filledForm.apply(to: form)
    return AuthFormResult.ok
  }

  // No callback set — return form unchanged (will likely fail auth)
  return AuthFormResult.ok
}

/// C callback when reconnection succeeds. Updates status to .connected.
internal func reconnectedCallback(privdata: UnsafeMutableRawPointer?) {
  guard let privdata = privdata else {
    return
  }

  let context = VpnContext.extractContext(from: privdata)
  context.updateStatus(.connected)
}

/// C callback for traffic statistics. Triggered by requestStats() command.
internal func statsCallback(
  privdata: UnsafeMutableRawPointer?,
  stats: UnsafePointer<oc_stats>?
) {
  guard
    let privdata = privdata,
    let stats = stats
  else {
    return
  }

  let context = VpnContext.extractContext(from: privdata)

  let vpnStats = VpnStats(
    txPackets: stats.pointee.tx_pkts,
    txBytes: stats.pointee.tx_bytes,
    rxPackets: stats.pointee.rx_pkts,
    rxBytes: stats.pointee.rx_bytes
  )

  context.onStats?(vpnStats)
}

// MARK: - Helper Methods

extension VpnContext {
  /// Extracts the VpnContext from a C callback privdata pointer.
  ///
  /// - Parameter privdata: The opaque pointer passed to C callbacks
  /// - Returns: The VpnContext instance
  static func extractContext(from privdata: UnsafeMutableRawPointer) -> VpnContext {
    return Unmanaged<VpnContext>.fromOpaque(privdata).takeUnretainedValue()
  }

  /// Finds the vpnc-script executable.
  ///
  /// Uses the configured path if set, otherwise searches common locations.
  ///
  /// - Returns: The path to the vpnc-script, or `nil` if not found
  internal func findVpncScript() -> String? {
    if let configuredPath = configuration.vpncScript {
      guard FileManager.default.isExecutableFile(atPath: configuredPath) else {
        return nil
      }
      return configuredPath
    }

    let commonPaths = [
      "/opt/homebrew/etc/vpnc/vpnc-script",
      "/usr/local/etc/vpnc-scripts/vpnc-script",
      "/usr/share/vpnc-scripts/vpnc-script",
      "/etc/vpnc/vpnc-script",
      "/usr/local/share/vpnc-scripts/vpnc-script",
    ]

    for path in commonPaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        return path
      }
    }

    return nil
  }
}
