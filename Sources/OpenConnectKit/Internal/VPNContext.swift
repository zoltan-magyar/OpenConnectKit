//
//  VPNContext.swift
//  OpenConnectKit
//
//  Internal wrapper around OpenConnect C API
//

import COpenConnect
import Foundation
import Synchronization

// Owns one openconnect connection (`vpninfo`) for its whole life.
//
// Everything that touches `vpninfo` runs on one dedicated thread, started by `start()`:
// authentication, CSTP, DTLS, TUN setup and then the mainloop. openconnect isn't thread-safe;
// the only channel it supports from other threads is the command pipe, so `cancel()` and
// `requestStats()` are the only calls other threads make. The thread reports back by calling
// the owner's `Callbacks`, and the connection's progress through `lifecycle`, in order.
//
// It's a thread and not `Task.detached` because every one of those calls blocks: on network
// I/O, for as long as the user takes to fill in an auth form, and in the mainloop for the
// whole session. Swift's cooperative thread pool expects its threads never to block.
//
// `vpnInfo` is freed in `deinit`, which can only run once both the owner (VPNSession) and the
// connection thread have let go, so nothing can be using it any more.
internal final class VPNContext: Sendable {
  // MARK: - Types

  /// The connection's progress, from the first step to the end.
  ///
  /// These go through one stream so the owner's state machine sees them in the order they
  /// happened; in particular, `.finished` can never overtake `.established`.
  internal enum Lifecycle: Sendable {
    /// A connection step started.
    case stage(ConnectionStage)

    /// The tunnel is up and the mainloop is starting.
    case established(ConnectionInfo)

    /// openconnect lost the connection and is about to try to re-establish it. Reported before
    /// each attempt, so there can be several before `.reconnected` or `.finished`.
    case reconnecting

    /// openconnect re-established the connection after losing it.
    case reconnected

    /// The connection ended. `nil` if it ended because of `cancel()`; `.cancelled` if it was
    /// cancelled before it was established. Always the last element.
    case finished(VPNError?)
  }

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

  internal enum Command: UInt8 {
    // openconnect.h defines these as character literals ('x', ...), which Swift doesn't import.
    case cancel = 0x78  // 'x'
    case pause = 0x70  // 'p'
    case detach = 0x64  // 'd'
    case stats = 0x73  // 's'
  }

  // MARK: - Properties

  internal let configuration: VPNConfiguration

  internal let callbacks: Callbacks

  /// openconnect's connection state. Only the connection thread uses it, apart from `init` and
  /// `deinit`, which can't overlap with that thread.
  nonisolated(unsafe) internal let vpnInfo: OpaquePointer

  /// Write end of openconnect's command pipe (`OC_CMD_*` bytes). Safe to write from any thread.
  internal let commandPipe: Int32

  // MARK: - Initialization

  /// Creates the openconnect state for a connection. Nothing connects until `start()`.
  ///
  /// - Throws: `VPNError` if openconnect can't be set up, or the server URL is invalid.
  internal init(configuration: VPNConfiguration, callbacks: Callbacks) throws(VPNError) {
    // openconnect_parse_url() accepts a URL without a host, which then only fails when
    // connecting, with an empty host name in the message.
    guard let host = configuration.serverURL.host(), !host.isEmpty else {
      throw .invalidConfiguration(reason: "The server URL has no host name")
    }

    guard
      let vpnInfo = openconnect_vpninfo_new(
        "AnyConnect Compatible OpenConnectKit Client",
        validatePeerCertCallback,
        nil,
        processAuthFormCallback,
        nil,  // variadic progress callback, which Swift can't implement; see below
        Unmanaged.passUnretained(callbacks).toOpaque()
      )
    else {
      throw .internalError(reason: "Could not create the openconnect session")
    }

    callbacks.attach(vpnInfo)

    // Receives log messages already formatted. Set before anything can log.
    openconnect_set_progress_msg_handler(vpnInfo, progressCallback)
    openconnect_set_loglevel(vpnInfo, configuration.logLevel.openConnectLevel)

    // Before the URL: how openconnect reads it depends on the protocol.
    guard openconnect_set_protocol(vpnInfo, configuration.vpnProtocol.rawValue) == 0 else {
      openconnect_vpninfo_free(vpnInfo)
      throw .invalidConfiguration(
        reason: callbacks.firstErrorMessage
          ?? "openconnect doesn't support \(configuration.vpnProtocol.displayName)")
    }

    guard openconnect_parse_url(vpnInfo, configuration.serverURL.absoluteString) == 0 else {
      openconnect_vpninfo_free(vpnInfo)
      throw .invalidConfiguration(
        reason: callbacks.firstErrorMessage ?? "Could not parse the server URL")
    }

    let commandPipe = openconnect_setup_cmd_pipe(vpnInfo)
    guard commandPipe >= 0 else {
      openconnect_vpninfo_free(vpnInfo)
      throw .internalError(reason: "Could not create the command pipe")
    }

    openconnect_set_reconnecting_handler(vpnInfo, reconnectingCallback)
    openconnect_set_reconnected_handler(vpnInfo, reconnectedCallback)
    openconnect_set_stats_handler(vpnInfo, statsCallback)

    self.configuration = configuration
    self.callbacks = callbacks
    self.vpnInfo = vpnInfo
    self.commandPipe = commandPipe
  }

  deinit {
    // Also closes both ends of the command pipe.
    openconnect_vpninfo_free(vpnInfo)
    callbacks.finishLifecycle()
  }

  // MARK: - Computed Properties

  /// The connection's progress, in order. Finishes after `.finished`.
  internal var lifecycle: AsyncStream<Lifecycle> {
    callbacks.lifecycle
  }

  /// Whether the connection was cancelled, by `cancel()` or from the auth form.
  internal var isCancelled: Bool {
    callbacks.isCancelled
  }

  /// `.cancelled` or `.certificateRejected` if the user stopped the connection, otherwise
  /// `nil`. Checked before a failing step's own error, which is then only a consequence.
  internal var userAbort: VPNError? {
    if callbacks.isCancelled { return .cancelled }
    if callbacks.isCertificateRejected { return .certificateRejected }
    return nil
  }

  /// Why the current step failed: openconnect's first error message since the step started,
  /// or `fallback`.
  internal func errorMessage(or fallback: String) -> String {
    callbacks.firstErrorMessage ?? fallback
  }
}
