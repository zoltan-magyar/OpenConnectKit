//
//  VpnContext+Commands.swift
//  OpenConnectKit
//
//  Command sending extension for VpnContext
//

import COpenConnect
import Foundation

#if os(Windows)
  import WinSDK
#endif

// MARK: - Command Sending

extension VpnContext {
  /// Sends a command byte to the mainloop via the command pipe.
  ///
  /// This is used to control the mainloop from other threads.
  /// Commands include cancel, pause, detach, and stats request.
  ///
  /// - Parameter command: The command to send
  /// - Returns: `true` if the command was sent successfully, `false` otherwise
  @discardableResult
  internal func sendCommand(_ command: Command) -> Bool {
    guard isCmdPipeReady else {
      return false
    }

    var commandByte = command.rawValue

    #if os(Windows)
      // Windows: Use send() for socket
      let result = send(cmdFd, &commandByte, 1, 0)
      return result == 1
    #else
      // Unix/Linux/macOS: Use write() for file descriptor
      let result = write(cmdFd, &commandByte, 1)
      return result == 1
    #endif
  }

  /// Requests traffic statistics from the mainloop.
  ///
  /// The stats will be delivered via the stats callback, which in turn
  /// calls the session's logging delegate.
  ///
  /// - Returns: `true` if the request was sent successfully, `false` otherwise
  @discardableResult
  internal func requestStats() -> Bool {
    return sendCommand(.stats)
  }
}
