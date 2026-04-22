import Foundation
import Darwin

enum SocketSupport {
    static func createListeningSocket(port: UInt16) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw CLIError("failed to create listening socket: \(String(cString: strerror(errno)))")
        }

        var yes: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw CLIError("failed to configure listening socket: \(message)")
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw CLIError("failed to bind 127.0.0.1:\(port): \(message)")
        }

        guard listen(fd, SOMAXCONN) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw CLIError("failed to listen on 127.0.0.1:\(port): \(message)")
        }

        return fd
    }

    static func setNonBlocking(_ fd: Int32) throws {
        let flags = fcntl(fd, F_GETFL)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw CLIError("failed to set nonblocking mode: \(String(cString: strerror(errno)))")
        }
    }

    static func closeQuietly(_ fd: Int32) {
        guard fd >= 0 else { return }
        _ = shutdown(fd, SHUT_RDWR)
        _ = close(fd)
    }
}
