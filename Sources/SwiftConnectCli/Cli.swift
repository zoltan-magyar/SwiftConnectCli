//
//  Cli.swift
//  SwiftConnectCli
//
//  CLI application using OpenConnectKit library
//

import ArgumentParser
import Foundation
import OpenConnectKit

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
        // Validate server URL
        guard let server else {
            print("\nError: Server URL is required")
            throw ExitCode.validationFailure
        }

        guard let serverURL = URL(string: server) else {
            print("\nError: Invalid server URL")
            throw ExitCode.validationFailure
        }

        // Parse VPN protocol
        guard let vpnProtocol = VpnProtocol(rawValue: vpnProtocol) else {
            print("\nError: Invalid VPN protocol '\(vpnProtocol)'")
            print("Supported protocols: anyconnect, gp, pulse, nc, array")
            throw ExitCode.validationFailure
        }

        // Convert CLI verbosity to LogLevel
        let logLevel: LogLevel
        switch verbosity {
        case .info: logLevel = .info
        case .debug: logLevel = .debug
        case .trace: logLevel = .trace
        }

        // Create configuration
        let config = VpnConfiguration(
            serverURL: serverURL,
            vpnProtocol: vpnProtocol,
            logLevel: logLevel,
            allowInsecureCertificates: false,
            username: username
        )

        print("\nConfiguration:")
        print("  Server: \(serverURL)")
        print("  Username: \(username ?? "will prompt")")
        print("  Protocol: \(vpnProtocol.rawValue)")
        print("  Log Level: \(logLevel)")
        print()

        // Create VPN session
        let session = VpnSession(configuration: config)

        // Set up log handler (default is fine, but we could customize)
        session.onLog = { message, level in
            let prefix: String
            switch level {
            case .error: prefix = "ERROR"
            case .info: prefix = "INFO"
            case .debug: prefix = "DEBUG"
            case .trace: prefix = "TRACE"
            }
            print("\(prefix): \(message)")
        }

        // Set up certificate validation handler
        session.onCertificateValidation = { certInfo in
            print("\n⚠️  Certificate Validation:")
            print("   Reason: \(certInfo.reason)")
            if let hostname = certInfo.hostname {
                print("   Hostname: \(hostname)")
            }

            // For CLI, we'll accept certificates (in production, should prompt user)
            print("   Action: Accepting certificate")
            return true
        }

        // Set up authentication handler
        session.onAuthenticationRequired = { form in
            print("\n🔐 Authentication Required:")
            print("   \(form.title)")
            if let message = form.message {
                print("   \(message)")
            }
            print()

            var filledForm = form

            // Fill in form fields by prompting user
            for (index, field) in filledForm.fields.enumerated() {
                let prompt: String
                switch field.type {
                case .password:
                    prompt = "\(field.label): "
                case .text:
                    prompt = "\(field.label): "
                case .hidden:
                    // Skip hidden fields
                    continue
                case .select(let options):
                    print("\(field.label):")
                    for (idx, option) in options.enumerated() {
                        print("  \(idx + 1). \(option)")
                    }
                    prompt = "Select (1-\(options.count)): "
                }

                print(prompt, terminator: "")

                if let input = readLine() {
                    filledForm.fields[index].value = input
                }
            }

            return filledForm
        }

        print("Connecting to VPN...")

        // Connect to VPN
        do {
            try session.connect()
            print("\n✅ Connected successfully!")
            print("VPN connection established.")

            // In a real application, you would:
            // - Keep the connection alive
            // - Handle data transfer
            // - Monitor connection status
            // - Handle disconnection gracefully

        } catch let error as VpnError {
            print("\n❌ Connection failed: \(error.localizedDescription)")
            throw ExitCode.failure
        } catch {
            print("\n❌ Unexpected error: \(error)")
            throw ExitCode.failure
        }
    }
}

// Keep VerbosityLevel for CLI flags
enum VerbosityLevel: String, EnumerableFlag {
    case info
    case debug
    case trace

    static func name(for value: VerbosityLevel) -> NameSpecification {
        switch value {
        case .info: return .customLong("oc-info")
        case .debug: return .customLong("oc-debug")
        case .trace: return .customLong("oc-trace")
        }
    }

    static func help(for value: VerbosityLevel) -> ArgumentHelp? {
        switch value {
        case .info: return "OpenConnect INFO level"
        case .debug: return "OpenConnect DEBUG level (default)"
        case .trace: return "OpenConnect TRACE level"
        }
    }
}
