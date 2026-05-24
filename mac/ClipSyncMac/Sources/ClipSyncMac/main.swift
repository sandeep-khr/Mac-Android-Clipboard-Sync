import Foundation

print("ClipSyncMac prototype")
print("Watching the macOS clipboard for plain text changes...")
print("Press Ctrl+C to stop.\n")

let watcher = PasteboardWatcher { event in
    print(event.description)
    print("  rawLength: \(event.text.count)")
    print("")
}

watcher.start()
RunLoop.main.run()
