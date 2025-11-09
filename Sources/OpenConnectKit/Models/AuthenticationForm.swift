//
//  AuthenticationForm.swift
//  OpenConnectKit
//
//  Authentication form types for VPN login
//

import COpenConnect
import Foundation

/// Represents an authentication form that needs to be filled by the user.
///
/// The VPN server may present one or more authentication forms during the
/// connection process. Fill in the field values and return the modified form
/// in the `onAuthenticationRequired` callback.
///
/// ## Example
///
/// ```swift
/// session.onAuthenticationRequired = { form in
///     print("Authentication: \(form.title)")
///     var filledForm = form
///
///     for (index, field) in filledForm.fields.enumerated() {
///         switch field.type {
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
    public var fields: [AuthField]

    // MARK: - Initialization

    /// Creates an authentication form.
    ///
    /// - Parameters:
    ///   - title: The form title
    ///   - message: Optional message or banner text
    ///   - fields: The authentication fields
    public init(title: String, message: String? = nil, fields: [AuthField]) {
        self.title = title
        self.message = message
        self.fields = fields
    }
}

// MARK: - AuthField

/// A single field in an authentication form.
public struct AuthField: Sendable {
    // MARK: - Properties

    /// The field identifier.
    public let id: String

    /// The label to display to the user.
    public let label: String

    /// The type of field (text, password, etc.).
    public let type: FieldType

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
    ///   - type: The field type
    ///   - value: The current field value (default: empty string)
    ///   - isRequired: Whether the field is required (default: `true`)
    public init(
        id: String, label: String, type: FieldType, value: String = "", isRequired: Bool = true
    ) {
        self.id = id
        self.label = label
        self.type = type
        self.value = value
        self.isRequired = isRequired
    }

    // MARK: - FieldType

    /// The type of authentication field.
    public enum FieldType: Sendable {
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

// MARK: - Internal C Interop

extension AuthenticationForm {
    /// Creates an authentication form from a C auth form structure.
    ///
    /// - Parameter cForm: Pointer to the C `oc_auth_form` structure
    internal init(from cForm: UnsafeMutablePointer<oc_auth_form>) {
        let form = cForm.pointee

        // Extract title from banner
        if let titlePtr = form.banner {
            self.title = String(cString: titlePtr)
        } else {
            self.title = nil
        }

        // Extract message
        if let messagePtr = form.message {
            self.message = String(cString: messagePtr)
        } else {
            self.message = nil
        }

        // Extract fields from linked list
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

            // Determine field type based on OpenConnect option type
            let fieldType: AuthField.FieldType
            let fieldId = label  // Use label as ID for now

            // Map OpenConnect field types to our enum
            // OC_FORM_OPT_TEXT = 1, OC_FORM_OPT_PASSWORD = 2,
            // OC_FORM_OPT_HIDDEN = 3, OC_FORM_OPT_SELECT = 4
            switch opt.type {
            case 2:  // OC_FORM_OPT_PASSWORD
                fieldType = .password
            case 3:  // OC_FORM_OPT_HIDDEN
                fieldType = .hidden
            case 4:  // OC_FORM_OPT_SELECT
                // Cast to oc_form_opt_select to access choices
                let selectOpt = option.withMemoryRebound(to: oc_form_opt_select.self, capacity: 1) {
                    $0.pointee
                }
                var options: [String] = []

                // Extract choices from the select option
                if selectOpt.nr_choices > 0, let choicesPtr = selectOpt.choices {
                    for i in 0..<Int(selectOpt.nr_choices) {
                        if let choicePtr = choicesPtr[i], let namePtr = choicePtr.pointee.name {
                            options.append(String(cString: namePtr))
                        }
                    }
                }

                fieldType = .select(options: options)
            default:  // OC_FORM_OPT_TEXT or unknown
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

    /// Applies Swift form values back to the C form structure.
    ///
    /// Uses the proper OpenConnect API (`openconnect_set_option_value`) to set
    /// form field values instead of directly manipulating internal fields.
    ///
    /// - Parameter cForm: Pointer to the C `oc_auth_form` structure
    internal func apply(to cForm: UnsafeMutablePointer<oc_auth_form>) {
        var currentOption = cForm.pointee.opts
        var fieldIndex = 0

        while let option = currentOption, fieldIndex < fields.count {
            let field = fields[fieldIndex]

            // Use the proper OpenConnect API to set the option value
            // This handles all memory management internally and is the correct way
            // to set form field values according to the OpenConnect documentation
            let result = openconnect_set_option_value(option, field.value)

            // Log if setting the value failed (non-zero return value indicates error)
            if result != 0 {
                // We can't easily log here without access to the session context,
                // but the function will still continue to set other fields
                // The OpenConnect library will handle the error appropriately
            }

            currentOption = option.pointee.next
            fieldIndex += 1
        }
    }
}
