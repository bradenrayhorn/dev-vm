import Foundation

do {
    let cli = try CLI(arguments: Array(CommandLine.arguments.dropFirst()))
    try cli.run()
} catch let error as CLIError {
    fputs("error: \(error.message)\n", stderr)
    exit(EXIT_FAILURE)
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(EXIT_FAILURE)
}
