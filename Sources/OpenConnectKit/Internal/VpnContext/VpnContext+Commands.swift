//
//  VpnContext+Commands.swift
//  OpenConnectKit
//
//  Command sending extension for VpnContext
//

import COpenConnect
import Foundation

// MARK: - Command Sending

extension VpnContext {
  /// Cancels the connection, whatever stage it's in. Safe to call from any thread.
  ///
  /// While connecting, openconnect also watches the command pipe during network I/O, so this
  /// aborts authentication too. An auth form or certificate prompt that is waiting for the
  /// user still has to be answered first. Once established, the mainloop logs off and exits.
  func cancel() {
    callbacks.markCancelled()
    sendCommand(.cancel)
  }

  /// Asks the mainloop for traffic statistics, which arrive through `callbacks.stats`.
  func requestStats() {
    sendCommand(.stats)
  }

  /// Writes a command byte to openconnect's command pipe.
  ///
  /// The pipe stays open until `deinit`, so this is safe even after the connection has ended:
  /// the byte is simply never read.
  private func sendCommand(_ command: Command) {
    var byte = command.rawValue
    // Nonblocking, and only ever holds a few bytes, so a failed write isn't worth reporting.
    _ = write(commandPipe, &byte, 1)
  }
}
