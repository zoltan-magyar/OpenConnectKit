//
//  VPNSessionDelegate.swift
//  OpenConnectKit
//
//  Delegate protocol for interactive VPN session events
//

import Foundation

/// What a `VPNSession` needs from its delegate: answers to the prompts that come up while
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
///         guard case .untrusted(let reason) = info.systemTrust else { return true }
///         return await readLine(prompt: "\(reason). Connect anyway? [y/N]") == "y"
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

  /// Called with the server's certificate, to decide whether to connect to it.
  ///
  /// It's called for every server certificate, trusted or not. `info.systemTrust` says whether
  /// the system trusts the certificate for the server's host name, with the system's trust
  /// settings and the user's own (such as a company root marked "Always Trust" in Keychain
  /// Access). The decision is yours: accepting what the system trusts and asking the user about
  /// the rest is the usual choice, and what `VPNPrompts` does. Pinning or always showing the
  /// certificate are others.
  ///
  /// Your answer holds for the rest of the connection. During one connection the session can
  /// open several TLS connections to the server: to log in, for each attempt to re-establish a
  /// lost connection, and with some protocols to log off. A certificate you accepted is accepted
  /// again without asking when the same server (host name and port) presents it and
  /// `info.systemTrust` hasn't changed, so re-establishing a lost connection doesn't wait for you.
  /// Certificates count as the same when their public keys are, which is what `info.pin`
  /// identifies. You're asked again about a different certificate, another server, or a changed
  /// verdict, such as a certificate that expired during the connection. Each `connect` starts
  /// afresh; to remember decisions across connections, store the pin (see `CertificateInfo.pin`).
  ///
  /// Return `true` to accept the certificate and proceed with the connection,
  /// or `false` to reject it, which ends the connection attempt, or the connection if it's being
  /// re-established, with `VPNError.certificateRejected`. After a rejection you aren't asked
  /// again until the next `connect`.
  ///
  /// - Parameters:
  ///   - session: The VPN session requesting validation
  ///   - info: The server's certificate and the system's verdict on it
  /// - Returns: `true` to accept the certificate, `false` to reject
  func vpnSession(
    _ session: VPNSession,
    shouldAcceptCertificate info: CertificateInfo
  ) async -> Bool
}
