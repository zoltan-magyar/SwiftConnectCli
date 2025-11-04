import ArgumentParser
import COpenConnect
import Foundation

@main
struct Cli: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "openconnect-swift",
        abstract: "A Swift CLI for OpenConnect VPN",
        version: "1.0.0"
    )

    @Argument(help: "VPN server URL (e.g., https://vpn.example.com)")
    var server: String?

    @Argument(help: "Username for authentication (optional, will prompt if not provided)")
    var username: String?

    @Option(name: .long, help: "VPN protocol (anyconnect, gp, pulse, etc.)")
    var vpnProtocol: String = "anyconnect"

    @Flag(help: "Set OpenConnect verbosity level")
    var verbosity: VerbosityLevel = .debug

    mutating func run() throws {

        // Print OpenConnect library version
        if let version = openconnect_get_version() {
            print("OpenConnect library version: \(String(cString: version))")
        }
        // Validate server URL
        guard let server else {
            print("\nError: Server URL is required")
            throw ExitCode.validationFailure
        }

        // Validate server URL
        guard let serverURL = URL(string: server) else {
            print("\nError: Invalid server URL")
            throw ExitCode.validationFailure
        }

        print("\nConfiguration:")
        print("  Server: \(serverURL)")
        print("  Username: \(username ?? "will prompt")")
        print("  Protocol: \(vpnProtocol)")
        print(
            "  Verbosity: \(verbosity.rawValue.uppercased()) (level \(verbosity.openConnectLevel))")

        print("\nReady to connect to: \(serverURL)")
        print("OpenConnect log level: \(verbosity.openConnectLevel)")

        let vpnContext = VpnContext(
            server_url: serverURL, username: "", password: "", verbosity: verbosity)

        vpnContext.connect()
    }
}
