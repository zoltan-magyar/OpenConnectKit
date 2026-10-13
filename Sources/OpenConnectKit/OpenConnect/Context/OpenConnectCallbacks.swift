//
//  OpenConnectCallbacks.swift
//  OpenConnectKit
//
//  The C functions openconnect calls back
//

import COpenConnect
import Foundation

// openconnect calls all of these on the connection thread. Their `privdata` is the context's
// CallbackState, passed to openconnect_vpninfo_new(). Each one turns C data into Swift values and
// passes them on: questions to the context's delegate (OpenConnectContextDelegate), progress to
// the lifecycle stream. None of them decides anything; they only record the outcome, so a failure
// that follows can be reported for what it really was.
//
// They're free functions passed to openconnect as Swift function pointers; C never calls them by
// name. "Callback" in this module means one of these.

/// Log messages, already formatted by openconnect.
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

  let state = OpenConnectContext.CallbackState.from(privdata)

  var text = String(cString: message)

  // Strip trailing newline
  if text.hasSuffix("\n") {
    text = String(text.dropLast())
  }

  // Remembered so a failing step can say why it failed (see OpenConnectContext.errorMessage(or:)).
  if level == PRG_ERR {
    state.recordErrorMessage(text)
  }

  state.log(LogLevel(openConnectLevel: level), text)
}

/// The server's certificate. Returns 0 to accept, 1 to reject.
///
/// openconnect calls it for every server certificate, because its own OpenSSL check is switched
/// off (see `OpenConnectContext.init`). The delegate decides, with the system's verdict in
/// `CertificateInfo.systemTrust`. openconnect's `reason` is OpenSSL's, which without a CA store
/// always fails, so it isn't used.
internal func validatePeerCertCallback(
  privdata: UnsafeMutableRawPointer?,
  reason: UnsafePointer<CChar>?
) -> CInt {
  guard let privdata = privdata else {
    return 1
  }

  let state = OpenConnectContext.CallbackState.from(privdata)
  guard let vpnInfo = state.vpnInfo else {
    return 1
  }

  // Read here: openconnect only guarantees the certificate is available inside this callback.
  let certInfo = CertificateInfo(vpnInfo: vpnInfo)
  switch certInfo.systemTrust {
  case .trusted:
    state.log(.info, "The system trusts the server's certificate")
  case .untrusted(let reason):
    state.log(.info, "The system doesn't trust the server's certificate: \(reason)")
  }

  // Without an owner there's nobody to accept it.
  guard state.delegate?.shouldAcceptCertificate(certInfo) == true else {
    // Recorded so the failure that follows reads as a rejected certificate.
    state.markCertificateRejected()
    return 1
  }
  return 0
}

/// A login form. Returns an `OC_FORM_RESULT_*` code.
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

  let state = OpenConnectContext.CallbackState.from(privdata)

  let authForm = AuthenticationForm(from: form)

  guard let filledForm = state.delegate?.requiresAuthentication(authForm) else {
    // Cancelled, or there's no owner any more. Recorded so the failed cookie request reads as a
    // cancellation.
    state.markCancelled()
    return OC_FORM_RESULT_CANCELLED
  }
  return filledForm.apply(to: form)
}

/// Before each attempt to re-establish a lost connection.
/// Registered with `openconnect_set_reconnecting_handler()`.
internal func reconnectingCallback(privdata: UnsafeMutableRawPointer?) {
  guard let privdata = privdata else {
    return
  }

  OpenConnectContext.CallbackState.from(privdata).report(.reconnecting)
}

/// When an attempt to re-establish the connection succeeded.
internal func reconnectedCallback(privdata: UnsafeMutableRawPointer?) {
  guard let privdata = privdata else {
    return
  }

  OpenConnectContext.CallbackState.from(privdata).report(.reconnected)
}

/// Traffic statistics, in reply to `OpenConnectContext.requestStats()`.
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

  OpenConnectContext.CallbackState.from(privdata).delegate?.didReceive(vpnStats)
}
