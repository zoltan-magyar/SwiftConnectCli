//
//  VpnContext+CallbackHandlers.swift
//  OpenConnectKit
//
//  OpenConnect C callback implementations
//

import COpenConnect
import Foundation

// MARK: - C Callback Entry Points

// C callback for log messages. Called from C shim on mainloop thread.
// Must be @_cdecl for C interop.
@_cdecl("progressCallback")
internal func progressCallback(
  privdata: UnsafeMutableRawPointer?,
  level: CInt,
  formatted_message: UnsafePointer<CChar>?
) {
  guard
    let privdata = privdata,
    let formatted_message = formatted_message
  else {
    return
  }

  let context = VpnContext.extractContext(from: privdata)

  var message = String(cString: formatted_message)

  // Strip trailing newline
  if message.hasSuffix("\n") {
    message = String(message.dropLast())
  }

  // Convert C log level to Swift LogLevel
  let logLevel: LogLevel
  switch level {
  case 0: logLevel = .error
  case 1: logLevel = .info
  case 2: logLevel = .debug
  case 3: logLevel = .trace
  default: logLevel = .info
  }

  context.session.handleProgress(level: logLevel, message: message)
}

// C callback for certificate validation. Returns 0 to accept, 1 to reject.
internal func validatePeerCertCallback(
  privdata: UnsafeMutableRawPointer?,
  reason: UnsafePointer<CChar>?
) -> CInt {
  guard let privdata = privdata else {
    return 1
  }

  let context = VpnContext.extractContext(from: privdata)
  let certInfo = CertificateInfo(from: reason)
  let accepted = context.session.handleCertificateValidation(certInfo: certInfo)

  return accepted ? 0 : 1
}

// C callback for authentication forms. Returns 0 for success, 1 for failure.
internal func processAuthFormCallback(
  privdata: UnsafeMutableRawPointer?,
  form: UnsafeMutablePointer<oc_auth_form>?
) -> CInt {
  guard
    let privdata = privdata,
    let form = form
  else {
    return 1
  }

  let context = VpnContext.extractContext(from: privdata)

  let authForm = AuthenticationForm(from: form)
  let filledForm = context.session.handleAuthenticationForm(authForm)
  filledForm.apply(to: form)

  return 0
}

// C callback when reconnection succeeds. Updates status to .connected.
internal func reconnectedCallback(privdata: UnsafeMutableRawPointer?) {
  guard let privdata = privdata else {
    return
  }

  let context = VpnContext.extractContext(from: privdata)
  context.updateStatus(.connected)
}

// C callback for traffic statistics. Triggered by requestStats() command.
internal func statsCallback(
  privdata: UnsafeMutableRawPointer?,
  stats: UnsafePointer<oc_stats>?
) {
  guard
    let privdata = privdata,
    let stats = stats
  else {
    return
  }

  let context = VpnContext.extractContext(from: privdata)

  let vpnStats = VpnStats(
    txPackets: stats.pointee.tx_pkts,
    txBytes: stats.pointee.tx_bytes,
    rxPackets: stats.pointee.rx_pkts,
    rxBytes: stats.pointee.rx_bytes
  )

  context.session.handleStats(vpnStats)
}

// C callback for TUN device setup. Called during connection establishment.
internal func setupTunCallback(privdata: UnsafeMutableRawPointer?) {
  guard let privdata = privdata else {
    return
  }

  let context = VpnContext.extractContext(from: privdata)

  context.updateStatus(.connecting(stage: "Configuring tunnel"))

  guard let vpncScriptPath = try? context.findVpncScript() else {
    context.setupError = .vpncScriptFailed
    return
  }

  let vpncScriptPtr = vpncScriptPath.withCString { strdup($0) }
  let interfaceNamePtr = context.session.configuration.interfaceName?.withCString { strdup($0) }

  defer {
    free(vpncScriptPtr)
    free(interfaceNamePtr)
  }

  let ret = openconnect_setup_tun_device(context.vpnInfo, vpncScriptPtr, interfaceNamePtr)
  if ret != 0 {
    context.setupError = .tunSetupFailed
  } else {
    // TUN device setup succeeded - update status to connected
    // The interface name is now available via openconnect_get_ifname()
    context.updateStatus(.connected)
  }
}

// MARK: - Helper Methods

extension VpnContext {
  // Extract VpnContext from C callback pointer
  static func extractContext(from privdata: UnsafeMutableRawPointer) -> VpnContext {
    return Unmanaged<VpnContext>.fromOpaque(privdata).takeUnretainedValue()
  }

  // Find vpnc-script: use configured path or search common locations
  internal func findVpncScript() throws -> String {

    if let configuredPath = session.configuration.vpncScript {
      guard FileManager.default.isExecutableFile(atPath: configuredPath) else {
        throw VpnError.vpncScriptFailed
      }
      return configuredPath
    }

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
