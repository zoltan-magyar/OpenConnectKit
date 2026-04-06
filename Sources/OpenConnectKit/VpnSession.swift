//
//  VpnSession.swift
//  OpenConnectKit
//
//  Main public API for VPN sessions
//

import Foundation

/// Manages VPN connections using the OpenConnect protocol.
///
/// `VpnSession` provides a Swift-native API for establishing and managing
/// OpenConnect VPN connections. All C interop is handled internally, exposing
/// a clean, type-safe interface.
///
/// **Thread Safety**: Delegate methods may be invoked on background threads.
/// Use `DispatchQueue.main.async` when updating UI.
///
/// ## Example Usage
///
/// ```swift
/// class MyHandler: VpnSessionDelegate {
///     func vpnSession(_ session: VpnSession, didChangeStatus status: ConnectionStatus) {
///         print("Status: \(status)")
///     }
///
///     func vpnSession(_ session: VpnSession, requiresAuthentication form: AuthenticationForm) -> AuthenticationForm {
///         var filledForm = form
///         // Fill in authentication fields
///         return filledForm
///     }
///
///     func vpnSession(_ session: VpnSession, shouldAcceptCertificate info: CertificateInfo) -> Bool {
///         return true
///     }
/// }
///
/// let config = VpnConfiguration(serverURL: URL(string: "https://vpn.example.com")!)
/// let handler = MyHandler()
/// let session = VpnSession(configuration: config, delegate: handler)
/// try session.connect()
/// ```
public class VpnSession {
  // MARK: - Public Properties

  /// The configuration for this VPN session.
  public let configuration: VpnConfiguration

  /// The current connection status of the VPN session.
  ///
  /// This property provides detailed information about the connection state,
  /// including any errors that caused disconnection and progress messages
  /// during connection establishment.
  ///
  /// Use the delegate's `vpnSession(_:didChangeStatus:)` method to receive
  /// real-time updates when the status changes.
  public var connectionStatus: ConnectionStatus {
    return context?.connectionStatus ?? .disconnected(error: nil)
  }

  /// The name of the network interface assigned to the VPN tunnel.
  ///
  /// This property returns the interface name (e.g., "tun0", "utun0") after
  /// the TUN device has been successfully set up. Returns `nil` before connection
  /// or if the TUN device hasn't been configured yet.
  ///
  /// **Important**: The interface name becomes available only when the connection
  /// status changes to `.connected`. During the `connect()` call, the TUN device
  /// setup happens asynchronously in a background thread. To access the interface
  /// name reliably, wait for the delegate to report `.connected` status.
  ///
  /// ## Example Usage
  ///
  /// ```swift
  /// func vpnSession(_ session: VpnSession, didChangeStatus status: ConnectionStatus) {
  ///     if case .connected = status {
  ///         if let ifname = session.interfaceName {
  ///             print("Interface: \(ifname)")
  ///         }
  ///     }
  /// }
  /// ```
  public var interfaceName: String? {
    return context?.assignedInterfaceName
  }

  // MARK: - Delegate Properties

  /// The primary delegate for connection lifecycle events.
  ///
  /// This delegate receives critical events including status changes,
  /// authentication requests, and certificate validation.
  ///
  /// **Required**: You must set this delegate to receive connection events
  /// and handle authentication. The delegate is not retained (weak reference)
  /// to prevent retain cycles.
  public weak var delegate: VpnSessionDelegate?

  /// Optional delegate for logging and statistics.
  ///
  /// Set this delegate if you want to receive log messages and traffic
  /// statistics. Unlike the primary delegate, this is optional and can
  /// be left unset if logging is not needed.
  ///
  /// The delegate is not retained (weak reference) to prevent retain cycles.
  public weak var loggingDelegate: VpnSessionLoggingDelegate?

  // MARK: - Internal Properties

  /// Internal context managing the OpenConnect connection.
  internal private(set) var context: VpnContext?

  // MARK: - Initialization

  /// Creates a new VPN session with the given configuration and delegate.
  ///
  /// - Parameters:
  ///   - configuration: The VPN configuration
  ///   - delegate: The delegate to receive connection events
  public init(configuration: VpnConfiguration, delegate: VpnSessionDelegate) {
    self.configuration = configuration
    self.delegate = delegate
  }

  deinit {
    disconnect()
  }

  // MARK: - Public Methods

