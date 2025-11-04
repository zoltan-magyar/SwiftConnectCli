import COpenConnect
import Foundation

class VpnContext {
    var vpnInfo: OpaquePointer?
    var server_url: URL?
    var username: String?
    var password: String?
    var is_connected: Bool = false
    var verbosity: VerbosityLevel

    var auth_called: Int = 0

    func connect() {
        guard let vpnInfo = self.vpnInfo else {
            fatalError("VPN context not initialized")
        }

        var ret = openconnect_obtain_cookie(vpnInfo)
        if ret != 0 {
            fatalError("Failed to obtain cookie")
        }

        ret = openconnect_make_cstp_connection(vpnInfo)
        if ret != 0 {
            fatalError("Failed to make CSTP connection")
        }

        ret = openconnect_setup_dtls(vpnInfo, 60)
        if ret != 0 {
            fatalError("Failed to setup DTLS")
        }

        self.is_connected = true
    }

    func set_url(_ url: URL) {
        self.server_url = url
        if let server_url = self.server_url {
            let ret = openconnect_parse_url(vpnInfo, server_url.absoluteString)
            if ret != 0 {
                fatalError("Failed to parse server URL")
            }
        }
    }

    func set_loglevel(_ level: VerbosityLevel) {
        self.verbosity = level
        openconnect_set_loglevel(vpnInfo, self.verbosity.openConnectLevel)
    }

    func set_credentials(_ username: String, _ password: String) {
        self.username = username
        self.password = password
    }

    func print_cert() {
        print("Cert called!")
        //let urlDesc = self.server_url?.absoluteString ?? "nil"
        //print("Context info:", urlDesc, self.username ?? "nil", self.is_connected)
    }

    func print_auth() {
        self.auth_called += 1
        print("Auth called! (count: \(self.auth_called))")
        //let urlDesc = self.server_url?.absoluteString ?? "nil"
        //print("Context info:", urlDesc, self.username ?? "nil", self.is_connected)
    }

    init(server_url: URL?, username: String?, password: String?, verbosity: VerbosityLevel?) {
        self.server_url = server_url
        self.username = username
        self.password = password
        self.verbosity = verbosity ?? .info

        // Initialize the progress callback system before creating vpninfo
        registerCallback()

        self.vpnInfo = openconnect_vpninfo_new(
            "AnyConnect compatible VPN client in Swift",
            validatePeerCertCallback,
            nil,
            processAuthFormCallback,
            get_progress_shim_callback(),  // Use the C shim that converts variadic to va_list
            Unmanaged.passRetained(self).toOpaque())
        guard let vpnInfo = self.vpnInfo else {
            fatalError("Failed to create VPN context")
        }

        openconnect_set_loglevel(vpnInfo, self.verbosity.openConnectLevel)

        if let server_url = self.server_url {
            let ret = openconnect_parse_url(vpnInfo, server_url.absoluteString)
            if ret != 0 {
                fatalError("Failed to parse server URL")
            }
        }
    }

    deinit {
        if let vpnInfo = self.vpnInfo {
            // Get the privdata pointer from vpnInfo if possible, or track it
            // This consumes the +1 from passRetained, balancing the retain count
            openconnect_vpninfo_free(vpnInfo)
        }
    }
}

// volatile int quit_signal;
// int cmd_fd;  /* Command pipe file descriptor for cancellation */
