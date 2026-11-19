import ArgumentParser
import Foundation
import MacMoshKit

struct SwiftBarCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftbar",
        abstract: "Print the menu in SwiftBar's text format. Always exits 0, so SwiftBar shows no error icon."
    )

    func run() async {
        print(await menuText(), terminator: "")
    }

    /// The whole plugin output. Anything that goes wrong becomes a one-line menu.
    private func menuText() async -> String {
        let path = ownPath()
        guard PlainWords.isPlain(path) else {
            return SwiftBarRenderer.errorMenu(
                "MacMosh is at a path with spaces or unusual characters, which SwiftBar can't pass on: "
                + "\(path). Move it to a plain path such as ~/.local/bin/macmosh.")
        }
        do {
            let paths = Paths.standard()
            let store = WorkhorseStore(paths: paths)
            let list = try store.load()
            let gathered = await MenuData.gather(list, checker: makeChecker(paths: paths), budget: .seconds(20))
            // Only a workhorse that was checked has anything to save.
            let checked = gathered.compactMap { entry -> CheckResult? in
                if case .checked(let result) = entry { return result }
                return nil
            }
            save(checked, in: store)
            return SwiftBarRenderer.render(MenuModel.build(gathered), macmoshPath: path)
        } catch {
            return SwiftBarRenderer.errorMenu(StatusFormat.storeMessage(error))
        }
    }

    /// This program's own absolute path, for the `bash=` values.
    private func ownPath() -> String {
        let folder = FileManager.default.currentDirectoryPath
        let raw = Bundle.main.executablePath ?? CommandLine.arguments.first ?? "macmosh"
        return SwiftBarRenderer.absolutePath(of: raw, in: folder)
    }
}
