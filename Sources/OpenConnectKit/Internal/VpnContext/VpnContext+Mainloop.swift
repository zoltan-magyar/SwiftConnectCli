//
//  VpnContext+Mainloop.swift
//  OpenConnectKit
//
//  Mainloop management extension for VpnContext
//

import COpenConnect
import Foundation

// MARK: - Mainloop Management

extension VpnContext {
  // Start mainloop on background thread. Returns immediately.
  internal func startMainloop() {
    stateLock.lock()

    mainloopThread = Thread { [weak self] in
      guard let self = self else { return }
      // Status set to .connected in setupTunCallback after TUN setup
      self.runMainloopThread()
    }
    mainloopThread?.name = "com.openconnect.mainloop"
    mainloopThread?.start()

    stateLock.unlock()
  }

  // Stop mainloop via cancel command. Waits up to 5s.
  internal func stopMainloop() {
    stateLock.lock()
    guard case .connected = connectionStatus else {
      stateLock.unlock()
      return
    }
    stateLock.unlock()

    sendCommand(.cancel)

    let deadline = Date().addingTimeInterval(5.0)
    let semaphore = DispatchSemaphore(value: 0)

    while Date() < deadline {
      stateLock.lock()
      if case .disconnected = connectionStatus {
        stateLock.unlock()
        break
      }
      stateLock.unlock()
      _ = semaphore.wait(timeout: .now() + 0.1)
    }

    mainloopThread = nil
  }

  // Mainloop execution. Loops until error or cancel.
  private func runMainloopThread() {
    while true {
      let ret = openconnect_mainloop(
        vpnInfo,
        session.configuration.reconnectTimeout,
        session.configuration.reconnectInterval
      )

      if ret != 0 {
        break
      }
    }

    let error: VpnError?
    stateLock.lock()
    switch connectionStatus {
    case .disconnected:
      stateLock.unlock()
      error = nil
    default:
      stateLock.unlock()
      error = setupError ?? .connectionFailed(reason: "Connection lost")
    }

    updateStatus(.disconnected(error: error))

    setupError = nil
  }
}
