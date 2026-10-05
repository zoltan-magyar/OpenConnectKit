//
//  VPNContext+Callbacks.swift
//  OpenConnectKit
//
//  How the connection thread reports back: the owner's Callbacks object, and the C callbacks
//  that reach it
//

import COpenConnect
import Foundation
import Synchronization

// MARK: - Callbacks

extension VPNContext {
  /// How the context reaches its owner. The owner creates it; the C callbacks reach it through
  /// their `privdata` pointer. Everything here is called on the connection thread.
  ///
  /// It's a separate object so it can exist before `openconnect_vpninfo_new()` is called,
  /// which needs the pointer; that is what lets `vpnInfo` be a `let`. It has to be a class,
  /// because C holds on to its address. VPNContext keeps it alive for as long as `vpnInfo`
  /// exists.
  internal final class Callbacks: Sendable {
    /// Blocks until the form is filled in. Returning `nil` cancels the connection.
    internal let authenticate: @Sendable (AuthenticationForm) -> AuthenticationForm?

    /// Blocks until a decision is made. Returning `true` accepts the certificate.
    internal let validateCertificate: @Sendable (CertificateInfo) -> Bool

    /// Receives every log message. Called often, so it shouldn't block.
    internal let log: @Sendable (LogLevel, String) -> Void

    /// Receives traffic statistics, in reply to `requestStats()`.
    ///
    /// Not ordered with `lifecycle`: a reply can still come in after `.finished` has been
    /// reported, and the owner has to ignore it then.
    internal let stats: @Sendable (VPNStats) -> Void

    /// The owner reads the connection's progress from this. Finishes after `.finished`.
    internal let lifecycle: AsyncStream<Lifecycle>

    private let lifecycleContinuation: AsyncStream<Lifecycle>.Continuation

    // State the C callbacks record, so a failing step can be reported for what it really was.
    // Written and read on the connection thread, except `cancelled`, which `cancel()` sets
    // from another thread.

    /// Set by `cancel()`, and when the auth handler cancels.
    private let cancelled = Atomic<Bool>(false)

    /// Set when the certificate handler rejects the server's certificate.
    private let certificateRejected = Atomic<Bool>(false)

    /// openconnect's first and most recent error messages (`PRG_ERR`) since
    /// `clearErrorMessages()`.
    private let recordedErrorMessages = Mutex<(first: String?, last: String?)>((nil, nil))

    /// openconnect's connection state, for the certificate callback, which reads the server's
    /// certificate. `VPNContext.init` attaches it right after `openconnect_vpninfo_new()`, before
    /// anything can call back; after that it's only read, on the connection thread (starting the
    /// thread orders that read after the write). Not usable once the context is gone.
    nonisolated(unsafe) internal private(set) var vpnInfo: OpaquePointer?

    internal init(
      authenticate: @escaping @Sendable (AuthenticationForm) -> AuthenticationForm?,
      validateCertificate: @escaping @Sendable (CertificateInfo) -> Bool,
      log: @escaping @Sendable (LogLevel, String) -> Void,
      stats: @escaping @Sendable (VPNStats) -> Void
    ) {
      self.authenticate = authenticate
      self.validateCertificate = validateCertificate
      self.log = log
      self.stats = stats
      let (stream, continuation) = AsyncStream.makeStream(of: Lifecycle.self)
      self.lifecycle = stream
      self.lifecycleContinuation = continuation
    }

    /// Reports the connection's progress to the owner.
    internal func report(_ event: Lifecycle) {
      lifecycleContinuation.yield(event)
    }

    /// Ends `lifecycle`. Called once the connection is over.
    internal func finishLifecycle() {
      lifecycleContinuation.finish()
    }

    internal var isCancelled: Bool {
      cancelled.load(ordering: .sequentiallyConsistent)
    }

    internal func markCancelled() {
      cancelled.store(true, ordering: .sequentiallyConsistent)
    }

    internal var isCertificateRejected: Bool {
      certificateRejected.load(ordering: .sequentiallyConsistent)
    }

    internal func markCertificateRejected() {
      certificateRejected.store(true, ordering: .sequentiallyConsistent)
    }

    /// Usually the cause: openconnect logs it before its consequences, for example
    /// "getaddrinfo failed for host …" before "Failed to open HTTPS connection to …".
    internal var firstErrorMessage: String? {
      recordedErrorMessages.withLock { $0.first }
    }

    internal var lastErrorMessage: String? {
      recordedErrorMessages.withLock { $0.last }
    }

    internal func recordErrorMessage(_ message: String) {
      recordedErrorMessages.withLock {
        if $0.first == nil { $0.first = message }
        $0.last = message
      }
    }

    internal func clearErrorMessages() {
      recordedErrorMessages.withLock { $0 = (nil, nil) }
    }

    internal func attach(_ vpnInfo: OpaquePointer) {
      self.vpnInfo = vpnInfo
    }

    /// Recovers the object from a C callback's `privdata`.
    internal static func from(_ privdata: UnsafeMutableRawPointer) -> Callbacks {
      Unmanaged<Callbacks>.fromOpaque(privdata).takeUnretainedValue()
    }
  }
}

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

/// C callback before each attempt to re-establish a lost connection.
/// Registered with `openconnect_set_reconnecting_handler()`.
internal func reconnectingCallback(privdata: UnsafeMutableRawPointer?) {
  guard let privdata = privdata else {
    return
  }

  VPNContext.Callbacks.from(privdata).report(.reconnecting)
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
