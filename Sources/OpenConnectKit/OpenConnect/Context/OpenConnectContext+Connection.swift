//
//  OpenConnectContext+Connection.swift
//  OpenConnectKit
//
//  Connection management extension for OpenConnectContext
//

import COpenConnect
import Foundation

// MARK: - Connection Management

extension OpenConnectContext {
  /// Starts the connection on its own thread. Progress and the outcome arrive in `lifecycle`.
  ///
  /// Call it once. The thread keeps the context alive until the connection has ended.
  internal func start() {
    let thread = Thread { [self] in
      run()
    }
    thread.name = "OpenConnectKit.connection"
    thread.qualityOfService = .userInitiated
    thread.start()
  }

  /// The connection thread: connects, then runs the mainloop until the connection ends.
  private func run() {
    defer { state.finishLifecycle() }

    do {
      try establish()
    } catch {
      // If the user cancelled or rejected the certificate, the step's own error is only a
      // consequence of that.
      state.report(.finished(userAbort ?? error))
      return
    }
    state.report(.established(connectionInfo()))

    // Blocks for the rest of the session: the mainloop carries the traffic and reconnects by
    // itself, and only returns once the connection has ended.
    let error = runMainloop()
    state.report(.finished(error))
  }

  /// Connects to VPN: auth cookie -> CSTP -> DTLS -> TUN setup
  ///
  /// Blocks for the whole sequence, including while an auth form waits for the user.
  ///
  /// - Throws: `VPNError` if a step fails
  private func establish() throws(VPNError) {
    // cancel() may have been called before the thread started.
    if isCancelled { throw .cancelled }

    begin(.authenticating)
    guard openconnect_obtain_cookie(vpnInfo) == 0 else {
      throw .authenticationFailed(reason: errorMessage(or: "Could not log in to the server"))
    }

    begin(.establishingTunnel)
    guard openconnect_make_cstp_connection(vpnInfo) == 0 else {
      throw .tunnelFailed(reason: errorMessage(or: "Could not establish the tunnel"))
    }

    begin(.settingUpDTLS)
    if openconnect_setup_dtls(vpnInfo, 60) != 0 {
      // Not fatal: the server may not offer DTLS at all ("No DTLS address"). Like openconnect's
      // own client, carry on over TLS, and disable DTLS so reconnects don't keep retrying it.
      openconnect_disable_dtls(vpnInfo)
      state.delegate?.didLog("DTLS unavailable, using TLS only", level: .info)
    }

    begin(.configuringNetwork)
    try setupTunDevice()  // LEGACY, see OpenConnectContext+VpncScript.swift
  }

  /// Reports that a step started, and forgets error messages from earlier steps, so a failure
  /// is explained by a message from the step that failed.
  private func begin(_ stage: ConnectionStage) {
    state.clearErrorMessages()
    state.report(.stage(stage))
  }

  /// The details of the established connection. Read here, on the connection thread, before
  /// the mainloop starts.
  private func connectionInfo() -> ConnectionInfo {
    ConnectionInfo(
      interfaceName: openconnect_get_ifname(vpnInfo).map { String(cString: $0) },
      serverName: openconnect_get_dnsname(vpnInfo).map { String(cString: $0) },
      serverAddress: openconnect_get_hostname(vpnInfo).map { String(cString: $0) },
      connectedAt: Date()
    )
  }
}
