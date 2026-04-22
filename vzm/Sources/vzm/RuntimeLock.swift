import Foundation
import Darwin

final class RuntimeLock {
    private let paths: VMPaths
    private var lockFD: Int32 = -1

    init(paths: VMPaths) {
        self.paths = paths
    }

    func acquire() throws {
        try FileManager.default.createDirectory(at: paths.runtimeDirectory, withIntermediateDirectories: true)

        while true {
            let fd = open(paths.lock.path, O_CREAT | O_EXCL | O_RDWR, S_IRUSR | S_IWUSR)
            if fd >= 0 {
                lockFD = fd
                let pidString = "\(getpid())\n"
                _ = pidString.withCString { write(fd, $0, strlen($0)) }
                try pidString.write(to: paths.pid, atomically: true, encoding: .utf8)
                return
            }

            guard errno == EEXIST else {
                throw CLIError("failed to acquire runtime lock: \(String(cString: strerror(errno)))")
            }

            guard let rawPID = try? String(contentsOf: paths.pid, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
                  let pid = Int32(rawPID)
            else {
                try recoverStaleState()
                continue
            }

            if processIsLiveVZM(pid) {
                throw CLIError("VM is already running with pid \(pid)")
            }

            try recoverStaleState()
        }
    }

    func release() {
        if lockFD >= 0 {
            close(lockFD)
            lockFD = -1
        }
        try? FileManager.default.removeItem(at: paths.lock)
        try? FileManager.default.removeItem(at: paths.pid)
    }

    private func recoverStaleState() throws {
        try? FileManager.default.removeItem(at: paths.lock)
        try? FileManager.default.removeItem(at: paths.pid)
    }

    private func processIsLiveVZM(_ pid: pid_t) -> Bool {
        guard kill(pid, 0) == 0 || errno == EPERM else {
            return false
        }

        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN * 4))
        let length = proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count))
        guard length > 0 else {
            return false
        }

        let executablePath = String(decoding: pathBuffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
        return URL(fileURLWithPath: executablePath).lastPathComponent == "vzm"
    }
}
