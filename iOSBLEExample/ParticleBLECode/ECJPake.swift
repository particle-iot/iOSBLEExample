//
//  ECJPake.swift
//  iOSBLEExample
//
//  Created by Nick Lambourne on 10/20/22.
//

import Foundation
import libmbedtls

public protocol ecJPAKETLSDelegate {
    func handshakeCompleted()
}

public class ecJPAKE {

    enum State {
        case NEW
        case READ_ROUND1
        case WRITE_ROUND1
        case READ_ROUND2
        case WRITE_ROUND2
        case READ_CONFIRM
        case WRITE_CONFIRM
        case DONE
        case FAILED
    }
    
    public static var delegate: ecJPAKETLSDelegate?
    
    public static var jpakeContext: mbedtls_ecjpake_context!
//
//    public static var readCallbackBuffer: [UInt8]?
//
//    public typealias sslWriteCallback = (UnsafeMutableRawPointer?, UnsafePointer<UInt8>?, Int) ->  Int32
//    public typealias sslReadCallback = (UnsafeMutableRawPointer?, UnsafeMutablePointer<UInt8>?, Int) ->  Int32
//
//    static var sslWriteCallbackFunc: sslWriteCallback!
//    static var sslReadCallbackFunc: sslReadCallback!

    //public static var currentHandshakeState: HandshakeStep = .helloRequest

    static var ciphers: Array<Int32>!

    public init(key: [UInt8]) throws {
        ecJPAKE.jpakeContext = mbedtls_ecjpake_context()

        mbedtls_ecjpake_init(&ecJPAKE.jpakeContext)
        
        mbedtls_ecjpake_setup(&ecJPAKE.jpakeContext, MBEDTLS_ECJPAKE_CLIENT, MBEDTLS_MD_SHA256, MBEDTLS_ECP_DP_SECP256R1, key, key.count)
    }

}
