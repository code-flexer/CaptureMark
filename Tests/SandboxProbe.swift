import Darwin
import Foundation

let outgoing = socket(AF_INET, SOCK_STREAM, 0)
var address = sockaddr_in()
address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
address.sin_family = sa_family_t(AF_INET)
address.sin_port = UInt16(9).bigEndian
address.sin_addr.s_addr = inet_addr("127.0.0.1")
let connected = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(outgoing, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
}
let connectError = errno
close(outgoing)
guard connected == -1 && (connectError == EPERM || connectError == EACCES) else {
    fputs("FAIL: sandbox did not deny outgoing connection (errno \(connectError))\n", stderr)
    exit(1)
}
let incoming = socket(AF_INET, SOCK_STREAM, 0)
address.sin_port = 0
let bound = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(incoming, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
}
let bindError = errno
close(incoming)
guard bound == -1 && (bindError == EPERM || bindError == EACCES) else {
    fputs("FAIL: sandbox did not deny incoming socket (errno \(bindError))\n", stderr)
    exit(1)
}
print("PASS: App Sandbox denied outgoing TCP connect and incoming bind on loopback (EPERM/EACCES)")
