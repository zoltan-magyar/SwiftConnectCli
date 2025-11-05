//
//  VpnContext.swift
//  OpenConnectKit
//
//  Internal wrapper around OpenConnect C API
//

import COpenConnect
import Foundation

/// Internal context managing the OpenConnect VPN connection.
///
/// This class handles all C interop with the OpenConnect library and is owned by `VpnSession`.
/// It translates between Swift types and C types, managing the lifecycle of the underlying
/// OpenConnect `vpninfo` structure.
internal class VpnContext {
    // MARK: - Properties

    /// OpenConnect vpninfo pointer.
    private var vpnInfo: OpaquePointer?

    /// Reference to the owning VpnSession.
    private weak var session: VpnSession?

    /// Configuration for this context.
    private let configuration: VpnConfiguration

    /// Whether the VPN is currently connected.
    private(set) var isConnected: Bool = false

    // MARK: - Initialization

    /// Creates a VPN context.
    ///
    /// - Parameters:
    ///   - session: The VpnSession that owns this context
    ///   - configuration: The VPN configuration
    /// - Throws: `VpnError` if initialization fails
    init(session: VpnSession, configuration: VpnConfiguration) throws {
        self.session = session
        self.configuration = configuration

        self.vpnInfo = openconnect_vpninfo_new(
            "OpenConnectKit",
            validatePeerCertCallback,
            nil,
            processAuthFormCallback,
            get_progress_shim_callback(),
            Unmanaged.passUnretained(session).toOpaque()
        )

        guard let vpnInfo = self.vpnInfo else {
            throw VpnError.notInitialized
        }

        openconnect_set_loglevel(vpnInfo, configuration.logLevel.openConnectLevel)

        let ret = openconnect_parse_url(vpnInfo, configuration.serverURL.absoluteString)
        if ret != 0 {
            throw VpnError.invalidConfiguration(reason: "Failed to parse server URL")
        }
    }

    deinit {
        disconnect()

        if let vpnInfo = self.vpnInfo {
            openconnect_vpninfo_free(vpnInfo)
            self.vpnInfo = nil
        }
    }

    // MARK: - Connection Methods

    /// Connects to the VPN server.
    ///
    /// - Throws: `VpnError` if any connection step fails
    func connect() throws {
        guard let vpnInfo = self.vpnInfo else {
            throw VpnError.notInitialized
        }

        guard !isConnected else {
            return
        }

        var ret = openconnect_obtain_cookie(vpnInfo)
        if ret != 0 {
            throw VpnError.cookieObtainFailed
        }

        ret = openconnect_make_cstp_connection(vpnInfo)
        if ret != 0 {
            throw VpnError.cstpConnectionFailed
        }

        ret = openconnect_setup_dtls(vpnInfo, 60)
        if ret != 0 {
            throw VpnError.dtlsSetupFailed
        }

        isConnected = true
    }

    /// Disconnects from the VPN server.
    func disconnect() {
        guard isConnected else {
            return
        }

        isConnected = false
    }

    // MARK: - Callback Handlers

    /// Handles progress/log messages from OpenConnect.
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
    /// - Parameter reason: C string pointer to the validation failure reason
    /// - Returns: `0` to accept, `1` to reject
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
