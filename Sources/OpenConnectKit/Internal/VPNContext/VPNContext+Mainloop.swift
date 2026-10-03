//
//  VPNContext+Mainloop.swift
//  OpenConnectKit
//
//  Mainloop management extension for VPNContext
//

import COpenConnect
import Foundation

// MARK: - Mainloop Management

extension VPNContext {
  /// Runs openconnect's mainloop on the connection thread until the connection ends.
  ///
  /// The mainloop handles all VPN traffic, and reconnects by itself when the connection drops,
  /// for up to `reconnectTimeout`. Each successful reconnect calls `reconnectedCallback`; there
  /// is no callback for when a reconnect starts.
  ///
  /// - Returns: Why the connection ended, or `nil` if it ended because of `cancel()`.
  internal func runMainloop() -> VPNError? {
    callbacks.clearErrorMessages()

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

    // A cancellation isn't a failure. A certificate can also be rejected here, when the server
    // presents a different one on reconnect.
    switch userAbort {
    case .cancelled?: return nil
    case let error?: return error
    case nil: break
    }

    switch -ret {
    case EINTR, ECONNABORTED:  // OC_CMD_CANCEL, OC_CMD_DETACH
      return nil
    case EPERM:  // e.g. "Cookie is no longer valid" when reconnecting
      return .sessionEnded
    default:
      // The most recent message, unlike the connection steps: over a long session, the first
      // one may be from an earlier hiccup that has nothing to do with the end.
      return .connectionLost(
        reason: callbacks.lastErrorMessage ?? String(cString: strerror(-ret)))
    }
  }
}
