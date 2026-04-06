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
  /// Connects to VPN: auth cookie → CSTP → DTLS → TUN setup → mainloop
  ///
  /// This method blocks during the authentication, connection, and TUN setup phases.
  /// The mainloop runs on a background task after setup completes.
  ///
  /// - Throws: `VpnError` if connection fails at any step
  func connect() throws {
    guard case .disconnected = connectionStatus else {
      return
    }

    updateStatus(.connecting(stage: "Initializing connection"))

    updateStatus(.connecting(stage: "Authenticating..."))
    var ret = openconnect_obtain_cookie(vpnInfo)
    if ret != 0 {
      updateStatus(.disconnected(error: .cookieObtainFailed))
      throw VpnError.cookieObtainFailed
    }

    updateStatus(.connecting(stage: "Establishing CSTP connection"))
    ret = openconnect_make_cstp_connection(vpnInfo)
    if ret != 0 {
      updateStatus(.disconnected(error: .cstpConnectionFailed))
      throw VpnError.cstpConnectionFailed
    }

    updateStatus(.connecting(stage: "Setting up DTLS"))
    ret = openconnect_setup_dtls(vpnInfo, 60)
    if ret != 0 {
      updateStatus(.disconnected(error: .dtlsSetupFailed))
      throw VpnError.dtlsSetupFailed
    }

    // Set up TUN device before starting mainloop
    // This allows synchronous error handling rather than relying on callbacks
    updateStatus(.connecting(stage: "Configuring tunnel"))
    try setupTunDevice()

    updateStatus(.connected)
    startMainloop()
  }

  /// Sets up the TUN device for the VPN connection.
  ///
  /// This finds the vpnc-script and configures the TUN device.
  /// Must be called after DTLS setup and before starting the mainloop.
  ///
  /// - Throws: `VpnError` if TUN setup fails
  private func setupTunDevice() throws {
    guard let vpncScriptPath = findVpncScript() else {
      updateStatus(.disconnected(error: .vpncScriptFailed))
      throw VpnError.vpncScriptFailed
    }

    guard let vpnInfo = vpnInfo else {
      updateStatus(.disconnected(error: .notInitialized))
      throw VpnError.notInitialized
    }

    let vpncScriptPtr = vpncScriptPath.withCString { strdup($0) }
    let interfaceNamePtr = session.configuration.interfaceName?.withCString { strdup($0) }

    defer {
      free(vpncScriptPtr)
      free(interfaceNamePtr)
    }

    let ret = openconnect_setup_tun_device(vpnInfo, vpncScriptPtr, interfaceNamePtr)
    if ret != 0 {
      updateStatus(.disconnected(error: .tunSetupFailed))
      throw VpnError.tunSetupFailed
    }
  }

  /// Disconnects from the VPN.
  ///
  /// This method sends a cancel command to the mainloop and updates status.
  /// The actual cleanup happens when the mainloop exits.
  func disconnect() {
    if case .disconnected = connectionStatus {
      return
    }
    if case .disconnecting = connectionStatus {
      return
    }

    stopMainloop()

    updateStatus(.disconnecting)
  }

  /// Updates the connection status and notifies the session delegate.
  ///
  /// - Parameter status: The new connection status
  internal func updateStatus(_ status: ConnectionStatus) {
    connectionStatus = status
    session.handleStatusChange(status: status)
  }
}
