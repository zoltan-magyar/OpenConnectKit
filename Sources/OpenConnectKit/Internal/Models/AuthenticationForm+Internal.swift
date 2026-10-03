//
//  AuthenticationForm+Internal.swift
//  OpenConnectKit
//
//  Internal C interop extensions for AuthenticationForm
//

import COpenConnect
import Foundation

// MARK: - Internal C Interop

extension AuthenticationForm {
  // Create from C oc_auth_form structure
  internal init(from cForm: UnsafeMutablePointer<oc_auth_form>) {
    let form = cForm.pointee
    var fields: [Field] = []
    var currentOption = form.opts

    while let option = currentOption {
      defer { currentOption = option.pointee.next }
      let opt = option.pointee

      // openconnect marks fields the selected group doesn't use (just before calling us); they
      // must be neither shown nor sent.
      if opt.flags & UInt32(OC_FORM_OPT_IGNORE) != 0 {
        continue
      }

      let label = opt.label.map { String(cString: $0) } ?? "Field"
      var value = opt._value.map { String(cString: $0) } ?? ""
      var isAuthGroup = false

      let kind: Field.Kind
      switch opt.type {
      case OC_FORM_OPT_TEXT:
        kind = .text
      case OC_FORM_OPT_PASSWORD:
        kind = .password
      case OC_FORM_OPT_SELECT:
        // A select option is an oc_form_opt_select, which starts with an oc_form_opt. Only the
        // type tag says the allocation is the larger struct, so reinterpret after checking it.
        let select = UnsafeMutableRawPointer(option).assumingMemoryBound(
          to: oc_form_opt_select.self)
        let choices = Self.choices(of: select)
        isAuthGroup = select == form.authgroup_opt

        // openconnect leaves a select's value unset, and openconnect_set_option_value() rejects
        // anything that isn't one of its choices. Preselect the choice the server marked as
        // selected (only recorded for the auth group), otherwise the first one.
        if value.isEmpty {
          let selected = isAuthGroup ? Int(form.authgroup_selection) : 0
          value =
            choices.indices.contains(selected)
            ? choices[selected].value : choices.first?.value ?? ""
        }
        kind = .select(choices: choices)
      default:
        // OC_FORM_OPT_HIDDEN, and the types openconnect fills in itself (TOKEN, when a software
        // token is configured) or that need support this library doesn't have yet (SSO_TOKEN,
        // SSO_USER for browser logins). openconnect's own client doesn't prompt for these either.
        kind = .hidden
      }

      fields.append(
        Field(
          // The name is what the server expects back; every field the server sends has one.
          id: opt.name.map { String(cString: $0) } ?? label,
          label: label,
          kind: kind,
          value: value,
          isNumeric: opt.flags & UInt32(OC_FORM_OPT_NUMERIC) != 0,
          isAuthGroup: isAuthGroup
        ))
    }

    self.init(
      name: form.auth_id.map { String(cString: $0) },
      banner: form.banner.map { String(cString: $0) },
      message: form.message.map { String(cString: $0) },
      error: form.error.map { String(cString: $0) },
      fields: fields
    )
  }

  // Writes the field values back into the C form, matching them to the server's fields by name.
  // Returns the OC_FORM_RESULT_* code for openconnect: NEWGROUP if the user chose a different
  // auth group (openconnect then fetches that group's form and asks again), ERR if openconnect
  // rejects a value, OK otherwise.
  internal func apply(to cForm: UnsafeMutablePointer<oc_auth_form>) -> CInt {
    let form = cForm.pointee
    let values = Dictionary(
      fields.map { ($0.id, $0.value) }, uniquingKeysWith: { first, _ in first })
    var groupChanged = false
    var currentOption = form.opts

    while let option = currentOption {
      defer { currentOption = option.pointee.next }
      let opt = option.pointee

      // Only what the user fills in. Hidden options already carry their value; setting it again
      // would only leak the original copy.
      guard opt.flags & UInt32(OC_FORM_OPT_IGNORE) == 0,
        opt.type == OC_FORM_OPT_TEXT || opt.type == OC_FORM_OPT_PASSWORD
          || opt.type == OC_FORM_OPT_SELECT,
        let name = opt.name.map({ String(cString: $0) }),
        let value = values[name]
      else {
        continue
      }

      if opt.type == OC_FORM_OPT_SELECT {
        let select = UnsafeMutableRawPointer(option).assumingMemoryBound(
          to: oc_form_opt_select.self)
        if select == form.authgroup_opt {
          // The group openconnect presented is the one at authgroup_selection.
          let choices = Self.choices(of: select)
          let presented = Int(form.authgroup_selection)
          groupChanged =
            choices.indices.contains(presented) && choices[presented].value != value
        }
      }

      guard openconnect_set_option_value(option, value) == 0 else {
        return OC_FORM_RESULT_ERR
      }
    }
    return groupChanged ? OC_FORM_RESULT_NEWGROUP : OC_FORM_RESULT_OK
  }

  // The choices of a select option: oc_choice.name is what's sent, oc_choice.label is shown.
  private static func choices(
    of select: UnsafeMutablePointer<oc_form_opt_select>
  ) -> [Field.Choice] {
    guard select.pointee.nr_choices > 0, let choicesPtr = select.pointee.choices else {
      return []
    }
    // openconnect rejects choices without a name while parsing, so indices match
    // authgroup_selection.
    return (0..<Int(select.pointee.nr_choices)).compactMap { index in
      guard let choice = choicesPtr[index]?.pointee, let namePtr = choice.name else { return nil }
      let value = String(cString: namePtr)
      return Field.Choice(value: value, label: choice.label.map { String(cString: $0) } ?? value)
    }
  }
}
