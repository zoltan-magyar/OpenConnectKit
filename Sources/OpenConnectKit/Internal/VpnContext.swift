//
//  VpnContext.swift
//  OpenConnectKit
//
//  Internal wrapper around OpenConnect C API
//

import COpenConnect
import Foundation

#if os(Windows)
  import WinSDK
#endif

// Internal context managing OpenConnect C API
//
// This is a class (not actor) because C callbacks require synchronous access
// to properties. The @unchecked Sendable conformance acknowledges that we're
// managing thread safety manually through the C library's threading model.
//
// VpnContext is fully decoupled from VpnSession — it communicates via closures.
// This allows VpnSession to be @MainActor-isolated while VpnContext runs on
// background threads.
internal final class VpnContext: @unchecked Sendable {
  // MARK: - Properties

  // Properties accessed from C callbacks must be nonisolated(unsafe)
  // Thread safety is managed by OpenConnect's internal threading model

  /// Connection status - accessed from callbacks and mainloop
  nonisolated(unsafe) internal var connectionStatus: ConnectionStatus = .disconnected(error: nil)

  /// OpenConnect vpninfo structure - managed by C library
  nonisolated(unsafe) internal var vpnInfo: OpaquePointer!

  /// Stored configuration for access during connection and mainloop
  internal let configuration: VpnConfiguration

  // Command pipe for controlling mainloop (OC_CMD_*)
  #if os(Windows)
    nonisolated(unsafe) internal var cmdFd: SOCKET!
  #else
    nonisolated(unsafe) internal var cmdFd: Int32!
  #endif

  /// Mainloop thread handle
  nonisolated(unsafe) internal var mainloopThread: Thread?

  // MARK: - Closure Callbacks

  /// Called when authentication is required. Blocks the C thread until resolved.
  nonisolated(unsafe) internal var onAuth: ((AuthenticationForm) -> AuthenticationForm)?

  /// Called when certificate validation is needed. Blocks the C thread until resolved.
  nonisolated(unsafe) internal var onCert: ((CertificateInfo) -> Bool)?

  /// Called when a log message is received from the C library.
  nonisolated(unsafe) internal var onLog: ((LogLevel, String) -> Void)?

  /// Called when the connection status changes.
  nonisolated(unsafe) internal var onStatus: ((ConnectionStatus) -> Void)?

  /// Called when traffic statistics are received.
  nonisolated(unsafe) internal var onStats: ((VpnStats) -> Void)?

  /// Called when the mainloop finishes and context is cleaned up.
  nonisolated(unsafe) internal var onMainloopFinished: (() -> Void)?

  // MARK: - Command Types

  internal enum Command: UInt8 {
    case cancel = 0x78  // 'x'
    case pause = 0x70  // 'p'
    case detach = 0x64  // 'd'
    case stats = 0x73  // 's'
  }

  // MARK: - Initialization

  /// Creates a VPN context.
  ///
  /// This initializes the OpenConnect library, parses the server URL, sets up
  /// the command pipe for mainloop control, and registers callback handlers.
  ///
  /// - Parameter configuration: The VPN configuration for this connection
  /// - Throws: `VpnError` if initialization fails
  init(configuration: VpnConfiguration) throws {
    self.configuration = configuration

    // Create OpenConnect vpninfo structure with callbacks
    // Pass VpnContext (self) as privdata since it manages the OpenConnect resources
    guard
      let vpnInfo = openconnect_vpninfo_new(
        "AnyConnect Compatible OpenConnectKit Client",
        validatePeerCertCallback,
        nil,
        processAuthFormCallback,
        get_progress_shim_callback(),
        Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      throw VpnError.notInitialized
    }

    self.vpnInfo = vpnInfo

    // Configure log level
    openconnect_set_loglevel(vpnInfo, configuration.logLevel.openConnectLevel)

    // Parse and validate server URL
    let ret = openconnect_parse_url(vpnInfo, configuration.serverURL.absoluteString)
    if ret != 0 {
      openconnect_vpninfo_free(vpnInfo)
      self.vpnInfo = nil
      throw VpnError.invalidConfiguration(reason: "Failed to parse server URL")
    }

    // Set up command pipe for controlling the mainloop
    let cmdFdResult = openconnect_setup_cmd_pipe(vpnInfo)
    #if os(Windows)
      if cmdFdResult == INVALID_SOCKET {
        openconnect_vpninfo_free(vpnInfo)
        self.vpnInfo = nil
        throw VpnError.cmdPipeSetupFailed
      }
    #else
      if cmdFdResult < 0 {
        openconnect_vpninfo_free(vpnInfo)
        self.vpnInfo = nil
        throw VpnError.cmdPipeSetupFailed
      }
    #endif
    self.cmdFd = cmdFdResult

    // Register callback handlers
    openconnect_set_reconnected_handler(vpnInfo, reconnectedCallback)
    openconnect_set_stats_handler(vpnInfo, statsCallback)
  }

  deinit {
    cleanup()
  }

  // MARK: - Cleanup

  /// Cleans up OpenConnect resources.
  ///
  /// This method is safe to call multiple times.
  /// Note: The mainloop must be stopped via command pipe before calling this.
  internal func cleanup() {
    // Clear thread reference (mainloop should already be stopped via command pipe)
    mainloopThread = nil

    // Free OpenConnect resources
    if vpnInfo != nil {
      openconnect_vpninfo_free(vpnInfo)
      vpnInfo = nil
    }

    // Reset command pipe
    #if os(Windows)
      cmdFd = INVALID_SOCKET
    #else
      cmdFd = -1
    #endif
  }

  // MARK: - Computed Properties

  internal var isCmdPipeReady: Bool {
    #if os(Windows)
      return cmdFd != nil && cmdFd != INVALID_SOCKET
    #else
      return cmdFd != nil && cmdFd >= 0
    #endif
  }

  internal var assignedInterfaceName: String? {
    guard let vpnInfo = vpnInfo else {
      return nil
    }

    guard let ifnamePtr = openconnect_get_ifname(vpnInfo) else {
      return nil
    }

    return String(cString: ifnamePtr)
  }
}
