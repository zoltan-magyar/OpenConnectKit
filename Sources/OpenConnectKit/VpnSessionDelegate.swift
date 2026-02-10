//
//  VpnSessionDelegate.swift
//  OpenConnectKit
//
//  Delegate protocols for VPN session event handling
//

import Foundation

/// Protocol for handling critical VPN session events.
///
/// Implement this protocol to receive callbacks about connection lifecycle,
/// authentication requests, and certificate validation.
///
/// **Thread Safety**: All delegate methods may be called on background threads.
/// If you need to update UI, dispatch to the main queue:
///
/// ```swift
/// func vpnSession(_ session: VpnSession, didChangeStatus status: ConnectionStatus) {
///     DispatchQueue.main.async {
///         // Update UI here
///     }
/// }
/// ```
///
/// ## Example Implementation
///
/// ```swift
/// class MyVpnHandler: VpnSessionDelegate {
///     func vpnSession(_ session: VpnSession, didChangeStatus status: ConnectionStatus) {
///         print("Status changed to: \(status)")
///     }
///
///     func vpnSession(_ session: VpnSession, requiresAuthentication form: AuthenticationForm) -> AuthenticationForm {
///         var filledForm = form
///         // Fill in authentication fields
///         return filledForm
///     }
///
///     func vpnSession(_ session: VpnSession, shouldAcceptCertificate info: CertificateInfo) -> Bool {
///         // Validate certificate
///         return true
///     }
/// }
/// ```
public protocol VpnSessionDelegate: AnyObject {

  // MARK: - Required Methods

  /// Called when the connection status changes.
  ///
  /// This method is invoked whenever the VPN connection transitions between states,
  /// such as connecting, connected, disconnected, or reconnecting.
  ///
  /// - Parameters:
  ///   - session: The VPN session reporting the status change
  ///   - status: The new connection status
  func vpnSession(_ session: VpnSession, didChangeStatus status: ConnectionStatus)

  /// Called when the VPN server requires authentication.
  ///
  /// The delegate should fill in the authentication form fields and return it.
  /// The form may contain username, password, and other authentication fields
  /// depending on the server's requirements.
  ///
  /// **Important**: This method is called synchronously and blocks the VPN
  /// connection process until a form is returned. Perform authentication
  /// promptly to avoid timeouts.
  ///
  /// - Parameters:
  ///   - session: The VPN session requesting authentication
  ///   - form: The authentication form to fill
  /// - Returns: The authentication form with filled field values
  func vpnSession(
    _ session: VpnSession,
    requiresAuthentication form: AuthenticationForm
  ) -> AuthenticationForm

  /// Called when the server's certificate needs validation.
  ///
  /// Return `true` to accept the certificate and proceed with the connection,
  /// or `false` to reject it and abort the connection.
  ///
  /// This is typically called when:
  /// - The certificate is self-signed
  /// - The certificate hostname doesn't match
  /// - The certificate chain cannot be verified
  ///
  /// **Important**: This method is called synchronously and blocks the VPN
  /// connection process. Return promptly to avoid timeouts.
  ///
  /// - Parameters:
  ///   - session: The VPN session requesting validation
  ///   - info: Information about the certificate requiring validation
  /// - Returns: `true` to accept the certificate, `false` to reject
  func vpnSession(
    _ session: VpnSession,
    shouldAcceptCertificate info: CertificateInfo
  ) -> Bool
}

/// Optional protocol for non-critical VPN session events.
///
/// Implement this protocol if you need to receive log messages or
/// traffic statistics from the VPN session.
///
/// **Thread Safety**: All delegate methods may be called on background threads.
///
/// ## Example Implementation
///
/// ```swift
/// class MyVpnLogger: VpnSessionLoggingDelegate {
///     func vpnSession(_ session: VpnSession, didLog message: String, level: LogLevel) {
///         print("[\(level)] \(message)")
///     }
///
///     func vpnSession(_ session: VpnSession, didReceiveStats stats: VpnStats) {
///         print("TX: \(stats.formattedTxBytes), RX: \(stats.formattedRxBytes)")
///     }
/// }
/// ```
public protocol VpnSessionLoggingDelegate: AnyObject {

  /// Called when the VPN session generates a log message.
  ///
  /// Log messages include diagnostic information, connection progress,
  /// and error details from the underlying OpenConnect library.
  ///
  /// - Parameters:
  ///   - session: The VPN session generating the log
  ///   - message: The log message
  ///   - level: The severity level of the message
  func vpnSession(_ session: VpnSession, didLog message: String, level: LogLevel)

  /// Called when traffic statistics are available.
  ///
  /// Statistics are delivered in response to `requestStats()` calls or
  /// periodically if configured. They include cumulative byte and packet
  /// counts for transmitted and received data.
  ///
  /// - Parameters:
  ///   - session: The VPN session reporting statistics
  ///   - stats: The current traffic statistics
  func vpnSession(_ session: VpnSession, didReceiveStats stats: VpnStats)
}
