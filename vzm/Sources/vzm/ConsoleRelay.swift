import Foundation
import Darwin
import Virtualization

final class ConsoleRelay {
    private let guestReadHandle: FileHandle
    private let guestWriteHandle: FileHandle
    private let ptyMasterFD: Int32

    private var stdinSource: DispatchSourceRead?
    private var ptySource: DispatchSourceRead?
    private var originalTermios: termios?
    private var terminalConfigured = false
    private var isRunning = false

    init() throws {
        var masterFD: Int32 = -1
        var slaveFD: Int32 = -1

        guard openpty(&masterFD, &slaveFD, nil, nil, nil) == 0 else {
            throw CLIError("failed to allocate PTY for guest console: \(String(cString: strerror(errno)))")
        }

        do {
            try SocketSupport.setNonBlocking(STDIN_FILENO)
            try SocketSupport.setNonBlocking(masterFD)
            guestReadHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: true)
            guestWriteHandle = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
            ptyMasterFD = masterFD
        } catch {
            SocketSupport.closeQuietly(masterFD)
            SocketSupport.closeQuietly(slaveFD)
            throw error
        }
    }

    deinit {
        stop()
    }

    func makeAttachment() -> VZFileHandleSerialPortAttachment {
        VZFileHandleSerialPortAttachment(
            fileHandleForReading: guestReadHandle,
            fileHandleForWriting: guestWriteHandle
        )
    }

    func start() throws {
        guard !isRunning else { return }
        isRunning = true

        if isatty(STDIN_FILENO) == 1 {
            var state = termios()
            guard tcgetattr(STDIN_FILENO, &state) == 0 else {
                throw CLIError("failed to read terminal settings: \(String(cString: strerror(errno)))")
            }
            originalTermios = state
            var raw = state
            cfmakeraw(&raw)
            guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else {
                throw CLIError("failed to configure terminal for guest console: \(String(cString: strerror(errno)))")
            }
            terminalConfigured = true
        }

        let stdinSource = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        stdinSource.setEventHandler { [weak self] in
            self?.pump(from: STDIN_FILENO, to: self?.ptyMasterFD ?? -1)
        }
        stdinSource.setCancelHandler { }
        stdinSource.resume()
        self.stdinSource = stdinSource

        let ptySource = DispatchSource.makeReadSource(fileDescriptor: ptyMasterFD, queue: .main)
        ptySource.setEventHandler { [weak self] in
            self?.pump(from: self?.ptyMasterFD ?? -1, to: STDOUT_FILENO)
        }
        ptySource.setCancelHandler { [ptyMasterFD] in
            SocketSupport.closeQuietly(ptyMasterFD)
        }
        ptySource.resume()
        self.ptySource = ptySource
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        stdinSource?.cancel()
        stdinSource = nil
        ptySource?.cancel()
        ptySource = nil

        if terminalConfigured, var originalTermios {
            _ = tcsetattr(STDIN_FILENO, TCSANOW, &originalTermios)
            terminalConfigured = false
        }
    }

    private func pump(from sourceFD: Int32, to destinationFD: Int32) {
        guard sourceFD >= 0, destinationFD >= 0 else {
            return
        }

        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        let bytesRead = read(sourceFD, &buffer, buffer.count)

        if bytesRead <= 0 {
            if bytesRead < 0, errno == EAGAIN || errno == EWOULDBLOCK {
                return
            }
            return
        }

        var totalWritten = 0
        while totalWritten < bytesRead {
            let written = buffer.withUnsafeBytes { bytes in
                write(destinationFD, bytes.baseAddress!.advanced(by: totalWritten), bytesRead - totalWritten)
            }

            if written < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    continue
                }
                return
            }

            totalWritten += written
        }
    }
}
