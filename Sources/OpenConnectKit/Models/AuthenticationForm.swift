//
//  AuthenticationForm.swift
//  OpenConnectKit
//
//  Authentication form types for VPN login
//

import Foundation

/// Represents an authentication form that needs to be filled by the user.
///
/// The VPN server may present one or more authentication forms during the
/// connection process. Fill in the field values and return the modified form
/// from `VPNSessionDelegate.vpnSession(_:requiresAuthentication:)`.
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
public struct AuthenticationForm: Sendable {
  // MARK: - Properties

  /// The form title.
  public let title: String?

  /// Optional message or banner text.
  public let message: String?

  /// The authentication fields that need to be filled.
  public var fields: [Field]

  // MARK: - Initialization

  /// Creates an authentication form.
  ///
  /// - Parameters:
  ///   - title: The form title
  ///   - message: Optional message or banner text
  ///   - fields: The authentication fields
  public init(title: String, message: String? = nil, fields: [Field]) {
    self.title = title
    self.message = message
    self.fields = fields
  }
}

// MARK: - Field

extension AuthenticationForm {
  /// A single field in an authentication form.
  public struct Field: Sendable {
    // MARK: - Properties

    /// The field identifier.
    public let id: String

    /// The label to display to the user.
    public let label: String

    /// What kind of field this is (text, password, etc.).
    public let kind: Kind

    /// The current value of the field.
    public var value: String

    /// Whether this field is required.
    public let isRequired: Bool

    // MARK: - Initialization

    /// Creates an authentication field.
    ///
    /// - Parameters:
    ///   - id: The field identifier
    ///   - label: The label to display to the user
    ///   - kind: What kind of field this is
    ///   - value: The current field value (default: empty string)
    ///   - isRequired: Whether the field is required (default: `true`)
    public init(
      id: String, label: String, kind: Kind, value: String = "", isRequired: Bool = true
    ) {
      self.id = id
      self.label = label
      self.kind = kind
      self.value = value
      self.isRequired = isRequired
    }

    // MARK: - Kind

    /// The kind of authentication field.
    public enum Kind: Sendable {
      /// Regular text input.
      case text

      /// Password input (should be hidden from display).
      case password

      /// Hidden field (pre-filled, not shown to user).
      case hidden

      /// Select/dropdown field with options.
      ///
      /// - Parameter options: Available options for selection
      case select(options: [String])
    }
  }
}
