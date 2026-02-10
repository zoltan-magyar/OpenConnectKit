//
//  VpnContext+Mainloop.swift
//  OpenConnectKit
//
//  Mainloop management extension for VpnContext
//

import COpenConnect
import Foundation

// MARK: - Mainloop Management

extension VpnContext {
  /// Starts the mainloop on a background task.
  ///
  /// The mainloop handles all VPN traffic and reconnection logic.
  /// It runs until cancelled or an error occurs.
  internal func startMainloop() {
    mainloopTask = Task.detached { [weak self] in
      self?.runMainloop()
    }
  }

  /// Stops the mainloop by sending a cancel command.
  ///
  /// The mainloop will exit gracefully after processing the cancel command.
  internal func stopMainloop() {
    guard case .connected = connectionStatus else {
      return
    }

    sendCommand(.cancel)
  }

  /// Runs the mainloop until error or cancellation.
  ///
  /// This method blocks the current thread while the mainloop is running.
  /// It should only be called from a background task.
  private func runMainloop() {
    guard let vpnInfo = vpnInfo else {
      updateStatus(.disconnected(error: .notInitialized))
      return
    }

    // Run the OpenConnect mainloop
    // This blocks until the connection ends or is cancelled
    while !Task.isCancelled {
      let ret = openconnect_mainloop(
        vpnInfo,
        session.configuration.reconnectTimeout,
        session.configuration.reconnectInterval
      )

      if ret != 0 {
        break
      }
    }

    // Determine the disconnect reason
    let error: VpnError?
    switch connectionStatus {
    case .disconnected:
      // Already disconnected (user initiated)
      error = nil
    default:
      // Unexpected disconnect - use setup error if available
      error = setupError ?? .connectionFailed(reason: "Connection lost")
    }

    updateStatus(.disconnected(error: error))

    // Clear any captured setup error
    setupError = nil
  }
}
