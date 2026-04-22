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
  /// Starts the mainloop on a dedicated thread.
  ///
  /// The mainloop handles all VPN traffic and reconnection logic.
  /// It runs until cancelled or an error occurs.
  ///
  /// Uses a dedicated Thread instead of Task.detached because
  /// openconnect_mainloop() blocks indefinitely and should not
  /// consume a cooperative thread pool thread.
  internal func startMainloop() {
    let thread = Thread { [self] in
      self.runMainloop()
    }
    thread.name = "OpenConnectKit.mainloop"
    thread.qualityOfService = .userInitiated
    mainloopThread = thread
    thread.start()
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
  /// It should only be called from the dedicated mainloop thread.
  /// The mainloop exits when a cancel command is sent via the command pipe.
  private func runMainloop() {
    defer {
      cleanup()
      onMainloopFinished?()
    }

    guard let vpnInfo = vpnInfo else {
      updateStatus(.disconnected(error: .notInitialized))
      return
    }
    var ret: Int32 = 0
    while ret == 0 {
      // Run the OpenConnect mainloop
      // This blocks until the connection ends or is cancelled via command pipe
      ret = openconnect_mainloop(
        vpnInfo,
        configuration.reconnectTimeout,
        configuration.reconnectInterval
      )
      if ret == 0 {
        if case .disconnecting = connectionStatus { break }
        updateStatus(.reconnecting)
      }
    }

    // Determine the disconnect reason based on return value and current status
    switch connectionStatus {
    case .disconnecting:
      updateStatus(.disconnected(error: nil))
    default:
      let error: VpnError? = ret < 0
        ? .connectionFailed(reason: "Connection lost")
        : nil
      updateStatus(.disconnected(error: error))
    }
  }
}
