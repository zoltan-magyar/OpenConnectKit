//
//  OpenConnectContext+CallbackState.swift
//  OpenConnectKit
//
//  The object openconnect's C callbacks reach through their privdata pointer
//

import Foundation
import Synchronization

extension OpenConnectContext {
  /// What openconnect's C callbacks (`OpenConnectCallbacks.swift`) work with: the context's
  /// delegate, the lifecycle stream, and what they record about the connection. They reach it
  /// through their `privdata` pointer. Everything here is called on the connection thread,
  /// except where noted.
  ///
  /// It's a separate object so it can exist before `openconnect_vpninfo_new()` is called,
  /// which needs the pointer; that is what lets the context's `vpnInfo` be a `let`. It has to be
  /// a class, because C holds on to its address. The context keeps it alive for as long as
  /// `vpnInfo` exists.
  internal final class CallbackState: Sendable {
    /// The owner. Weak, because the owner holds the context.
    internal weak let delegate: (any OpenConnectContextDelegate)?

    /// The owner reads the connection's progress from this. Finishes after `.finished`.
    internal let lifecycle: AsyncStream<Lifecycle>

    private let lifecycleContinuation: AsyncStream<Lifecycle>.Continuation

    // What the C callbacks record, so a failing step can be reported for what it really was.
    // Written and read on the connection thread, except `cancelled`, which `cancel()` sets
    // from another thread.

    /// Set by `cancel()`, and when the login is cancelled.
    private let cancelled = Atomic<Bool>(false)

    /// Set when the owner rejects the server's certificate.
    private let certificateRejected = Atomic<Bool>(false)

    /// openconnect's first and most recent error messages (`PRG_ERR`) since
    /// `clearErrorMessages()`.
    private let recordedErrorMessages = Mutex<(first: String?, last: String?)>((nil, nil))

    /// openconnect's connection state, for the certificate callback, which reads the server's
    /// certificate. `OpenConnectContext.init` attaches it right after `openconnect_vpninfo_new()`,
    /// before anything can call back; after that it's only read, on the connection thread
    /// (starting the thread orders that read after the write). Not usable once the context is
    /// gone.
    nonisolated(unsafe) internal private(set) var vpnInfo: OpaquePointer?

    internal init(delegate: any OpenConnectContextDelegate) {
      self.delegate = delegate
      let (stream, continuation) = AsyncStream.makeStream(of: Lifecycle.self)
      self.lifecycle = stream
      self.lifecycleContinuation = continuation
    }

    /// Passes a log message to the owner.
    internal func log(_ level: LogLevel, _ message: String) {
      delegate?.didLog(message, level: level)
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
    internal static func from(_ privdata: UnsafeMutableRawPointer) -> CallbackState {
      Unmanaged<CallbackState>.fromOpaque(privdata).takeUnretainedValue()
    }
  }
}
