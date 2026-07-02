// macrift — instant keyboard input-source toggle on the Globe/FN key.
// Headless daemon: listen-only CGEventTap + Carbon TIS. No window, no dock icon.
// Switch-on-release-if-solitary: a plain FN tap switches the layout, but FN used as
// part of a combo (Fn+F-key, Fn+arrow, Fn+Shift, …) is left alone.
// Written from scratch for macrift against public Apple APIs.

import AppKit
import Carbon
import IOKit.hid

// Cycle through the selectable keyboard input sources, mirroring the order
// shown in the macOS input-source menu.
final class InputSourceManager {
    private var sources: [TISInputSource] = []

    init() { reload() }

    func reload() {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            sources = []
            return
        }
        sources = list.filter { src in
            guard let catPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceCategory) else { return false }
            let cat = Unmanaged<CFString>.fromOpaque(catPtr).takeUnretainedValue() as String
            guard cat == (kTISCategoryKeyboardInputSource as String) else { return false }

            guard let selPtr = TISGetInputSourceProperty(src, kTISPropertyInputSourceIsSelectCapable) else { return false }
            let selectable = Unmanaged<CFBoolean>.fromOpaque(selPtr).takeUnretainedValue()
            return CFBooleanGetValue(selectable)
        }
    }

    func toggle() {
        if sources.count < 2 { reload() }              // pick up sources added since launch
        guard sources.count > 1 else { return }

        let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let currentID = id(of: current)

        var next = 0
        if let idx = sources.firstIndex(where: { id(of: $0) == currentID }) {
            next = (idx + 1) % sources.count
        }
        TISSelectInputSource(sources[next])
    }

    private func id(of src: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(src, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
}

// Watch the Globe/FN key. The key toggles the `.maskSecondaryFn` flag, so we track
// its rising/falling edge via `.flagsChanged` and only switch on release if nothing
// else happened while it was held — that distinguishes a plain tap from a shortcut.
//
// A listen-only CGEventTap is used deliberately: it works with the Input Monitoring
// grant (IOHIDRequestAccess). An NSEvent global monitor looks equivalent but is
// gated on Accessibility trust and silently receives no key events without it.
final class FnWatcher {
    private let inputs = InputSourceManager()
    private var tap: CFMachPort?
    private var fnDown = false
    private var sawOther = false

    func start() {
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                let watcher = Unmanaged<FnWatcher>.fromOpaque(refcon!).takeUnretainedValue()
                watcher.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("fnlangswitchd: event tap creation failed — Input Monitoring not granted?")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("fnlangswitchd: event tap active")
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        tap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .flagsChanged:
            let fn = event.flags.contains(.maskSecondaryFn)
            if fn && !fnDown {
                fnDown = true
                sawOther = false                       // FN pressed — start a fresh window
            } else if !fn && fnDown {
                fnDown = false
                if !sawOther { inputs.toggle() }       // FN released solitary — switch
            } else if fn && fnDown {
                sawOther = true                        // another modifier changed (e.g. Fn+Shift)
            }
        case .keyDown:
            if fnDown { sawOther = true }              // a key was used while FN was held
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        default:
            break
        }
    }

    deinit { stop() }
}

final class Daemon: NSObject, NSApplicationDelegate {
    private let watcher = FnWatcher()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)          // no dock icon, no menu bar item

        // Register with TCC and surface the prompt. Without this explicit request a
        // passive global monitor never appears in System Settings → Input Monitoring,
        // so there is nothing for the user to enable.
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        NSLog("fnlangswitchd: input monitoring granted=\(granted)")

        watcher.start()
        NSLog("fnlangswitchd: watching FN key")
    }
}

let app = NSApplication.shared
let daemon = Daemon()
app.delegate = daemon
app.run()
