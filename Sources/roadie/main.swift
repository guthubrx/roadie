import Foundation
import RoadieDaemon

// Client mince : les commandes d'action passent par le daemon (socket) quand il tourne,
// le reste s'exécute ici avec le même router (contrat cli-daemon-socket.md).
let arguments = Array(CommandLine.arguments.dropFirst())
let response = CommandSocketClient.execute(argv: arguments, cwd: FileManager.default.currentDirectoryPath) {
    CLICommandRouter(streamSink: { FileHandle.standardOutput.write(Data($0.utf8)) }).run(arguments)
}
FileHandle.standardOutput.write(Data(response.stdout.utf8))
FileHandle.standardError.write(Data(response.stderr.utf8))
exit(response.exitCode)
