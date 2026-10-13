//
//  OpenConnectContext+Commands.swift
//  OpenConnectKit
//
//  Command sending extension for OpenConnectContext
//

import COpenConnect
import Foundation

// MARK: - Command Sending

extension OpenConnectContext {
  /// Cancels the connection, whatever stage it's in. Safe to call from any thread.
  ///
  /// While connecting, openconnect also watches the command pipe during network I/O, so this
  /// aborts authentication too. An auth form or certificate prompt that is waiting for the
  /// user still has to be answered first. Once established, the mainloop logs off and exits.
  internal func cancel() {
    state.markCancelled()
    Command.cancel.send(to: commandPipe)
  }

  /// Asks the mainloop for traffic statistics, which arrive through the delegate's
  /// `didReceive(_:)`.
  internal func requestStats() {
    Command.stats.send(to: commandPipe)
  }
}
