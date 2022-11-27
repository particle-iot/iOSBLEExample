import Foundation
import libmbedtls


public class Sha256 {
    
    let hmac: Bool
    
    static let HASH_SIZE: Int = 32
    static let BLOCK_SIZE: Int = 64
    
    var mbedMDContextAlloc: UnsafeMutablePointer<mbedtls_md_context_t>?
    
    init(hmac: Bool = false) {
        self.hmac = hmac

        mbedMDContextAlloc = UnsafeMutablePointer<mbedtls_md_context_t>.allocate(capacity: 1)
        
        mbedtls_md_init(mbedMDContextAlloc!);
        mbedtls_md_setup(mbedMDContextAlloc!, mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), self.hmac ? 1 : 0)
    }
    
    deinit {
        mbedMDContextAlloc?.deallocate()
    }
    
    public func start() {
        mbedtls_md_starts(mbedMDContextAlloc!)
    }
    
    public func finish() -> [UInt8] {
        let uint8Pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: Sha256.HASH_SIZE)
        
        if self.hmac {
            let ret = mbedtls_md_hmac_finish(mbedMDContextAlloc!, uint8Pointer)
            assert( ret == 0 )
        } else {
            let ret = mbedtls_md_finish(mbedMDContextAlloc!, uint8Pointer)
            assert( ret == 0 )
        }
        
        let hash = Array(UnsafeBufferPointer(start: uint8Pointer, count: Sha256.HASH_SIZE))

        uint8Pointer.deinitialize(count: Sha256.HASH_SIZE)
        uint8Pointer.deallocate()
        
        return hash
    }
    
    public func update(data: [UInt8]) {
        let uint8Pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        uint8Pointer.initialize(from: data, count: data.count)
        
        if self.hmac {
            let ret = mbedtls_md_hmac_update(mbedMDContextAlloc!, uint8Pointer, data.count)
            assert( ret == 0 )
        } else {
            let ret = mbedtls_md_update(mbedMDContextAlloc!, uint8Pointer, data.count)
            assert( ret == 0 )
        }
        
        uint8Pointer.deinitialize(count: data.count)
        uint8Pointer.deallocate()
    }
    
    func copyFrom(src: Sha256) {
        let ret = mbedtls_md_clone(mbedMDContextAlloc!, src.mbedMDContextAlloc!);
        assert( ret == 0 )
    }
}


public class HMACSha256 : Sha256 {
    
    init() {
        super.init(hmac: true)
    }
    
    public func start(key: [UInt8]) {
        let uint8Pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: key.count)
        uint8Pointer.initialize(from: key, count: key.count)
        
        let ret = mbedtls_md_hmac_starts(mbedMDContextAlloc!, uint8Pointer, key.count)
        assert( ret == 0 )
        
        uint8Pointer.deinitialize(count: key.count)
        uint8Pointer.deallocate()
    }
}
