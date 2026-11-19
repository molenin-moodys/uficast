import AppKit

@MainActor
enum AppMenu {
    static func make(target: AnyObject, settings: Selector, quit: Selector, find: Selector) -> NSMenu {
        func item(_ title: String, _ action: Selector, key: String = "", target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target
            return item
        }
        let main = NSMenu()
        func append(_ title: String, items: [NSMenuItem]) {
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            parent.submenu = menu
            main.addItem(parent)
        }
        let customSettings = item("Settings…", settings, key: "p", target: target)
        customSettings.isHidden = true
        customSettings.allowsKeyEquivalentWhenHidden = true
        let hideOthers = item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        append("Uficast", items: [
            item("Settings…", settings, key: ",", target: target), customSettings, .separator(),
            item("Hide Uficast", #selector(NSApplication.hide(_:)), key: "h"), hideOthers,
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))), .separator(),
            item("Quit Uficast", quit, key: "q", target: target),
        ])
        append("File", items: [item("Close Window", #selector(NSWindow.performClose(_:)), key: "w")])
        var edit: [NSMenuItem] = []
        for (title, action, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "z"),
            ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            let command = item(title, NSSelectorFromString(action), key: key)
            if title == "Redo" { command.keyEquivalentModifierMask = [.command, .shift] }
            edit.append(command)
        }
        edit += [.separator(), item("Find…", find, key: "f", target: target)]
        append("Edit", items: edit)
        append("Window", items: [item("Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m")])
        return main
    }
}
