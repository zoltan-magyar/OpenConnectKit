//
//  OpenConnectContext+CallbackState.swift
//  OpenConnectKit
//
//  The object openconnect's C callbacks reach through their privdata pointer
//

import COpenConnect
import Foundation
import Synchronization

extension OpenConnectContext {
  /// What openconnect's C callbacks (`OpenConnectCallbacks.swift`) work with: the context's
  /// delegate, the lifecycle stream, the command pipe, and what they record about the
  /// connection. They reach it through their `privdata` pointer. Everything here is called on
  /// the connection thread, except where noted.
  ///
  /// It's a separate object so it can exist before `openconnect_vpninfo_new()` is called,
  /// which needs the pointer; that is what lets the context's `vpnInfo` be a `let`. It has to be
  /// a class, because C holds on to its address. The context keeps it alive for as long as
  /// `vpnInfo` exists.
  internal final class CallbackState: Sendable {
    /// The context's delegate. Weak, because it's normally the context's owner, which holds the
    /// context.
    internal weak let delegate: (any OpenConnectContextDelegate)?

    /// The owner reads the connection's progress from this. Finishes after `.finished`.
    internal let lifecycle: AsyncStream<Lifecycle>

    private let lifecycleContinuation: AsyncStream<Lifecycle>.Continuation

    // What the C callbacks record: the delegate's answers, so a failing step can be reported for
    // what it really was and an accepted certificate isn't asked about again, and openconnect's
    // error messages. Written and read on the connection thread, except `cancelled`, which
    // `cancel()` sets from another thread.

    /// Set by `cancel()`, and when the login is cancelled.
    private let cancelled = Atomic<Bool>(false)

    /// Set when the delegate rejects the server's certificate, or there's no delegate to accept it.
    /// The connection is ending then, so the certificate callback doesn't ask about another one.
    private let certificateRejected = Atomic<Bool>(false)

    /// The server certificates the delegate accepted in this connection, for `hasAccepted(_:)`.
    private let acceptedCertificates = Mutex<[AcceptedCertificate]>([])

    /// openconnect's first and most recent error messages (`PRG_ERR`) since
    /// `clearErrorMessages()`.
    private let recordedErrorMessages = Mutex<(first: String?, last: String?)>((nil, nil))

    /// openconnect's connection state, for the certificate callback, which reads the server's
    /// certificate. `OpenConnectContext.init` attaches it right after `openconnect_vpninfo_new()`,
    /// before anything can call back; after that it's only read, on the connection thread
    /// (starting the thread orders that read after the write). Not usable once the context is
    /// gone.
    nonisolated(unsafe) internal private(set) var vpnInfo: OpaquePointer?

    /// The write end of openconnect's command pipe, for `send(_:)`. The context's own
    /// `commandPipe`, attached and read like `vpnInfo`.
    nonisolated(unsafe) private var commandPipe: Int32 = -1

    internal init(delegate: any OpenConnectContextDelegate) {
      self.delegate = delegate
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

    /// Safe to call from any thread.
    internal func markCancelled() {
      cancelled.store(true, ordering: .sequentiallyConsistent)
    }

    internal var isCertificateRejected: Bool {
      certificateRejected.load(ordering: .sequentiallyConsistent)
    }

    internal func markCertificateRejected() {
      certificateRejected.store(true, ordering: .sequentiallyConsistent)
    }

    /// Whether the delegate already accepted this certificate in this connection, when it was
    /// asked the same question: the same server (host name and port) presenting it, with the same
    /// verdict from the system.
    ///
    /// Certificates count as the same when their public keys are, which is what the pin
    /// identifies. Pins are compared with `openconnect_check_peer_cert_hash()`, not as strings, as
    /// `openconnect.h` asks. That reads the current certificate, so this is only valid inside the
    /// certificate callback, like `CertificateInfo(vpnInfo:)`.
    internal func hasAccepted(_ certificate: CertificateInfo) -> Bool {
      guard let vpnInfo, let hostname = certificate.hostname?.lowercased() else {
        return false
      }
      let port = openconnect_get_port(vpnInfo)
      // Copied out, so openconnect isn't called with the lock held.
      let accepted = acceptedCertificates.withLock { $0 }
      return accepted.contains {
        $0.hostname == hostname && $0.port == port && $0.systemTrust == certificate.systemTrust
          && openconnect_check_peer_cert_hash(vpnInfo, $0.pin) == 0
      }
    }

    /// Records that the delegate accepted this certificate, for `hasAccepted(_:)`. Only valid
    /// inside the certificate callback, which reads the server's port.
    internal func recordAccepted(_ certificate: CertificateInfo) {
      guard let vpnInfo, let hostname = certificate.hostname, let pin = certificate.pin else {
        return
      }
      let accepted = AcceptedCertificate(
        hostname: hostname.lowercased(),
        port: openconnect_get_port(vpnInfo),
        pin: pin,
        systemTrust: certificate.systemTrust
      )
      acceptedCertificates.withLock { $0.append(accepted) }
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

    /// Writes a command to openconnect's command pipe, for a callback that has to stop the
    /// connection itself. Unlike `OpenConnectContext.cancel()`, it doesn't mark the connection
    /// cancelled.
    internal func send(_ command: Command) {
      command.send(to: commandPipe)
    }

    /// Gives the callbacks the parts of openconnect's state they use. Called once, by
    /// `OpenConnectContext.init`, before anything can call back.
    internal func attach(_ vpnInfo: OpaquePointer, commandPipe: Int32) {
      self.vpnInfo = vpnInfo
      self.commandPipe = commandPipe
    }

    /// Recovers the object from a C callback's `privdata`.
    internal static func from(_ privdata: UnsafeMutableRawPointer) -> CallbackState {
      Unmanaged<CallbackState>.fromOpaque(privdata).takeUnretainedValue()
    }

    /// A server certificate the delegate accepted, and what it was asked about.
    private struct AcceptedCertificate: Sendable {
      /// The server's host name, lowercased: host names are case-insensitive.
      internal let hostname: String

      /// The server's port.
      internal let port: Int32

      /// The certificate's pin, from `openconnect_get_peer_cert_hash()`.
      internal let pin: String

      /// The system's verdict on the certificate when the delegate accepted it.
      internal let systemTrust: SystemTrust
    }
  }
}
