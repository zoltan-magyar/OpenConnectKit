//
//  OpenConnectContext.swift
//  OpenConnectKit
//
//  One openconnect connection (vpninfo) and the thread that drives it
//

import COpenConnect
import Foundation

/// Owns one openconnect connection (`vpninfo`) for its whole life.
///
/// The object that creates a context is its owner (`VPNSession` today), and also its delegate
/// (`OpenConnectContextDelegate`): it answers openconnect's questions and receives the logs and
/// statistics. The owner reads the connection's progress from `lifecycle`.
///
/// Everything that touches `vpninfo` runs on one dedicated thread, started by `start()`:
/// authentication, CSTP, DTLS, TUN setup and then the mainloop. openconnect isn't thread-safe;
/// the only channel it supports from other threads is the command pipe, so `cancel()` and
/// `requestStats()` are the only calls other threads make. The thread calls the delegate from
/// openconnect's C callbacks (`OpenConnectCallbacks.swift`), and reports the connection's
/// progress through `lifecycle`, in order.
///
/// It's a thread and not `Task.detached` because every one of those calls blocks: on network
/// I/O, for as long as the user takes to fill in an auth form, and in the mainloop for the
/// whole session. Swift's cooperative thread pool expects its threads never to block.
///
/// `vpnInfo` is freed in `deinit`, which can only run once both the owner and the connection
/// thread have let go, so nothing can be using it any more.
internal final class OpenConnectContext: Sendable {
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

  /// Commands for openconnect's command pipe (`OC_CMD_*`), written to `commandPipe`.
  ///
  /// openconnect.h defines them as character literals (`'x'`, ...), which Swift doesn't import.
  internal enum Command: UInt8 {
    case cancel = 0x78  // 'x'
    case pause = 0x70  // 'p'
    case detach = 0x64  // 'd'
    case stats = 0x73  // 's'

    /// Writes the command to the write end of openconnect's command pipe. Safe to call from any
    /// thread.
    ///
    /// The pipe stays open until `vpninfo` is freed, in the context's `deinit`, so this is safe
    /// even after the connection has ended: the byte is simply never read.
    internal func send(to commandPipe: Int32) {
      var byte = rawValue
      // Nonblocking, and only ever holds a few bytes, so a failed write isn't worth reporting.
      _ = write(commandPipe, &byte, 1)
    }
  }

  // MARK: - Properties

  internal let configuration: VPNConfiguration

  /// What openconnect's C callbacks work with, including the delegate.
  internal let state: CallbackState

  /// openconnect's connection state. Only the connection thread uses it, apart from `init` and
  /// `deinit`, which can't overlap with that thread.
  nonisolated(unsafe) internal let vpnInfo: OpaquePointer

  /// Write end of openconnect's command pipe (`OC_CMD_*` bytes). Safe to write from any thread.
  internal let commandPipe: Int32

  // MARK: - Initialization

  /// Creates the openconnect state for a connection. Nothing connects until `start()`.
  ///
  /// - Parameter delegate: Answers openconnect's questions and receives the logs and statistics.
  ///   Held weakly, because it's normally the owner, which holds the context.
  /// - Throws: `VPNError` if openconnect can't be set up, or the server URL is invalid.
  internal init(
    configuration: VPNConfiguration, delegate: any OpenConnectContextDelegate
  ) throws(VPNError) {
    // openconnect_parse_url() accepts a URL without a host, which then only fails when
    // connecting, with an empty host name in the message.
    guard let host = configuration.serverURL.host(), !host.isEmpty else {
      throw .invalidConfiguration(reason: "The server URL has no host name")
    }

    let state = CallbackState(delegate: delegate)
    guard
      let vpnInfo = openconnect_vpninfo_new(
        "AnyConnect Compatible OpenConnectKit Client",
        validatePeerCertCallback,
        nil,
        processAuthFormCallback,
        nil,  // variadic progress callback, which Swift can't implement; see below
        Unmanaged.passUnretained(state).toOpaque()
      )
    else {
      throw .internalError(reason: "Could not create the openconnect session")
    }

    // Right away, so the callbacks get it together with vpnInfo: the certificate callback writes
    // to it when the delegate rejects a certificate.
    let commandPipe = openconnect_setup_cmd_pipe(vpnInfo)
    guard commandPipe >= 0 else {
      openconnect_vpninfo_free(vpnInfo)
      throw .internalError(reason: "Could not create the command pipe")
    }

    state.attach(vpnInfo, commandPipe: commandPipe)

    // Every server certificate must reach the certificate callback, which asks the system
    // (SystemTrust) and then the delegate, so OpenSSL must never accept one on its own. With system
    // trust on, it would trust any CA in its compiled-in OPENSSLDIR (a path on the build
    // machine) or in the files that SSL_CERT_FILE and SSL_CERT_DIR name, and the callback would
    // never be called.
    openconnect_set_system_trust(vpnInfo, 0)

    // Receives log messages already formatted. Set before anything can log.
    openconnect_set_progress_msg_handler(vpnInfo, progressCallback)
    openconnect_set_loglevel(vpnInfo, configuration.logLevel.openConnectLevel)

    // Before the URL: how openconnect reads it depends on the protocol.
    guard openconnect_set_protocol(vpnInfo, configuration.vpnProtocol.rawValue) == 0 else {
      openconnect_vpninfo_free(vpnInfo)
      throw .invalidConfiguration(
        reason: state.firstErrorMessage
          ?? "openconnect doesn't support \(configuration.vpnProtocol.displayName)")
    }

    guard openconnect_parse_url(vpnInfo, configuration.serverURL.absoluteString) == 0 else {
      openconnect_vpninfo_free(vpnInfo)
      throw .invalidConfiguration(
        reason: state.firstErrorMessage ?? "Could not parse the server URL")
    }

    openconnect_set_reconnecting_handler(vpnInfo, reconnectingCallback)
    openconnect_set_reconnected_handler(vpnInfo, reconnectedCallback)
    openconnect_set_stats_handler(vpnInfo, statsCallback)

    self.configuration = configuration
    self.state = state
    self.vpnInfo = vpnInfo
    self.commandPipe = commandPipe
  }

  deinit {
    // Also closes both ends of the command pipe.
    openconnect_vpninfo_free(vpnInfo)
    state.finishLifecycle()
  }

  // MARK: - Computed Properties

  /// The connection's progress, in order. Finishes after `.finished`.
  internal var lifecycle: AsyncStream<Lifecycle> {
    state.lifecycle
  }

  /// Whether the connection was cancelled, by `cancel()` or from the auth form.
  internal var isCancelled: Bool {
    state.isCancelled
  }

  /// `.cancelled` or `.certificateRejected` if the user stopped the connection, otherwise
  /// `nil`. Checked before a failing step's own error, which is then only a consequence.
  internal var userAbort: VPNError? {
    if state.isCancelled { return .cancelled }
    if state.isCertificateRejected { return .certificateRejected }
    return nil
  }

  /// Why the current step failed: openconnect's first error message since the step started,
  /// or `fallback`.
  internal func errorMessage(or fallback: String) -> String {
    state.firstErrorMessage ?? fallback
  }
}
