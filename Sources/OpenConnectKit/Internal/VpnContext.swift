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
// `requestStats()` are the only calls other threads make. The thread reports back through
// `events`, in order.
//
// It's a thread and not `Task.detached` because every one of those calls blocks: on network
// I/O, for as long as the user takes to fill in an auth form, and in the mainloop for the
// whole session. Swift's cooperative thread pool expects its threads never to block.
//
// `vpnInfo` is freed in `deinit`, which can only run once both the owner (VpnSession) and the
// connection thread have let go, so nothing can be using it any more.
final class VpnContext: Sendable {
  // MARK: - Types

  /// What the connection thread reports, in order.
  enum Event: Sendable {
    /// A connection step started; a human-readable description.
    case stage(String)

    /// The tunnel is up and the mainloop is starting.
    case established(interfaceName: String?)

    /// openconnect re-established the connection after losing it.
    case reconnected

    /// Traffic statistics, in reply to `requestStats()`.
    case stats(VpnStats)

    /// The connection ended. `nil` if it ended because of `cancel()`; `.cancelled` if it was
    /// cancelled before it was established. Always the last event.
    case finished(VpnError?)
  }

  /// What the C callbacks hand over to the owner. Called on the connection thread.
  struct Handlers: Sendable {
    /// Blocks until the form is filled in. Returning `nil` cancels the connection.
    var authenticate: @Sendable (AuthenticationForm) -> AuthenticationForm?

    /// Blocks until a decision is made. Returning `true` accepts the certificate.
    var validateCertificate: @Sendable (CertificateInfo) -> Bool

    /// Receives every log message. Called often, so it shouldn't block.
    var log: @Sendable (LogLevel, String) -> Void
  }

  /// What the C callbacks reach through their `privdata` pointer.
  ///
  /// It's a separate object so it can exist before `openconnect_vpninfo_new()` is called,
  /// which needs the pointer; that is what lets `vpnInfo` be a `let`. VpnContext keeps it alive
  /// for as long as `vpnInfo` exists.
  final class Callbacks: Sendable {
    let handlers: Handlers
    let events: AsyncStream<Event>.Continuation

    /// Set by `cancel()`, and when the auth handler cancels. Read on the connection thread to
    /// tell a cancellation apart from a failure.
    private let cancelled = Atomic<Bool>(false)

    init(handlers: Handlers, events: AsyncStream<Event>.Continuation) {
      self.handlers = handlers
      self.events = events
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

  /// Progress and the outcome of the connection. Finishes after `.finished`.
  let events: AsyncStream<Event>

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
  init(configuration: VpnConfiguration, handlers: Handlers) throws(VpnError) {
    let (events, continuation) = AsyncStream.makeStream(of: Event.self)
    let callbacks = Callbacks(handlers: handlers, events: continuation)

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
    self.events = events
    self.callbacks = callbacks
    self.vpnInfo = vpnInfo
    self.commandPipe = commandPipe
  }

  deinit {
    // Also closes both ends of the command pipe.
    openconnect_vpninfo_free(vpnInfo)
    callbacks.events.finish()
  }

  // MARK: - Computed Properties

  /// Whether the connection was cancelled, by `cancel()` or from the auth form.
  var isCancelled: Bool {
    callbacks.isCancelled
  }
}
