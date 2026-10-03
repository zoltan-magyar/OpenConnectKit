//
//  VPNContext+CallbackHandlers.swift
//  OpenConnectKit
//
//  OpenConnect C callback implementations
//

import COpenConnect
import Foundation

// MARK: - C Callback Entry Points
//
// openconnect calls all of these on the connection thread, with the VPNContext.Callbacks object
// passed to openconnect_vpninfo_new() as privdata.

/// C callback for log messages, already formatted by the library.
/// Registered with `openconnect_set_progress_msg_handler()`.
internal func progressCallback(
  privdata: UnsafeMutableRawPointer?,
  level: CInt,
  message: UnsafePointer<CChar>?
) {
  guard
    let privdata = privdata,
    let message = message
  else {
    return
  }

  let callbacks = VPNContext.Callbacks.from(privdata)

  var text = String(cString: message)

  // Strip trailing newline
  if text.hasSuffix("\n") {
    text = String(text.dropLast())
  }

  // Remembered so a failing step can say why it failed (see VPNContext.errorMessage(or:)).
  if level == PRG_ERR {
    callbacks.recordErrorMessage(text)
  }

  callbacks.log(LogLevel(openConnectLevel: level), text)
}

/// C callback for certificate validation. Returns 0 to accept, 1 to reject.
internal func validatePeerCertCallback(
  privdata: UnsafeMutableRawPointer?,
  reason: UnsafePointer<CChar>?
) -> CInt {
  guard let privdata = privdata else {
    return 1
  }

  let callbacks = VPNContext.Callbacks.from(privdata)
  // Read the certificate here: openconnect only guarantees it's available inside this callback.
  let certInfo = CertificateInfo(reason: reason, vpnInfo: callbacks.vpnInfo)

  guard callbacks.validateCertificate(certInfo) else {
    // Recorded so the failure that follows reads as a rejected certificate.
    callbacks.markCertificateRejected()
    return 1
  }
  return 0
}

/// C callback for authentication forms. Returns an `OC_FORM_RESULT_*` code.
internal func processAuthFormCallback(
  privdata: UnsafeMutableRawPointer?,
  form: UnsafeMutablePointer<oc_auth_form>?
) -> CInt {
  guard
    let privdata = privdata,
    let form = form
  else {
    return OC_FORM_RESULT_ERR
  }

  let callbacks = VPNContext.Callbacks.from(privdata)

  let authForm = AuthenticationForm(from: form)

  guard let filledForm = callbacks.authenticate(authForm) else {
    // nil = user cancelled. Recorded so the failed cookie request reads as a cancellation.
    callbacks.markCancelled()
    return OC_FORM_RESULT_CANCELLED
  }
  return filledForm.apply(to: form)
}

/// C callback when reconnection succeeds.
internal func reconnectedCallback(privdata: UnsafeMutableRawPointer?) {
  guard let privdata = privdata else {
    return
  }

  VPNContext.Callbacks.from(privdata).report(.reconnected)
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

  let vpnStats = VPNStats(
    txPackets: stats.pointee.tx_pkts,
    txBytes: stats.pointee.tx_bytes,
    rxPackets: stats.pointee.rx_pkts,
    rxBytes: stats.pointee.rx_bytes
  )

  VPNContext.Callbacks.from(privdata).stats(vpnStats)
}

// MARK: - Helper Methods

extension VPNContext {
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
