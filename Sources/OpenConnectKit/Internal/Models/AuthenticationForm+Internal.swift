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

    if let titlePtr = form.banner {
      self.title = String(cString: titlePtr)
    } else {
      self.title = nil
    }

    if let messagePtr = form.message {
      self.message = String(cString: messagePtr)
    } else {
      self.message = nil
    }

    var fields: [AuthField] = []
    var currentOption = form.opts

    while let option = currentOption {
      let opt = option.pointee

      let label: String
      if let labelPtr = opt.label {
        label = String(cString: labelPtr)
      } else {
        label = "Field"
      }

      var value = ""
      if let valuePtr = opt._value {
        value = String(cString: valuePtr)
      }

      let fieldType: AuthField.FieldType
      let fieldId = label  // Use label as ID for now

      switch opt.type {
      case OC_FORM_OPT_PASSWORD:
        fieldType = .password
      case OC_FORM_OPT_HIDDEN:
        fieldType = .hidden
      case OC_FORM_OPT_SELECT:
        // A select option is an oc_form_opt_select, which starts with an oc_form_opt. Only the
        // type tag says the allocation is the larger struct, so reinterpret after checking it.
        let select = UnsafeMutableRawPointer(option).assumingMemoryBound(
          to: oc_form_opt_select.self)
        var options: [String] = []
        if select.pointee.nr_choices > 0, let choicesPtr = select.pointee.choices {
          for i in 0..<Int(select.pointee.nr_choices) {
            if let choicePtr = choicesPtr[i], let namePtr = choicePtr.pointee.name {
              options.append(String(cString: namePtr))
            }
          }
        }

        // openconnect leaves a select's value unset, and openconnect_set_option_value() rejects
        // anything that isn't one of its choices. Preselect the choice the server marked as
        // selected (only recorded for the auth group), otherwise the first one.
        if value.isEmpty {
          let selected = select == form.authgroup_opt ? Int(form.authgroup_selection) : 0
          value = options.indices.contains(selected) ? options[selected] : options.first ?? ""
        }

        fieldType = .select(options: options)
      default:
        fieldType = .text
      }

      let field = AuthField(
        id: fieldId,
        label: label,
        type: fieldType,
        value: value,
        isRequired: true
      )

      fields.append(field)
      currentOption = opt.next
    }

    self.fields = fields
  }

  // Apply Swift form values back to C structure. Returns false if openconnect rejects a value,
  // e.g. a select value that isn't one of its choices.
  internal func apply(to cForm: UnsafeMutablePointer<oc_auth_form>) -> Bool {
    var currentOption = cForm.pointee.opts
    var fieldIndex = 0

    while let option = currentOption, fieldIndex < fields.count {
      // Hidden options already carry the server's value; setting it again would only leak
      // the original copy.
      if option.pointee.type != OC_FORM_OPT_HIDDEN,
        openconnect_set_option_value(option, fields[fieldIndex].value) != 0
      {
        return false
      }

      currentOption = option.pointee.next
      fieldIndex += 1
    }
    return true
  }
}
