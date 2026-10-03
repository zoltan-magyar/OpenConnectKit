//
//  VpnContext+Connection.swift
//  OpenConnectKit
//
//  Connection management extension for VpnContext
//

import COpenConnect
import Foundation

// MARK: - Connection Management

extension VpnContext {
  /// Starts the connection on its own thread. Progress and the outcome arrive as `events`.
  ///
  /// Call it once. The thread keeps the context alive until the connection has ended.
  func start() {
    let thread = Thread { [self] in
      run()
    }
    thread.name = "OpenConnectKit.connection"
    thread.qualityOfService = .userInitiated
    thread.start()
  }

  /// The connection thread: connects, then runs the mainloop until the connection ends.
  private func run() {
    let events = callbacks.events
    defer { events.finish() }

    do {
      try establish()
    } catch {
      events.yield(.finished(isCancelled ? .cancelled : error))
      return
    }

    let interfaceName = openconnect_get_ifname(vpnInfo).map { String(cString: $0) }
    events.yield(.established(interfaceName: interfaceName))
    events.yield(.finished(runMainloop()))
  }

  /// Connects to VPN: auth cookie -> CSTP -> DTLS -> TUN setup
  ///
  /// Blocks for the whole sequence, including while an auth form waits for the user.
  ///
  /// - Throws: `VpnError` if a step fails
  private func establish() throws(VpnError) {
    // cancel() may have been called before the thread started.
    if isCancelled { throw .cancelled }

    stage("Authenticating...")
    guard openconnect_obtain_cookie(vpnInfo) == 0 else {
      throw .cookieObtainFailed
    }

    stage("Establishing CSTP connection")
    guard openconnect_make_cstp_connection(vpnInfo) == 0 else {
      throw .cstpConnectionFailed
    }

    stage("Setting up DTLS")
    if openconnect_setup_dtls(vpnInfo, 60) != 0 {
      // Not fatal: the server may not offer DTLS at all ("No DTLS address"). Like openconnect's
      // own client, carry on over TLS, and disable DTLS so reconnects don't keep retrying it.
      openconnect_disable_dtls(vpnInfo)
      callbacks.handlers.log(.info, "DTLS unavailable, using TLS only")
    }

    stage("Configuring tunnel")
    try setupTunDevice()
  }

  /// Sets up the TUN device for the VPN connection.
  ///
  /// This finds the vpnc-script and configures the TUN device.
  /// Must be called after DTLS setup and before starting the mainloop.
  ///
  /// - Throws: `VpnError` if TUN setup fails
  private func setupTunDevice() throws(VpnError) {
    guard let vpncScriptPath = findVpncScript() else {
      throw .vpncScriptFailed
    }

    // openconnect copies both strings, so Swift's temporary C strings are enough.
    guard
      openconnect_setup_tun_device(vpnInfo, vpncScriptPath, configuration.interfaceName) == 0
    else {
      throw .tunSetupFailed
    }
  }

  private func stage(_ description: String) {
    callbacks.events.yield(.stage(description))
  }
}
