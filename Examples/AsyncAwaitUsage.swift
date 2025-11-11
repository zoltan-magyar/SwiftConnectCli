//
//  AsyncAwaitUsage.swift
//  OpenConnectKit Examples
//
//  Demonstrates how to use OpenConnectKit with async/await in SwiftUI
//

import OpenConnectKit
import SwiftUI

// MARK: - SwiftUI Example

/// Example SwiftUI view using async/await with OpenConnectKit
struct VpnConnectionView: View {
  @StateObject private var viewModel = VpnViewModel()

  var body: some View {
    VStack(spacing: 20) {
      // Status display
      VStack {
        Text("VPN Status")
          .font(.headline)
        Text(viewModel.statusText)
          .font(.body)
          .foregroundColor(viewModel.statusColor)
      }

      // Connection controls
      HStack {
        Button("Connect") {
          Task {
            await viewModel.connect()
          }
        }
        .disabled(viewModel.isConnected)

        Button("Disconnect") {
          Task {
            await viewModel.disconnect()
          }
        }
        .disabled(!viewModel.isConnected)
      }

      // Statistics
      if viewModel.isConnected {
        VStack(alignment: .leading, spacing: 8) {
          Text("Statistics")
            .font(.headline)

          if let stats = viewModel.currentStats {
            Text("↑ TX: \(stats.formattedTxBytes)")
            Text("↓ RX: \(stats.formattedRxBytes)")
            Text("Total: \(stats.formattedTotalBytes)")
          } else {
            Text("Requesting statistics...")
              .foregroundColor(.secondary)
          }
        }
      }

      // Log messages
      ScrollView {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(viewModel.logMessages, id: \.self) { message in
            Text(message)
              .font(.system(.caption, design: .monospaced))
              .foregroundColor(.secondary)
          }
        }
      }
      .frame(maxHeight: 200)
    }
    .padding()
  }
}

// MARK: - ViewModel with Async/Await

@MainActor
class VpnViewModel: ObservableObject {
  @Published var status: ConnectionStatus = .disconnected(error: nil)
  @Published var currentStats: VpnStats?
  @Published var logMessages: [String] = []

  private var asyncSession: AsyncVpnSession?
  private var statsTimer: Timer?

  var statusText: String {
    switch status {
    case .disconnected(let error):
      if let error = error {
        return "Disconnected: \(error.localizedDescription)"
      }
      return "Disconnected"
    case .connecting(let stage):
      return "Connecting: \(stage)"
    case .connected:
      return "Connected ✓"
    case .reconnecting:
      return "Reconnecting..."
    }
  }

  var statusColor: Color {
    switch status {
    case .connected:
      return .green
    case .connecting, .reconnecting:
      return .orange
    case .disconnected(let error):
      return error == nil ? .primary : .red
    }
  }

  var isConnected: Bool {
    if case .connected = status {
      return true
    }
    return false
  }

  func connect() async {
    guard asyncSession == nil else { return }

    let config = VpnConfiguration(
      serverURL: URL(string: "https://vpn.example.com")!,
      logLevel: .info
    )

    let session = VpnSession(configuration: config)
    asyncSession = session.async

    // Set up authentication handler
    asyncSession?.onAuthenticationRequired = { form in
      var filledForm = form
      // In a real app, you'd show a form UI and get user input
      // For this example, we'll just show it's possible
      return filledForm
    }

    // Set up certificate validation handler
    asyncSession?.onCertificateValidation = { certInfo in
      // In a real app, you'd show an alert and let user decide
      // For this example, we accept all certificates
      return true
    }

    do {
      try asyncSession?.connect()

      // Start listening for updates
      await startListening()
    } catch {
      print("Connection failed: \(error)")
    }
  }

  func disconnect() async {
    asyncSession?.disconnect()
    stopStatsTimer()
  }

  /// Start listening to VPN session updates using async streams
  private func startListening() async {
    guard let asyncSession = asyncSession else { return }

    // Run all streams concurrently
    await withTaskGroup(of: Void.self) { group in
      // Listen for status updates
      group.addTask {
        for await newStatus in asyncSession.statusUpdates {
          await MainActor.run {
            self.status = newStatus

            // Start stats timer when connected
            if case .connected = newStatus {
              self.startStatsTimer()
            } else {
              self.stopStatsTimer()
              self.currentStats = nil
            }
          }
        }
      }

      // Listen for log messages
      group.addTask {
        for await (message, level) in asyncSession.logMessages {
          await MainActor.run {
            let logEntry = "[\(level)] \(message)"
            self.logMessages.append(logEntry)

            // Keep only last 50 messages
            if self.logMessages.count > 50 {
              self.logMessages.removeFirst()
            }
          }
        }
      }

      // Listen for statistics
      group.addTask {
        for await stats in asyncSession.statisticsUpdates {
          await MainActor.run {
            self.currentStats = stats
          }
        }
      }
    }
  }

  private func startStatsTimer() {
    stopStatsTimer()

    statsTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
      _ = self?.asyncSession?.requestStats()
    }
    // Request stats immediately
    asyncSession?.requestStats()
  }

  private func stopStatsTimer() {
    statsTimer?.invalidate()
    statsTimer = nil
  }
}

// MARK: - Traditional Callback Example (for comparison)

/// Example using traditional callbacks instead of async/await
class VpnManager {
  private var session: VpnSession?

  var onStatusChanged: ((ConnectionStatus) -> Void)?
  var onStatsReceived: ((VpnStats) -> Void)?

  func connect(serverURL: URL) {
    let config = VpnConfiguration(
      serverURL: serverURL,
      logLevel: .info
    )

    session = VpnSession(configuration: config)

    // Traditional callback style
    session?.onStatusChanged = { [weak self] status in
      // Need to dispatch to main queue for UI updates
      DispatchQueue.main.async {
        self?.onStatusChanged?(status)
      }
    }

    session?.onLog = { message, level in
      print("[\(level)] \(message)")
    }

    session?.onStats = { [weak self] stats in
      DispatchQueue.main.async {
        self?.onStatsReceived?(stats)
      }
    }

    do {
      try session?.connect()
    } catch {
      print("Connection failed: \(error)")
    }
  }

  func disconnect() {
    session?.disconnect()
    session = nil
  }
}

// MARK: - Notes

/*
 ## Key Improvements with AsyncVpnSession

 ### Type Safety
 The `session.async` property returns an `AsyncVpnSession` wrapper that provides
 a completely separate API. This prevents accidentally mixing callbacks and async streams.

 ### Before (Error-Prone):
 ```swift
 session.onStatusChanged = { status in
     // This won't be called if you use statusUpdates!
 }

 for await status in session.statusUpdates {
     // This overwrites the callback above
 }
 ```

 ### After (Type-Safe):
 ```swift
 // Choose one style explicitly:

 // Option 1: Callbacks
 session.onStatusChanged = { status in
     print(status)
 }

 // Option 2: Async (completely separate API)
 let asyncSession = session.async
 for await status in asyncSession.statusUpdates {
     print(status)
 }
 ```

 ### Benefits:
 - Explicit API choice: `session` for callbacks, `session.async` for async/await
 - Type system prevents accidental mixing
 - Clear separation of concerns
 - @MainActor isolation on AsyncVpnSession
 - All the same functionality in both APIs

 ### When to Use Each:

 **Use Callbacks (`session.onXXX`) when:**
 - Building CLI tools
 - Simple event handling
 - Integrating with existing callback-based code
 - Need maximum flexibility

 **Use Async/Await (`session.async`) when:**
 - Building SwiftUI apps
 - Need MainActor isolation
 - Want structured concurrency
 - Working with other async APIs
 */
