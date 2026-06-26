//
//  VpnContext+CallbackHandlers.swift
//  OpenConnectKit
//
//  OpenConnect C callback implementations
//

import COpenConnect
import Foundation

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

/// C callback for certificate validation. Returns 0 to accept, 1 to reject.
internal func validatePeerCertCallback(
  privdata: UnsafeMutableRawPointer?,
  reason: UnsafePointer<CChar>?
) -> CInt {
  guard let privdata = privdata else {
    return 1
  }

  let context = VpnContext.extractContext(from: privdata)
  let certInfo = CertificateInfo(from: reason)

  if let onCert = context.onCert {
    return onCert(certInfo) ? 0 : 1
  }

  // No callback set — fall back to configuration setting
  return context.configuration.allowInsecureCertificates ? 0 : 1
}

/// C callback for authentication forms. Returns 0 for success, 1 for failure.
internal func processAuthFormCallback(
  privdata: UnsafeMutableRawPointer?,
  form: UnsafeMutablePointer<oc_auth_form>?
) -> CInt {
  guard
    let privdata = privdata,
    let form = form
  else {
    return 1
  }

  let context = VpnContext.extractContext(from: privdata)

  let authForm = AuthenticationForm(from: form)

  if let onAuth = context.onAuth {
    guard let filledForm = onAuth(authForm) else {
      return 1  // nil = user cancelled
    }
    filledForm.apply(to: form)
    return 0
  }

  return 1  // No callback set — cancel auth
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
  /// Uses the configured path if explicitly set, otherwise uses the bundled script.
  ///
  /// - Returns: The path to the vpnc-script, or `nil` if not found
  internal func findVpncScript() -> String? {
    if let configuredPath = configuration.vpncScript {
      guard FileManager.default.isExecutableFile(atPath: configuredPath) else {
        return nil
      }
      return configuredPath
    }

    return bundledVpncScriptPath()
  }

  private func bundledVpncScriptPath() -> String? {
    guard let url = Bundle.module.url(forResource: "vpnc-script", withExtension: nil),
      FileManager.default.isExecutableFile(atPath: url.path)
    else {
      return nil
    }
    return url.path
  }
}
