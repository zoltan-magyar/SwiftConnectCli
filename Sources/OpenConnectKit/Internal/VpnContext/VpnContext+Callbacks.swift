//
//  VpnContext+Callbacks.swift
//  OpenConnectKit
//
//  Callback handling extension for VpnContext
//

import COpenConnect
import Foundation

// MARK: - Callback Handlers

extension VpnContext {
    /// Handles progress/log messages from OpenConnect.
    ///
    /// This method is called by the progress callback (via `progressCallback()` in ProgressCallback.swift)
    /// when OpenConnect emits log messages. It converts the C log level to a Swift `LogLevel`
    /// and forwards the message to the owning VpnSession.
    ///
    /// Log levels:
    /// - `0` - Error
    /// - `1` - Info
    /// - `2` - Debug
    /// - `3` - Trace
    ///
    /// - Parameters:
    ///   - level: The C log level
    ///   - message: The formatted message
    func handleProgress(level: Int32, message: String) {
        guard let session = session else { return }

        let logLevel: LogLevel
        switch level {
        case 0: logLevel = .error
        case 1: logLevel = .info
        case 2: logLevel = .debug
        case 3: logLevel = .trace
        default: logLevel = .info
        }

        session.handleProgress(level: logLevel, message: message)
    }

    /// Handles certificate validation from OpenConnect.
    ///
    /// This method is called by the certificate validation callback (via `validatePeerCertCallback()`
    /// in CertValidationCallback.swift) when the server's certificate needs validation.
    /// It creates a Swift `CertificateInfo` object and delegates to the VpnSession's
    /// validation handler.
    ///
    /// - Parameter reason: C string pointer to the validation failure reason (if any)
    /// - Returns: `0` to accept the certificate, `1` to reject it
    func handleCertificateValidation(reason: UnsafePointer<CChar>?) -> Int32 {
        guard let session = session else {
            return 1
        }

        let certInfo = CertificateInfo(from: reason)
        let accepted = session.handleCertificateValidation(certInfo: certInfo)

        return accepted ? 0 : 1
    }

    /// Handles authentication form from OpenConnect.
    ///
    /// This method is called by the authentication form callback (via `processAuthFormCallback()`
    /// in AuthFormCallback.swift) when the server requires authentication. It converts the
    /// C `oc_auth_form` structure to a Swift `AuthenticationForm`, delegates to the VpnSession
    /// for user input, and applies the filled values back to the C structure.
    ///
    /// - Parameter form: Pointer to the C `oc_auth_form` structure
    /// - Returns: `0` for success, `1` for failure
    func handleAuthenticationForm(form: UnsafeMutablePointer<oc_auth_form>) -> Int32 {
        guard let session = session else {
            return 1
        }

        let authForm = AuthenticationForm(from: form)
        let filledForm = session.handleAuthenticationForm(authForm)
        filledForm.apply(to: form)

        return 0
    }
}