  /// Connects to the VPN server.
  ///
  /// This method performs the following steps:
  /// 1. Parses the server URL
  /// 2. Obtains an authentication cookie (may trigger delegate authentication callback)
  /// 3. Establishes the CSTP connection
  /// 4. Sets up DTLS for the data channel
  /// 5. Starts the mainloop on a background thread
  ///
  /// The delegate's `vpnSession(_:didChangeStatus:)` method will be called
  /// throughout the connection process to report progress.
  ///
  /// If authentication is required, the delegate's
  /// `vpnSession(_:requiresAuthentication:)` method will be called synchronously.
  ///
  /// If certificate validation is needed, the delegate's
  /// `vpnSession(_:shouldAcceptCertificate:)` method will be called synchronously.
  ///
  /// - Throws: `VpnError` if connection fails at any step
  public func connect() throws {
    guard case .disconnected = connectionStatus else {
      throw VpnError.alreadyConnected
    }

    // Create context if needed
    if context == nil {
      context = try VpnContext(session: self)
    }

    try context?.connect()
  }

  /// Disconnects from the VPN server.
  ///
  /// This method gracefully shuts down the VPN connection and cleans up
  /// resources. After disconnection, the delegate's `vpnSession(_:didChangeStatus:)`
  /// method will be called with a `.disconnected` status.
  ///
  /// This method is safe to call multiple times and will be automatically
  /// called when the session is deallocated.
  public func disconnect() {
    // Only proceed if NOT already disconnected
    if case .disconnected = connectionStatus {
      return
    }
    if case .disconnecting = connectionStatus {
      return
    }

    context?.disconnect()
  }

  /// Requests traffic statistics from the VPN connection.
  ///
  /// This method sends a command to the mainloop to gather and report
  /// current traffic statistics. If a logging delegate is set, the statistics
  /// will be delivered via the `vpnSession(_:didReceiveStats:)` method.
  ///
  /// Statistics include:
  /// - Bytes sent/received
  /// - Packets sent/received
  ///
  /// The statistics are cumulative since the connection was established.
  ///
  /// - Returns: `true` if the request was sent successfully, `false` if not connected
  @discardableResult
  public func requestStats() -> Bool {
    guard case .connected = connectionStatus else {
      return false
    }

    return context?.requestStats() ?? false
  }

  // MARK: - Internal Methods

  /// Handles progress logging from OpenConnect.
  ///
  /// This is called by the internal context when log messages are received
  /// from the OpenConnect library.
  ///
  /// - Parameters:
  ///   - level: The log level
  ///   - message: The log message
  internal func handleProgress(level: LogLevel, message: String) {
    loggingDelegate?.vpnSession(self, didLog: message, level: level)
  }

  /// Handles certificate validation requests from OpenConnect.
  ///
  /// This is called by the internal context when a server certificate needs
  /// validation. The delegate's response determines whether the connection proceeds.
  ///
  /// - Parameter certInfo: Information about the certificate
  /// - Returns: `true` to accept the certificate, `false` to reject
  internal func handleCertificateValidation(certInfo: CertificateInfo) -> Bool {
    guard let delegate = delegate else {
      // No delegate - fall back to configuration setting
      return configuration.allowInsecureCertificates
    }

    return delegate.vpnSession(self, shouldAcceptCertificate: certInfo)
  }

  /// Handles authentication form requests from OpenConnect.
  ///
  /// This is called by the internal context when the server requires authentication.
  /// The delegate must fill in the form fields and return it.
  ///
  /// - Parameter form: The authentication form to fill
  /// - Returns: The filled authentication form
  internal func handleAuthenticationForm(_ form: AuthenticationForm) -> AuthenticationForm {
    guard let delegate = delegate else {
      // No delegate - return the form unchanged
      // This will likely cause authentication to fail, but that's expected
      // if the delegate wasn't set properly
      return form
    }

    return delegate.vpnSession(self, requiresAuthentication: form)
  }

  /// Handles statistics notification from OpenConnect.
  ///
  /// This is called by the internal context when statistics are received
  /// from the mainloop in response to a `requestStats()` call.
  ///
  /// - Parameter stats: The VPN traffic statistics
  internal func handleStats(_ stats: VpnStats) {
    loggingDelegate?.vpnSession(self, didReceiveStats: stats)
  }

  /// Handles connection status changes from OpenConnect.
  ///
  /// This is called by the internal context whenever the connection status changes.
  /// The delegate is notified of the status change.
  ///
  /// - Parameter status: The new connection status
  internal func handleStatusChange(status: ConnectionStatus) {
    delegate?.vpnSession(self, didChangeStatus: status)
  }

  /// Releases the active context after its mainloop has fully stopped.
  ///
  /// - Parameter context: The context whose mainloop finished
  internal func handleMainloopFinished(for context: VpnContext) {
    guard self.context === context else {
      return
    }

    self.context = nil
  }
}
