//
//  OpenConnectContextDelegate.swift
//  OpenConnectKit
//
//  What an OpenConnectContext needs from its delegate
//

import Foundation

/// What an `OpenConnectContext` needs from its delegate: answers to openconnect's questions, and
/// a place for its logs and statistics. The delegate is normally the context's owner, the object
/// that created it (`VPNSession` today).
///
/// The context calls these on its connection thread, synchronously, from inside openconnect's C
/// callbacks (`OpenConnectCallbacks.swift`). The two questions block that thread until they have
/// an answer, which is what openconnect needs; a delegate that has to ask someone asynchronously
/// waits for the answer there. That's fine on the connection thread, never on Swift's pool.
///
/// The questions use the same words as the public `VPNSessionDelegate`, so searching for one
/// finds every layer it passes through.
///
/// The context holds its delegate weakly, because its owner holds the context. Without a
/// delegate, it cancels the login and rejects the certificate.
internal protocol OpenConnectContextDelegate: AnyObject, Sendable {
  /// The server sent a login form. Return it filled in, or `nil` to cancel the connection.
  func requiresAuthentication(_ form: AuthenticationForm) -> AuthenticationForm?

  /// Return `true` to accept the server's certificate. `info.systemTrust` has the system's
  /// verdict; the decision is the delegate's.
  ///
  /// Asked on every new TLS connection, including each attempt to re-establish a lost one.
  /// Returning `false` ends the connection with `.certificateRejected`, also during a reconnect,
  /// and the context doesn't ask again.
  func shouldAcceptCertificate(_ info: CertificateInfo) -> Bool

  /// A log message from openconnect or the context. Called often, so it shouldn't block.
  func didLog(_ message: String, level: LogLevel)

  /// Traffic statistics, in reply to `OpenConnectContext.requestStats()`.
  ///
  /// Not ordered with the context's `lifecycle`: a reply can still arrive after `.finished`, and
  /// the delegate has to ignore it then.
  func didReceive(_ stats: VPNStats)
}
