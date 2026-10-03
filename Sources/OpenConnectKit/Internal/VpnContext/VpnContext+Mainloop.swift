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
  /// Runs openconnect's mainloop on the connection thread until the connection ends.
  ///
  /// The mainloop handles all VPN traffic, and reconnects by itself when the connection drops,
  /// for up to `reconnectTimeout`. Each successful reconnect calls `reconnectedCallback`; there
  /// is no callback for when a reconnect starts.
  ///
  /// - Returns: Why the connection ended, or `nil` if it ended because of `cancel()`.
  func runMainloop() -> VpnError? {
    var ret: CInt
    repeat {
      // Returns 0 only after OC_CMD_PAUSE, which asks to be called again. We never pause, but
      // honour it anyway.
      ret = openconnect_mainloop(
        vpnInfo,
        configuration.reconnectTimeout,
        configuration.reconnectInterval
      )
    } while ret == 0

    if isCancelled { return nil }

    switch -ret {
    case EINTR, ECONNABORTED:  // OC_CMD_CANCEL, OC_CMD_DETACH
      return nil
    case EPERM:  // e.g. "Cookie is no longer valid" when reconnecting
      return .connectionFailed(reason: "The VPN session expired or was ended by the server")
    default:
      return .connectionFailed(reason: "Connection lost (\(String(cString: strerror(-ret))))")
    }
  }
}
