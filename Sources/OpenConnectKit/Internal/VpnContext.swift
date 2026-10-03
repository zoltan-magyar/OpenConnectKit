//
//  VpnContext.swift
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
// `vpnInfo` is freed in `deinit`, which can only run once both the owner (VpnSession) and the
// connection thread have let go, so nothing can be using it any more.
final class VpnContext: Sendable {
  // MARK: - Types

  /// The connection's progress, from the first step to the end.
  ///
  /// These go through one stream so the owner's state machine sees them in the order they
  /// happened; in particular, `.finished` can never overtake `.established`.
  enum Lifecycle: Sendable {
    /// A connection step started; a human-readable description.
    case stage(String)

    /// The tunnel is up and the mainloop is starting.
    case established(interfaceName: String?)

    /// openconnect re-established the connection after losing it.
    case reconnected

    /// The connection ended. `nil` if it ended because of `cancel()`; `.cancelled` if it was
    /// cancelled before it was established. Always the last element.
    case finished(VpnError?)
  }

  /// How the context reaches its owner. The owner creates it; the C callbacks reach it through
  /// their `privdata` pointer. Everything here is called on the connection thread.
  ///
  /// It's a separate object so it can exist before `openconnect_vpninfo_new()` is called,
  /// which needs the pointer; that is what lets `vpnInfo` be a `let`. It has to be a class,
  /// because C holds on to its address. VpnContext keeps it alive for as long as `vpnInfo`
  /// exists.
  final class Callbacks: Sendable {
    /// Blocks until the form is filled in. Returning `nil` cancels the connection.
    let authenticate: @Sendable (AuthenticationForm) -> AuthenticationForm?

    /// Blocks until a decision is made. Returning `true` accepts the certificate.
    let validateCertificate: @Sendable (CertificateInfo) -> Bool

    /// Receives every log message. Called often, so it shouldn't block.
    let log: @Sendable (LogLevel, String) -> Void

    /// Receives traffic statistics, in reply to `requestStats()`.
    ///
    /// Not ordered with `lifecycle`: a reply can still come in after `.finished` has been
    /// reported, and the owner has to ignore it then.
    let stats: @Sendable (VpnStats) -> Void

    /// The owner reads the connection's progress from this. Finishes after `.finished`.
    let lifecycle: AsyncStream<Lifecycle>

    private let lifecycleContinuation: AsyncStream<Lifecycle>.Continuation

    /// Set by `cancel()`, and when the auth handler cancels. Read on the connection thread to
    /// tell a cancellation apart from a failure.
    private let cancelled = Atomic<Bool>(false)

    init(
      authenticate: @escaping @Sendable (AuthenticationForm) -> AuthenticationForm?,
      validateCertificate: @escaping @Sendable (CertificateInfo) -> Bool,
      log: @escaping @Sendable (LogLevel, String) -> Void,
      stats: @escaping @Sendable (VpnStats) -> Void
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
    func report(_ event: Lifecycle) {
      lifecycleContinuation.yield(event)
    }

    /// Ends `lifecycle`. Called once the connection is over.
    func finishLifecycle() {
      lifecycleContinuation.finish()
    }

    var isCancelled: Bool {
      cancelled.load(ordering: .sequentiallyConsistent)
    }

    func markCancelled() {
      cancelled.store(true, ordering: .sequentiallyConsistent)
    }

    /// Recovers the object from a C callback's `privdata`.
    static func from(_ privdata: UnsafeMutableRawPointer) -> Callbacks {
      Unmanaged<Callbacks>.fromOpaque(privdata).takeUnretainedValue()
    }
  }

  enum Command: UInt8 {
    // openconnect.h defines these as character literals ('x', ...), which Swift doesn't import.
    case cancel = 0x78  // 'x'
    case pause = 0x70  // 'p'
    case detach = 0x64  // 'd'
    case stats = 0x73  // 's'
  }

  // MARK: - Properties

  let configuration: VpnConfiguration

  let callbacks: Callbacks

  /// openconnect's connection state. Only the connection thread uses it, apart from `init` and
  /// `deinit`, which can't overlap with that thread.
  nonisolated(unsafe) let vpnInfo: OpaquePointer

  /// Write end of openconnect's command pipe (`OC_CMD_*` bytes). Safe to write from any thread.
  let commandPipe: Int32

  // MARK: - Initialization

  /// Creates the openconnect state for a connection. Nothing connects until `start()`.
  ///
  /// - Throws: `VpnError` if openconnect can't be set up, or the server URL is invalid.
  init(configuration: VpnConfiguration, callbacks: Callbacks) throws(VpnError) {
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
      throw .notInitialized
    }

    // Receives log messages already formatted. Set before anything can log.
    openconnect_set_progress_msg_handler(vpnInfo, progressCallback)
    openconnect_set_loglevel(vpnInfo, configuration.logLevel.openConnectLevel)

    guard openconnect_parse_url(vpnInfo, configuration.serverURL.absoluteString) == 0 else {
      openconnect_vpninfo_free(vpnInfo)
      throw .invalidConfiguration(reason: "Failed to parse server URL")
    }

    let commandPipe = openconnect_setup_cmd_pipe(vpnInfo)
    guard commandPipe >= 0 else {
      openconnect_vpninfo_free(vpnInfo)
      throw .cmdPipeSetupFailed
    }

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
  var lifecycle: AsyncStream<Lifecycle> {
    callbacks.lifecycle
  }

  /// Whether the connection was cancelled, by `cancel()` or from the auth form.
  var isCancelled: Bool {
    callbacks.isCancelled
  }
}
