//
//  OpenConnectContext+Mainloop.swift
//  OpenConnectKit
//
//  Mainloop management extension for OpenConnectContext
//

import COpenConnect
import Foundation

// MARK: - Mainloop Management

extension OpenConnectContext {
  /// Runs openconnect's mainloop on the connection thread until the connection ends.
  ///
  /// The mainloop handles all VPN traffic, and reconnects by itself when the connection drops,
  /// for up to `reconnectTimeout`. It calls `reconnectingCallback` before each attempt and
  /// `reconnectedCallback` once one succeeds.
  ///
  /// - Returns: Why the connection ended, or `nil` if it ended because of `cancel()`.
  internal func runMainloop() -> VPNError? {
    state.clearErrorMessages()

    var ret: CInt
    repeat {
      // Returns 0 only after OC_CMD_PAUSE, which asks to be called again. We never pause, but
      // honour it anyway.
      ret = openconnect_mainloop(
        vpnInfo,
        configuration.reconnectTimeout.wholeSeconds,
        configuration.reconnectInterval.wholeSeconds
      )
    } while ret == 0

    // Our own decisions come first; openconnect's result is then only a consequence of them.
    // That covers cancel() (-EINTR), which isn't a failure, and a certificate rejected when the
    // server presents a different one on reconnect (also -EINTR: the certificate callback stops
    // the reconnect with a cancel command).
    if let userAbort {
      return userAbort == .cancelled ? nil : userAbort
    }

    // Like most of openconnect's API, the mainloop returns a negative POSIX error code; the
    // values are documented above openconnect_mainloop() in mainloop.c.
    switch POSIXErrorCode(rawValue: -ret) {
    case .EPIPE?, .EPERM?:
      // The server ended the session, or no longer accepts the cookie when reconnecting, for
      // example because it expired.
      return .sessionEnded
    default:
      // The most recent message, unlike the connection steps: over a long session, the first
      // one may be from an earlier hiccup that has nothing to do with the end.
      return .connectionLost(
        reason: state.lastErrorMessage ?? String(cString: strerror(-ret)))
    }
  }
}

extension Duration {
  /// The whole seconds openconnect's C API takes, clamped to `CInt`.
  fileprivate var wholeSeconds: CInt {
    CInt(clamping: components.seconds)
  }
}
