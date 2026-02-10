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
    sendCommand(.cancel)
  }

  /// Runs the mainloop until error or cancellation via command pipe.
  ///
  /// This method blocks the current thread while the mainloop is running.
  /// It should only be called from a background task.
  /// The mainloop exits when a cancel command is sent via the command pipe.
  private func runMainloop() {
    guard let vpnInfo = vpnInfo else {
      updateStatus(.disconnected(error: .notInitialized))
      return
    }

    // Run the OpenConnect mainloop
    // This blocks until the connection ends or is cancelled via command pipe
    let ret = openconnect_mainloop(
      vpnInfo,
      session.configuration.reconnectTimeout,
      session.configuration.reconnectInterval
    )

    // Determine the disconnect reason based on return value and current status
    let error: VpnError?
    switch connectionStatus {
    case .disconnected:
      // Already disconnected (user initiated)
      error = nil
    default:
      // Unexpected disconnect - mainloop exited with error
      if ret < 0 {
        error = .connectionFailed(reason: "Connection lost")
      } else {
        // Normal exit (cancelled)
        error = nil
      }
    }

    updateStatus(.disconnected(error: error))
  }
}
