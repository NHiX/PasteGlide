import AppKit
import Carbon
import CryptoKit
import Foundation
import ImageIO
import SQLite3
import UniformTypeIdentifiers
import Vision

final class HotKeyController {
    private var hotKeyRef: EventHotKeyRef?
    private let callback: () -> Void
    private var eventHandler: EventHandlerRef?

    init(callback: @escaping () -> Void) {
        self.callback = callback
    }

    func register() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        if eventHandler == nil {
            InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
                guard let userData else { return noErr }
                let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
                controller.callback()
                return noErr
            }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        }

        let hotKeyID = EventHotKeyID(signature: OSType(UInt32("CLPC".fourCharCode)), id: 1)
        let modifiers = UInt32(cmdKey | optionKey)
        RegisterEventHotKey(AppSettings.shared.hotKeyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
