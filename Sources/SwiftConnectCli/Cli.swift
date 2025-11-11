//
//  Cli.swift
//  SwiftConnectCli
//
//  CLI application using OpenConnectKit library
//

import ArgumentParser
import Foundation
import OpenConnectKit

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@main
struct Cli: ParsableCommand {
  // Signal sources for handling Ctrl+C and termination
  private static var signalSources: [DispatchSourceSignal] = []
  // Timer for periodic stats updates
  private static var statsTimer: DispatchSourceTimer?

  static let configuration = CommandConfiguration(
    commandName: "swiftconnect-cli",
    abstract: "A Swift CLI for OpenConnect VPN",
    discussion: """
      This tool connects to VPN servers using the OpenConnect protocol.
      It supports multiple VPN protocols including Cisco AnyConnect, GlobalProtect,
      Pulse Secure, and others.

      Note: This application requires elevated privileges (root/Administrator)
      to create network interfaces and modify routing tables.
      """,
    version: "1.0.0"
  )

  @Argument(help: "VPN server URL (e.g., https://vpn.example.com)")
  var server: String?

  @Argument(help: "Username for authentication (optional, will prompt if not provided)")
  var username: String?

  @Option(name: .long, help: "VPN protocol (anyconnect, gp, pulse, nc, array)")
  var vpnProtocol: String = "anyconnect"

  @Flag(name: .shortAndLong, help: "Increase verbosity (-v: info, -vv: debug, -vvv: trace)")
  var verbose: Int

  mutating func run() throws {
    // Check for elevated privileges first
    do {
      try PrivilegeChecker.requireElevatedPrivileges()
    } catch {
      throw ExitCode.failure
    }

    // Validate server URL
    guard let server else {
      print("\n❌ Error: Server URL is required")
      print("\nUsage: swiftconnect-cli <server-url> [username]\n")
      print("Example: swiftconnect-cli https://vpn.example.com myuser")
      throw ExitCode.validationFailure
    }

    guard let serverURL = URL(string: server) else {
      print("\n❌ Error: Invalid server URL: '\(server)'")
      print("\nThe server URL must be a valid URL, including the protocol.")
      print("Example: https://vpn.example.com")
      throw ExitCode.validationFailure
    }

    // Parse VPN protocol
    guard let vpnProtocol = VpnProtocol(rawValue: vpnProtocol) else {
      print("\n❌ Error: Invalid VPN protocol '\(vpnProtocol)'")
      print("\nSupported protocols:")
      print("  • anyconnect - Cisco AnyConnect")
      print("  • gp         - GlobalProtect (Palo Alto)")
      print("  • pulse      - Pulse Secure")
      print("  • nc         - Juniper Network Connect")
      print("  • array      - Array Networks")
      throw ExitCode.validationFailure
    }

    // Convert CLI verbosity count to LogLevel
    let logLevel: LogLevel
    switch verbose {
    case 0: logLevel = .error  // No -v flag: errors only
    case 1: logLevel = .info  // -v: info level
    case 2: logLevel = .debug  // -vv: debug level
    default: logLevel = .trace  // -vvv or more: trace level
    }

    // Create configuration
    let config = VpnConfiguration(
      serverURL: serverURL,
      vpnProtocol: vpnProtocol,
      logLevel: logLevel,
      allowInsecureCertificates: false
    )

    print("\n" + String(repeating: "=", count: 60))
    print("SwiftConnect CLI - OpenConnect VPN Client")
    print(String(repeating: "=", count: 60))
    print("\nConfiguration:")
    print("  Server:   \(serverURL)")
    print("  Protocol: \(vpnProtocol.rawValue)")
    print("  Log Level: \(logLevel)")
    print()

    // Create VPN session
    let session = VpnSession(configuration: config)

    // Configure session handlers
    configureSessionHandlers(session: session)

    // Set up signal handlers for graceful shutdown
    setupSignalHandlers(session: session)

    print("Connecting to VPN...\n")

    // Connect to VPN
    do {
      try session.connect()
      print("\n✅ Connected successfully!")
      print(String(repeating: "=", count: 60))
      print()

      // Display connection details
      displayConnectionInfo(session: session)

      // Keep the connection alive
      print("Press Ctrl+C to disconnect...")
      print()

      // Start periodic stats updates
      startPeriodicStats(session: session)

      // Block on main dispatch queue (signal handlers will exit)
      // Note: dispatchMain() never returns - program exits via signal handlers
      dispatchMain()

    } catch let error as VpnError {
      print("\n" + String(repeating: "=", count: 60))
      print("❌ Connection failed: \(error.localizedDescription)")
      print(String(repeating: "=", count: 60))
      print()
      throw ExitCode.failure
    } catch {
      print("\n" + String(repeating: "=", count: 60))
      print("❌ Unexpected error: \(error)")
      print(String(repeating: "=", count: 60))
      print()
      throw ExitCode.failure
    }
  }

  // MARK: - Session Configuration

