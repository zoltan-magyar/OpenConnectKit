//
//  AuthenticationForm.swift
//  OpenConnectKit
//
//  Authentication form types for VPN login
//

import Foundation

/// An authentication form the server wants filled in.
///
/// The server may send several forms in a row, for example a password form and then a
/// one-time code. Fill in the field values and return the form from
/// `VPNSessionDelegate.vpnSession(_:requiresAuthentication:)`. Values are matched to the
/// server's fields by `Field.id`, so a UI may filter or reorder `fields` freely.
///
/// ## Example
///
/// ```swift
/// func vpnSession(
///     _ session: VPNSession,
///     requiresAuthentication form: AuthenticationForm
/// ) async -> AuthenticationForm? {
///     var filledForm = form
///     for index in filledForm.fields.indices {
///         switch filledForm.fields[index].kind {
///         case .password:
///             filledForm.fields[index].value = "secretpassword"
///         case .text:
///             filledForm.fields[index].value = "username"
///         default:
///             break
///         }
///     }
///     return filledForm
/// }
/// ```
public struct AuthenticationForm: Hashable, Sendable {
  // MARK: - Properties

  /// Which form this is, as the server names it, for example `"main"`, or `"challenge"` for a
  /// one-time code.
  public let name: String?

  /// Text the server shows with the login, such as a usage policy.
  public let banner: String?

  /// The server's prompt, for example "Please enter your username and password."
  public let message: String?

  /// Why the previous attempt failed, for example "Login failed." Set when the server sends the
  /// form again after a failed login.
  public let error: String?

  /// The fields to fill in.
  public var fields: [Field]

  // MARK: - Initialization

  /// Creates an authentication form. `VPNSession` creates these itself; this is for previews
  /// and tests.
  public init(
    name: String? = nil, banner: String? = nil, message: String? = nil, error: String? = nil,
    fields: [Field]
  ) {
    self.name = name
    self.banner = banner
    self.message = message
    self.error = error
    self.fields = fields
  }
}

// MARK: - Field

extension AuthenticationForm {
  /// A single field in an authentication form.
  public struct Field: Hashable, Identifiable, Sendable {
    // MARK: - Properties

    /// The field's name, as the server knows it, for example `"username"`. The filled-in value
    /// is sent back under this name.
    public let id: String

    /// The label to show, as the server provides it, for example "Username:".
    public let label: String

    /// What kind of field this is (text, password, etc.).
    public let kind: Kind

    /// The field's value. Pre-filled where the server or openconnect provides one, such as a
    /// select field's default choice.
    public var value: String

    /// Whether the server expects digits only, for example for a one-time code.
    public let isNumeric: Bool

    /// Whether this is the server's group selector ("GROUP:").
    ///
    /// Each group can ask for different things, so choosing a different group makes the server
    /// send that group's form. Submit the form as soon as the user picks another group (the
    /// other values are not needed yet); the group's form then arrives as the next prompt.
    public let isAuthGroup: Bool

    // MARK: - Initialization

    /// Creates an authentication field. `VPNSession` creates these itself; this is for
    /// previews and tests.
    public init(
      id: String, label: String, kind: Kind, value: String = "", isNumeric: Bool = false,
      isAuthGroup: Bool = false
    ) {
      self.id = id
      self.label = label
      self.kind = kind
      self.value = value
      self.isNumeric = isNumeric
      self.isAuthGroup = isAuthGroup
    }

    // MARK: - Kind

    /// The kind of authentication field.
    public enum Kind: Hashable, Sendable {
      /// Regular text input.
      case text

      /// Password input (should be hidden from display).
      case password

      /// A value the server or openconnect sets. Not shown to the user, and sent back
      /// unchanged whatever `value` says.
      case hidden

      /// A choice from a fixed list. Set `value` to one of the choices' `value`s.
      case select(choices: [Choice])
    }

    // MARK: - Choice

    /// One option of a `.select` field.
    public struct Choice: Hashable, Sendable {
      /// What's sent to the server when this choice is selected.
      public let value: String

      /// What to show the user.
      public let label: String

      public init(value: String, label: String) {
        self.value = value
        self.label = label
      }
    }
  }
}
