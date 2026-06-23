//
//  VpnSessionDelegate.swift
//  OpenConnectKit
//
//  Delegate protocol for interactive VPN session events
//

import Foundation

/// Protocol for handling interactive VPN session events.
///
/// Implement this protocol to handle authentication requests and
/// certificate validation. Both methods are `async`, allowing GUI
/// consumers to present sheets and await user input.
///
/// ## Example Implementation
///
/// ```swift
/// class MyVpnHandler: VpnSessionDelegate {
///     func vpnSession(
///         _ session: VpnSession,
///         requiresAuthentication form: AuthenticationForm
///     ) async -> AuthenticationForm? {
///         // Present auth sheet, wait for user to fill and submit, or nil to cancel
///         return await showAuthSheet(form)
///     }
///
///     func vpnSession(
///         _ session: VpnSession,
///         shouldAcceptCertificate info: CertificateInfo
///     ) async -> Bool {
///         // Show certificate warning dialog
///         return await showCertDialog(info)
///     }
/// }
/// ```
@MainActor
public protocol VpnSessionDelegate: AnyObject {

  /// Called when the VPN server requires authentication.
  ///
  /// The delegate should fill in the authentication form fields and return it,
  /// or return `nil` to cancel the connection.
  /// This method is `async` to support presenting UI and awaiting user input.
  ///
  /// - Parameters:
  ///   - session: The VPN session requesting authentication
  ///   - form: The authentication form to fill
  /// - Returns: The filled authentication form, or `nil` to cancel
  func vpnSession(
    _ session: VpnSession,
    requiresAuthentication form: AuthenticationForm
  ) async -> AuthenticationForm?

  /// Called when the server's certificate needs validation.
  ///
  /// Return `true` to accept the certificate and proceed with the connection,
  /// or `false` to reject it and abort the connection.
  ///
  /// This method is `async` to support presenting a confirmation dialog
  /// and awaiting the user's decision.
  ///
  /// - Parameters:
  ///   - session: The VPN session requesting validation
  ///   - info: Information about the certificate requiring validation
  /// - Returns: `true` to accept the certificate, `false` to reject
  func vpnSession(
    _ session: VpnSession,
    shouldAcceptCertificate info: CertificateInfo
  ) async -> Bool
}
