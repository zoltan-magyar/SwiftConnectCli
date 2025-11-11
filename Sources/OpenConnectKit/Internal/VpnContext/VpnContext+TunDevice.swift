//
//  VpnContext+TunDevice.swift
//  OpenConnectKit
//
//  TUN device management extension for VpnContext
//

import COpenConnect
import Foundation

// MARK: - TUN Device Management

extension VpnContext {
  /// Finds the vpnc-script in common installation locations.
  internal func findVpncScript() throws -> String {
    // Use configured path if provided
    if let configuredPath = configuration.vpncScript {
      guard FileManager.default.isExecutableFile(atPath: configuredPath) else {
        throw VpnError.vpncScriptFailed
      }
      return configuredPath
    }

    // Search common locations
    let commonPaths = [
      "/opt/homebrew/etc/vpnc-scripts/vpnc-script",
      "/usr/local/etc/vpnc-scripts/vpnc-script",
      "/usr/share/vpnc-scripts/vpnc-script",
      "/etc/vpnc/vpnc-script",
      "/usr/local/share/vpnc-scripts/vpnc-script",
    ]

    for path in commonPaths {
      if FileManager.default.isExecutableFile(atPath: path) {
        return path
      }
    }

    throw VpnError.vpncScriptFailed
  }
}

// MARK: - C Callback

/// C callback invoked by OpenConnect to set up the TUN device.
internal func setupTunCallback(privdata: UnsafeMutableRawPointer?) {
  guard let privdata = privdata else {
    return
  }

  let context = Unmanaged<VpnContext>.fromOpaque(privdata).takeUnretainedValue()

  // Find vpnc-script path
  guard let vpncScriptPath = try? context.findVpncScript() else {
    context.lastError = .vpncScriptFailed
    return
  }

  // Prepare C strings
  let vpncScriptPtr = vpncScriptPath.withCString { strdup($0) }
  let interfaceNamePtr = context.configuration.interfaceName?.withCString { strdup($0) }

  defer {
    free(vpncScriptPtr)
    free(interfaceNamePtr)
  }

  // Setup TUN device
  let ret = openconnect_setup_tun_device(context.vpnInfo, vpncScriptPtr, interfaceNamePtr)
  if ret != 0 {
    context.lastError = .tunSetupFailed
  }
}
