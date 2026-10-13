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
// the lifecycle stream. They record the outcome, so a failure that follows can be reported for
// what it really was, and leave decisions to the delegate. The one exception is the certificate
// callback, which applies the delegate's earlier answers for the rest of the connection: it
// accepts a certificate the delegate already accepted for the same server, and after a rejection
// it rejects without asking and stops the connection.
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

  state.delegate?.didLog(text, level: LogLevel(openConnectLevel: level))
}

/// The server's certificate. Returns 0 to accept, 1 to reject.
///
/// openconnect calls it for every server certificate, because its own OpenSSL check is switched
/// off (see `OpenConnectContext.init`): on every new TLS connection, including each attempt to
/// re-establish a lost one. The delegate decides, with the system's verdict in
/// `CertificateInfo.systemTrust`. openconnect's `reason` is OpenSSL's, which without a CA store
/// always fails, so it isn't used.
///
/// The delegate's answers hold for the rest of the connection, like the accepted certificates in
/// openconnect's own command-line client (`validate_peer_cert()` in `main.c`). A certificate it
/// accepted is accepted again without asking when the same server presents it and the system's
/// verdict hasn't changed, so a reconnect doesn't wait for a prompt. Anything else is asked about:
/// another certificate, another server (one connection can use several, such as a GlobalProtect
/// portal and its gateway), or a changed verdict, such as a certificate that expired meanwhile.
///
/// A rejection ends the connection. While connecting, the failed TLS handshake fails the step
/// anyway, but during a reconnect it's only one failed attempt to openconnect, which would retry
/// (and call this again) until its reconnect timeout. So a rejection also sends a cancel command,
/// and after one, the delegate isn't asked again.
internal func validatePeerCertCallback(
  privdata: UnsafeMutableRawPointer?,
  reason: UnsafePointer<CChar>?
) -> CInt {
  guard let privdata = privdata else {
    return 1
  }

  let state = OpenConnectContext.CallbackState.from(privdata)

  // The delegate has already rejected a certificate, so the connection is ending; openconnect
  // just hasn't got there yet. For example, GlobalProtect, F5, Fortinet, oNCP and Array log off
  // over a new HTTPS connection after the mainloop. Another answer couldn't change the outcome.
  if state.isCertificateRejected {
    state.delegate?.didLog(
      "Rejecting the server's certificate: one was already rejected", level: .debug)
    return 1
  }

  guard let vpnInfo = state.vpnInfo else {
    return 1
  }

  // Read here: openconnect only guarantees the certificate is available inside this callback.
  let certInfo = CertificateInfo(vpnInfo: vpnInfo)
  switch certInfo.systemTrust {
  case .trusted:
    state.delegate?.didLog("The system trusts the server's certificate", level: .info)
  case .untrusted(let reason):
    state.delegate?.didLog(
      "The system doesn't trust the server's certificate: \(reason)", level: .info)
  }

  // The delegate already answered this question in this connection; openconnect has opened
  // another TLS connection to the same server: during the login (after the server closed the
  // last one), to re-establish a lost connection, or to log off. The last case also lets a
  // protocol log off after cancel(): by then VPNSession no longer asks its delegate and would
  // reject.
  if state.hasAccepted(certInfo) {
    state.delegate?.didLog(
      "Accepting the server's certificate: it was accepted earlier in this connection",
      level: .info)
    return 0
  }

  // Without a delegate there's nobody to accept it.
  guard state.delegate?.shouldAcceptCertificate(certInfo) == true else {
    // Recorded so the failure that follows reads as a rejected certificate.
    state.markCertificateRejected()
    // Stops a reconnect, which would otherwise keep retrying. A plain cancel command, not
    // OpenConnectContext.cancel(): that would mark the connection cancelled, and the failure
    // would read as a cancellation.
    state.send(.cancel)
    return 1
  }
  state.recordAccepted(certInfo)
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
    // Cancelled, or there's no delegate any more. Recorded so the failed cookie request reads as a
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
