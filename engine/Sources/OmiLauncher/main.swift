import AppKit
import Foundation

let targetURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Applications/ReadAloudService.app")

guard FileManager.default.fileExists(atPath: targetURL.path) else {
    let alert = NSAlert()
    alert.messageText = "未找到 Omi"
    alert.informativeText = "请先将 ReadAloudService.app 安装到个人 Applications 目录。"
    alert.runModal()
    exit(1)
}

guard NSWorkspace.shared.open(targetURL) else {
    let alert = NSAlert()
    alert.messageText = "无法启动 Omi"
    alert.informativeText = "请检查 ReadAloudService.app 是否完整。"
    alert.runModal()
    exit(1)
}
