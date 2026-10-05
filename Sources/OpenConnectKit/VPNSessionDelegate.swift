//
//  VPNSessionDelegate.swift
//  OpenConnectKit
//
//  Delegate protocol for interactive VPN session events
//

import Foundation

/// What a `VPNSession` needs from its owner: answers to the prompts that come up while
/// connecting.
///
/// Both methods are `async`, so an implementation can present UI and wait for the user. For
/// SwiftUI, `VPNPrompts` is a ready-made implementation that publishes the pending prompt as
/// observable state; implement the protocol yourself for anything else, such as a command-line
/// tool.
///
/// The session keeps a strong reference to its delegate. The delegate gets the session as a
/// parameter, so it shouldn't need to keep one of its own; if it does, make it `weak` to avoid a
/// reference cycle.
///
/// ## Cancellation
///
/// If the connection attempt is cancelled while a method is waiting (by `disconnect()`, or by
/// cancelling the task that called `connect`), the task running the method is cancelled. Return
/// promptly when that happens, for example with `withTaskCancellationHandler`; whatever you
/// return then is ignored.
///
/// ## Example Implementation
///
/// ```swift
/// struct TerminalPrompts: VPNSessionDelegate {
///     func vpnSession(
///         _ session: VPNSession,
///         requiresAuthentication form: AuthenticationForm
///     ) async -> AuthenticationForm? {
///         var form = form
///         for index in form.fields.indices {
///             if case .hidden = form.fields[index].kind { continue }
///             guard let answer = await readLine(prompt: form.fields[index].label) else {
///                 return nil  // cancel
///             }
///             form.fields[index].value = answer
///         }
///         return form
///     }
///
///     func vpnSession(
///         _ session: VPNSession,
///         shouldAcceptCertificate info: CertificateInfo
///     ) async -> Bool {
///         await readLine(prompt: "\(info.reason). Connect anyway? [y/N]") == "y"
///     }
/// }
/// ```
@MainActor
public protocol VPNSessionDelegate {
  /// Called when the VPN server requires authentication.
  ///
  /// Fill in the form's fields and return it, or return `nil` to cancel the connection.
  /// The server may send several forms in a row, for example a password form followed by a
  /// one-time code.
  ///
  /// - Parameters:
  ///   - session: The VPN session requesting authentication
  ///   - form: The authentication form to fill
  /// - Returns: The filled authentication form, or `nil` to cancel
  func vpnSession(
    _ session: VPNSession,
    requiresAuthentication form: AuthenticationForm
  ) async -> AuthenticationForm?

  /// Called when the server's certificate couldn't be verified, for example because it's
  /// self-signed or doesn't match the host name.
  ///
  /// Return `true` to accept the certificate and proceed with the connection,
  /// or `false` to reject it, which ends the attempt with `VPNError.certificateRejected`.
  ///
  /// - Parameters:
  ///   - session: The VPN session requesting validation
  ///   - info: Information about the certificate requiring validation
  /// - Returns: `true` to accept the certificate, `false` to reject
  func vpnSession(
    _ session: VPNSession,
    shouldAcceptCertificate info: CertificateInfo
  ) async -> Bool
}