  private func configureSessionHandlers(session: VpnSession) {
    // Status change handler - show connection progress
    session.onStatusChanged = { status in
      let timestamp = DateFormatter.localizedString(
        from: Date(),
        dateStyle: .none,
        timeStyle: .medium
      )

      switch status {
      case .disconnected(let error):
        if let error = error {
          print("[\(timestamp)] ❌ Status: Disconnected - \(error.localizedDescription)")
        } else {
          print("[\(timestamp)] ℹ️  Status: Disconnected")
        }
      case .connecting(let stage):
        print("[\(timestamp)] 🔄 Status: \(stage)")
      case .connected:
        print("[\(timestamp)] ✅ Status: Connected!")
      case .reconnecting:
        print("[\(timestamp)] 🔄 Status: Reconnecting after connection loss...")
      }
    }

    // Log handler - format log messages nicely
    session.onLog = { message, level in
      let timestamp = DateFormatter.localizedString(
        from: Date(),
        dateStyle: .none,
        timeStyle: .medium
      )

      let prefix: String

      switch level {
      case .error:
        prefix = "ERROR"
      case .info:
        prefix = "INFO"
      case .debug:
        prefix = "DEBUG"
      case .trace:
        prefix = "TRACE"
      }

      print("[\(timestamp)] \(prefix): \(message)")
    }

    // Certificate validation handler
    session.onCertificateValidation = { certInfo in
      print("\n" + String(repeating: "=", count: 60))
      print("⚠️  Certificate Validation Required")
      print(String(repeating: "=", count: 60))
      print("\nReason: \(certInfo.reason)")
      if let hostname = certInfo.hostname {
        print("Hostname: \(hostname)")
      }

      print("Do you want to accept this certificate? [y/N]: ", terminator: " ")

      if let response = readLine()?.lowercased(), response == "y" || response == "yes" {
        print("\n✅ Certificate accepted")
        return true
      } else {
        print("\n❌ Certificate rejected")
        return false
      }
    }

    // Authentication handler - use secure input for passwords
    session.onAuthenticationRequired = { form in
      print("\n" + String(repeating: "=", count: 60))
      print("🔐 Authentication Required")
      print(String(repeating: "=", count: 60))

      if let title = form.title {
        print("\n\(title)")
      }
      if let message = form.message {
        print("\(message)")
      }
      print()

      var filledForm = form

      // Fill in form fields by prompting user
      for (index, field) in filledForm.fields.enumerated() {
        switch field.type {
        case .password:
          // Use secure input for password fields
          print("\(field.label)")
          if let password = SecureInput.read(prompt: "> ") {
            filledForm.fields[index].value = password
          } else {
            print("⚠️  Warning: Empty password entered")
            filledForm.fields[index].value = ""
          }

        case .text:
          print("\(field.label)")
          print("> ", terminator: "")
          if let input = readLine() {
            filledForm.fields[index].value = input
          }

        case .hidden:
          // Skip hidden fields
          continue

        case .select(let options):
          print("\n\(field.label)")
          for (idx, option) in options.enumerated() {
            print("  \(idx + 1). \(option)")
          }
          print("> ", terminator: "")
          if let input = readLine(), let selection = Int(input),
            selection > 0 && selection <= options.count
          {
            filledForm.fields[index].value = options[selection - 1]
          }
        }
      }

      print()
      return filledForm
    }

    // Reconnection handler
    session.onReconnected = {
      print("\n" + String(repeating: "=", count: 60))
      print("🔄 VPN connection reconnected successfully!")
      print(String(repeating: "=", count: 60))
      print()
    }

    // Statistics handler
    session.onStats = { stats in
      let timestamp = DateFormatter.localizedString(
        from: Date(),
        dateStyle: .none,
        timeStyle: .medium
      )

      print("[\(timestamp)] 📊 Statistics:")
      print("  ↑ TX: \(stats.formattedTxBytes) (\(stats.txPackets) packets)")
      print("  ↓ RX: \(stats.formattedRxBytes) (\(stats.rxPackets) packets)")
      print("  ∑ Total: \(stats.formattedTotalBytes)")
    }

    // Disconnect handler
    session.onDisconnect = { reason in
      print("\n" + String(repeating: "=", count: 60))
      if let reason = reason {
        print("❌ Disconnected: \(reason)")
      } else {
        print("✅ Disconnected")
      }
      print(String(repeating: "=", count: 60))
      print()

      // Exit the program after disconnect
      Foundation.exit(0)
    }
  }

  // MARK: - Connection Monitoring

  private func displayConnectionInfo(session: VpnSession) {
    if let ifname = session.interfaceName {
      print("Network Interface: \(ifname)")
    }
    print(
      "Connection Status: \(session.connectionStatus.isConnected ? "Connected ✓" : "Disconnected")")
    print()
  }

  private func startPeriodicStats(session: VpnSession) {
    // Request stats every 10 seconds on a background queue
    let timer = DispatchSource.makeTimerSource(queue: .global())
    timer.schedule(deadline: .now(), repeating: .seconds(10))
    timer.setEventHandler {
      session.requestStats()
    }
    timer.resume()

    Cli.statsTimer = timer
  }

  private func setupSignalHandlers(session: VpnSession) {
    // Ignore default signal handlers
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)

    // Handle SIGINT (Ctrl+C)
    let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sigintSource.setEventHandler {
      print("\n" + String(repeating: "=", count: 60))
      print("🛑 Received interrupt signal, disconnecting...")
      session.disconnect()
      print("✅ Disconnected successfully")
      print(String(repeating: "=", count: 60))
      print()
      Foundation.exit(0)
    }
    sigintSource.resume()
    Cli.signalSources.append(sigintSource)

    // Handle SIGTERM
    let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    sigtermSource.setEventHandler {
      print("\n" + String(repeating: "=", count: 60))
      print("🛑 Received termination signal, disconnecting...")
      session.disconnect()
      print("✅ Disconnected successfully")
      print(String(repeating: "=", count: 60))
      print()
      Foundation.exit(0)
    }
    sigtermSource.resume()
    Cli.signalSources.append(sigtermSource)
  }
}
