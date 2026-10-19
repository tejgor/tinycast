// Posts update-fork.sh's notifications as "Tinycast Update", under Tinycast's icon.
// `notify <message>` posts one and exits; launched with no message, as a click on one does, it
// opens the update log that sits beside the bundle.
import Foundation
import UserNotifications

let message = CommandLine.arguments.dropFirst().joined(separator: " ")
guard !message.isEmpty else {
    let log = Bundle.main.bundleURL.deletingLastPathComponent().appending(path: "update.log")
    let open = Process()
    open.executableURL = URL(filePath: "/usr/bin/open")
    open.arguments = ["-a", "Console", log.path]
    try? open.run()
    open.waitUntilExit()
    exit(0)
}

// The first run waits on the permission prompt, which must never hold up an update for long.
Task {
    try? await Task.sleep(for: .seconds(30))
    exit(1)
}

let center = UNUserNotificationCenter.current()
guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { exit(1) }
let content = UNMutableNotificationContent()
content.body = message
do {
    try await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    exit(0)
} catch {
    exit(1)
}
