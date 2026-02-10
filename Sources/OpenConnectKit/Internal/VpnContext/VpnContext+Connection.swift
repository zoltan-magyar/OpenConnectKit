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
  /// Connects to VPN: auth cookie → CSTP → DTLS → TUN setup (via callback) → mainloop
  ///
  /// This method blocks during the authentication and connection setup phases.
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

    startMainloop()
  }

  /// Disconnects from the VPN.
  ///
  /// This method sends a cancel command to the mainloop and updates status.
  /// The actual cleanup happens when the mainloop exits.
  func disconnect() {
    if case .disconnected = connectionStatus {
      return
    }

    stopMainloop()

    updateStatus(.disconnected(error: nil))
  }

  /// Updates the connection status and notifies the session delegate.
  ///
  /// - Parameter status: The new connection status
  internal func updateStatus(_ status: ConnectionStatus) {
    connectionStatus = status
    session.handleStatusChange(status: status)
  }
}
