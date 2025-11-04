//
//  ValidatePeerCert.swift
//  SwiftConnectCli
//
//  Created by Zoltán Magyar on 2025. 10. 27..
//

import COpenConnect
import Foundation

func validatePeerCertCallback(privdata: UnsafeMutableRawPointer?, reason: UnsafePointer<CChar>?)
    -> CInt
{
    guard let privdata = privdata else {
        print("Privdata is nil")
        return 1
    }
    let vpnContext = Unmanaged<VpnContext>.fromOpaque(privdata).takeUnretainedValue()

    vpnContext.print_cert()

    if let reason { print("Reason:", String(cString: reason)) }

    return 0
}
