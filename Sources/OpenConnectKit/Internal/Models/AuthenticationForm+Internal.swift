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

      let value: String
      if let valuePtr = opt._value {
        value = String(cString: valuePtr)
      } else {
        value = ""
      }

      let fieldType: AuthField.FieldType
      let fieldId = label  // Use label as ID for now

      switch opt.type {
      case 2:
        fieldType = .password
      case 3:
        fieldType = .hidden
      case 4:
        let selectOpt = option.withMemoryRebound(to: oc_form_opt_select.self, capacity: 1) {
          $0.pointee
        }
        var options: [String] = []
        if selectOpt.nr_choices > 0, let choicesPtr = selectOpt.choices {
          for i in 0..<Int(selectOpt.nr_choices) {
            if let choicePtr = choicesPtr[i], let namePtr = choicePtr.pointee.name {
              options.append(String(cString: namePtr))
            }
          }
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

  // Apply Swift form values back to C structure
  internal func apply(to cForm: UnsafeMutablePointer<oc_auth_form>) {
    var currentOption = cForm.pointee.opts
    var fieldIndex = 0

    while let option = currentOption, fieldIndex < fields.count {
      let field = fields[fieldIndex]

      let result = openconnect_set_option_value(option, field.value)
      assert(result == 0, "Failed to set auth form value for field: \(field.label)")

      currentOption = option.pointee.next
      fieldIndex += 1
    }
  }
}
