//
//  VPNPrompts.swift
//  OpenConnectKit
//
//  A ready-made VPNSessionDelegate that publishes prompts as observable state
//

import Foundation

/// A ready-made `VPNSessionDelegate` for SwiftUI. It publishes the prompt that's waiting for
/// the user as observable state, and the app answers it with the methods below.
///
/// Only one prompt is pending at a time, because the connection waits for each answer. Use one
/// `VPNPrompts` per session.
///
/// ```swift
/// @Observable @MainActor
/// final class AppModel {
///     let prompts = VPNPrompts()
///     let session: VPNSession
///
///     init() {
///         session = VPNSession(delegate: prompts)
///     }
/// }
///
/// // In a view:
/// .sheet(item: Bindable(model.prompts).pendingAuthentication) { prompt in
///     LoginForm(prompt.form) { filled in
///         model.prompts.submit(filled)
///     } onCancel: {
///         model.prompts.cancelAuthentication()
///     }
/// }
/// .alert(
///     "Untrusted certificate",
///     isPresented: Bindable(model.prompts).isCertificatePending,
///     presenting: model.prompts.pendingCertificate
/// ) { _ in
///     Button("Connect Anyway") { model.prompts.acceptCertificate() }
///     Button("Cancel", role: .cancel) { model.prompts.rejectCertificate() }
/// } message: { prompt in
///     Text(prompt.certificate.reason)
/// }
/// ```
///
/// If the connection attempt is cancelled while a prompt is pending, the prompt is withdrawn:
/// its property becomes `nil`, so a sheet or alert bound to it closes.
@Observable
@MainActor
public final class VPNPrompts: VPNSessionDelegate {
  // MARK: - Pending Prompts

  /// The authentication form waiting to be filled in, or `nil`.
  ///
  /// Setting it to `nil` cancels the prompt, like `cancelAuthentication()`, so it can back
  /// `.sheet(item:)` directly. Other values can't be assigned and are ignored.
  public var pendingAuthentication: AuthenticationPrompt? {
    get { authenticationWaiter?.prompt }
    set { if newValue == nil { resolveAuthentication(with: nil) } }
  }

  /// The server certificate waiting for a decision, or `nil`.
  ///
  /// Setting it to `nil` rejects the certificate, like `rejectCertificate()`. Other values can't
  /// be assigned and are ignored.
  public var pendingCertificate: CertificatePrompt? {
    get { certificateWaiter?.prompt }
    set { if newValue == nil { resolveCertificate(with: false) } }
  }

  /// Whether an authentication form is waiting. Setting it to `false` cancels the prompt.
  public var isAuthenticationPending: Bool {
    get { authenticationWaiter != nil }
    set { if !newValue { resolveAuthentication(with: nil) } }
  }

  /// Whether a server certificate is waiting for a decision. Setting it to `false` rejects the
  /// certificate.
  ///
  /// This suits `.alert(isPresented:)`: SwiftUI runs a button's action before it resets the
  /// binding, so after "Accept" there is nothing left to reject.
  public var isCertificatePending: Bool {
    get { certificateWaiter != nil }
    set { if !newValue { resolveCertificate(with: false) } }
  }

  // MARK: - Answers

  /// Answers the pending authentication prompt with the filled-in form.
  public func submit(_ form: AuthenticationForm) {
    resolveAuthentication(with: form)
  }

  /// Answers the pending authentication prompt with "cancel", which ends the connection
  /// attempt with `VPNError.cancelled`.
  public func cancelAuthentication() {
    resolveAuthentication(with: nil)
  }

  /// Accepts the pending server certificate, and the connection continues.
  public func acceptCertificate() {
    resolveCertificate(with: true)
  }

  /// Rejects the pending server certificate, which ends the connection attempt with
  /// `VPNError.certificateRejected`.
  public func rejectCertificate() {
    resolveCertificate(with: false)
  }

  // MARK: - Initialization

  public init() {}

  // MARK: - VPNSessionDelegate

  public func vpnSession(
    _ session: VPNSession,
    requiresAuthentication form: AuthenticationForm
  ) async -> AuthenticationForm? {
    let prompt = AuthenticationPrompt(form: form)
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        // Can't happen with one session per VPNPrompts; if it does, the older prompt can no
        // longer be answered, so cancel it rather than leave it waiting forever.
        resolveAuthentication(with: nil)
        authenticationWaiter = (prompt, continuation)
      }
    } onCancel: {
      Task { @MainActor in
        self.resolveAuthentication(with: nil, ifStillPending: prompt.id)
      }
    }
  }

  public func vpnSession(
    _ session: VPNSession,
    shouldAcceptCertificate info: CertificateInfo
  ) async -> Bool {
    let prompt = CertificatePrompt(certificate: info)
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        resolveCertificate(with: false)  // see the authentication method
        certificateWaiter = (prompt, continuation)
      }
    } onCancel: {
      Task { @MainActor in
        self.resolveCertificate(with: false, ifStillPending: prompt.id)
      }
    }
  }

  // MARK: - Private

  // The pending prompts, each with the continuation its delegate method is waiting on. The
  // public properties above are computed from these, so observing them works.

  private var authenticationWaiter:
    (prompt: AuthenticationPrompt, continuation: CheckedContinuation<AuthenticationForm?, Never>)?

  private var certificateWaiter:
    (prompt: CertificatePrompt, continuation: CheckedContinuation<Bool, Never>)?

  /// Resumes the waiting delegate method, if there is one. With `id`, only if that prompt is
  /// still the pending one: a cancellation that arrives late must not answer a newer prompt.
  private func resolveAuthentication(
    with form: AuthenticationForm?, ifStillPending id: AuthenticationPrompt.ID? = nil
  ) {
    guard let waiter = authenticationWaiter, id == nil || waiter.prompt.id == id else { return }
    authenticationWaiter = nil
    waiter.continuation.resume(returning: form)
  }

  /// See `resolveAuthentication(with:ifStillPending:)`.
  private func resolveCertificate(
    with accepted: Bool, ifStillPending id: CertificatePrompt.ID? = nil
  ) {
    guard let waiter = certificateWaiter, id == nil || waiter.prompt.id == id else { return }
    certificateWaiter = nil
    waiter.continuation.resume(returning: accepted)
  }
}

// MARK: - Prompts

/// An authentication form waiting for the user. `Identifiable`, so it can drive
/// `.sheet(item:)`.
public struct AuthenticationPrompt: Identifiable, Sendable {
  public let id: UUID

  /// The form to fill in. Pass the filled-in copy to `VPNPrompts.submit(_:)`.
  public let form: AuthenticationForm

  internal init(form: AuthenticationForm) {
    self.id = UUID()
    self.form = form
  }
}

/// A server certificate waiting for the user's decision. `Identifiable`, so it can drive
/// `.sheet(item:)` as well as an alert.
public struct CertificatePrompt: Identifiable, Sendable {
  public let id: UUID

  /// Why the certificate couldn't be verified.
  public let certificate: CertificateInfo

  internal init(certificate: CertificateInfo) {
    self.id = UUID()
    self.certificate = certificate
  }
}
