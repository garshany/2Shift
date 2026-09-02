@preconcurrency import AppKit

struct ClipboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> ClipboardSnapshot {
        let capturedItems: [[NSPasteboard.PasteboardType: Data]]

        if let pasteboardItems = pasteboard.pasteboardItems {
            capturedItems = pasteboardItems.map { item in
                var capturedTypes: [NSPasteboard.PasteboardType: Data] = [:]
                for type in item.types {
                    if let data = item.data(forType: type) {
                        capturedTypes[type] = data
                    }
                }
                return capturedTypes
            }
        } else {
            capturedItems = []
        }

        return ClipboardSnapshot(items: capturedItems)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let pasteboardItems = items.map { capturedTypes in
            let item = NSPasteboardItem()
            for (type, data) in capturedTypes {
                item.setData(data, forType: type)
            }
            return item
        }

        if !pasteboardItems.isEmpty {
            pasteboard.writeObjects(pasteboardItems)
        }
    }
}
