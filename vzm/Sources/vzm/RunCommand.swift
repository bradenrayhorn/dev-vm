import Foundation

struct RunCommand {
    let store: VMStore

    func run(options: RunOptions) throws {
        guard store.vmExists(options.name) else {
            throw CLIError("VM '\(options.name.rawValue)' does not exist")
        }

        let config = try store.loadConfig(name: options.name)
        let bundle = try store.validateGuestBundle(config.bundlePath)
        let paths = store.paths(for: options.name)
        let machineIdentifier = try store.loadMachineIdentifier(name: options.name)

        let probeFD = try SocketSupport.createListeningSocket(port: config.hostSSHPort)
        SocketSupport.closeQuietly(probeFD)

        let runtimeLock = RuntimeLock(paths: paths)
        try runtimeLock.acquire()
        defer {
            runtimeLock.release()
        }

        let runner = VirtualMachineRunner(
            config: config,
            bundle: bundle,
            machineIdentifier: machineIdentifier
        ) { message in
            let output = message.contains("failure") || message.contains("error") ? stderr : stdout
            fputs("\(message)\n", output)
        }
        try runner.run()
    }
}
