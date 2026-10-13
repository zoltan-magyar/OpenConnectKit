//
//  OpenConnectContext+VpncScript.swift
//  OpenConnectKit
//
//  TUN setup by openconnect, with a vpnc-script
//

import COpenConnect
import Foundation

// Everything that uses vpnc-script is in this file. It stays as one of two tunnel modes
// (decided 2026-10-11): vpnc-script for processes running as root (command-line tools, helpers,
// later Linux), the Network Extension for sandboxed apps. Plan step 6.6 reworks it: the setup
// moves into openconnect's provide-tun handler, inside the mainloop (here it still runs before
// the mainloop, too early for GlobalProtect ESP and PPP-based protocols), `vpncScript` and
// `interfaceName` move from `VPNConfiguration` into the mode, and the bundled script moves into
// its own product.

extension OpenConnectContext {
  /// Sets up the TUN device for the VPN connection.
  ///
  /// This finds the vpnc-script and configures the TUN device.
  /// Must be called after DTLS setup and before starting the mainloop.
  ///
  /// - Throws: `VPNError` if TUN setup fails
  internal func setupTunDevice() throws(VPNError) {
    guard let vpncScriptPath = findVpncScript() else {
      throw .networkConfigurationFailed(reason: "vpnc-script not found, or not executable")
    }

    // openconnect copies both strings, so Swift's temporary C strings are enough.
    guard
      openconnect_setup_tun_device(vpnInfo, vpncScriptPath, configuration.interfaceName) == 0
    else {
      throw .networkConfigurationFailed(
        reason: errorMessage(or: "Could not set up the tunnel interface"))
    }
  }

  /// Finds the vpnc-script executable.
  ///
  /// Uses the configured path if explicitly set, otherwise uses the bundled script.
  ///
  /// - Returns: The path to the vpnc-script, or `nil` if not found
  private func findVpncScript() -> String? {
    if let configuredPath = configuration.vpncScript {
      guard FileManager.default.isExecutableFile(atPath: configuredPath) else {
        return nil
      }
      return configuredPath
    }

    return bundledVpncScriptPath()
  }

  private func bundledVpncScriptPath() -> String? {
    guard let url = Bundle.module.url(forResource: "vpnc-script", withExtension: nil),
      FileManager.default.isExecutableFile(atPath: url.path)
    else {
      return nil
    }
    return url.path
  }
}
