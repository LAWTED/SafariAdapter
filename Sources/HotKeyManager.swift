import Carbon
import Foundation

/// Registers Safari-style command shortcuts only while Safari (or the command
/// bar itself) is frontmost. Carbon hotkeys reliably override Safari's own menu
/// equivalents without requiring Input Monitoring permission.
@MainActor
final class HotKeyManager {
    private enum HotKeyID: UInt32 {
        case commandBar = 1
        case sidebar = 2
    }

    private static let tabHotKeyBase: UInt32 = 100
    private static let tabKeyCodes: [UInt32] = [
        UInt32(kVK_ANSI_1),
        UInt32(kVK_ANSI_2),
        UInt32(kVK_ANSI_3),
        UInt32(kVK_ANSI_4),
        UInt32(kVK_ANSI_5),
        UInt32(kVK_ANSI_6),
        UInt32(kVK_ANSI_7),
        UInt32(kVK_ANSI_8),
        UInt32(kVK_ANSI_9)
    ]

    private let openCommandBar: () -> Void
    private let toggleSidebar: () -> Void
    private let selectTab: (Int) -> Void
    private var commandBarRef: EventHotKeyRef?
    private var sidebarRef: EventHotKeyRef?
    private var tabRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var isRegistered = false
    private var pressedHotKeys = Set<UInt32>()

    init(
        openCommandBar: @escaping () -> Void,
        toggleSidebar: @escaping () -> Void,
        selectTab: @escaping (Int) -> Void
    ) {
        self.openCommandBar = openCommandBar
        self.toggleSidebar = toggleSidebar
        self.selectTab = selectTab
        installEventHandler()
    }

    deinit {
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func register() {
        guard !isRegistered else { return }

        let signature = OSType(0x53464144) // "SFAD"
        let commandID = EventHotKeyID(signature: signature, id: HotKeyID.commandBar.rawValue)
        let sidebarID = EventHotKeyID(signature: signature, id: HotKeyID.sidebar.rawValue)

        let commandStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_L),
            UInt32(cmdKey),
            commandID,
            GetApplicationEventTarget(),
            0,
            &commandBarRef
        )
        let sidebarStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_S),
            UInt32(cmdKey),
            sidebarID,
            GetApplicationEventTarget(),
            0,
            &sidebarRef
        )

        var tabStatuses: [OSStatus] = []
        for (offset, keyCode) in Self.tabKeyCodes.enumerated() {
            let hotKeyID = EventHotKeyID(
                signature: signature,
                id: Self.tabHotKeyBase + UInt32(offset)
            )
            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                keyCode,
                UInt32(cmdKey),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            tabStatuses.append(status)
            if let hotKeyRef { tabRefs.append(hotKeyRef) }
        }

        NSLog(
            "SafariAdapter hotkeys registered — Command-L: %d, Command-S: %d, Command-1…9: %@",
            commandStatus,
            sidebarStatus,
            tabStatuses.map(String.init).joined(separator: ",")
        )
        isRegistered = commandStatus == noErr || sidebarStatus == noErr || tabStatuses.contains(noErr)
    }

    func unregister() {
        guard isRegistered else { return }
        if let commandBarRef { UnregisterEventHotKey(commandBarRef) }
        if let sidebarRef { UnregisterEventHotKey(sidebarRef) }
        tabRefs.forEach { UnregisterEventHotKey($0) }
        commandBarRef = nil
        sidebarRef = nil
        tabRefs.removeAll()
        pressedHotKeys.removeAll()
        isRegistered = false
    }

    private func installEventHandler() {
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()

        _ = eventTypes.withUnsafeMutableBufferPointer { eventTypeBuffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, userData in
                guard let event, let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }

                let eventKind = GetEventKind(event)
                Task { @MainActor in
                    manager.handleHotKey(id: hotKeyID.id, eventKind: eventKind)
                }
                return noErr
                },
                eventTypeBuffer.count,
                eventTypeBuffer.baseAddress,
                context,
                &eventHandler
            )
        }
    }

    private func handleHotKey(id: UInt32, eventKind: UInt32) {
        if eventKind == UInt32(kEventHotKeyReleased) {
            pressedHotKeys.remove(id)
            return
        }

        guard pressedHotKeys.insert(id).inserted else { return }
        switch id {
        case HotKeyID.commandBar.rawValue:
            openCommandBar()
        case HotKeyID.sidebar.rawValue:
            toggleSidebar()
        case Self.tabHotKeyBase..<(Self.tabHotKeyBase + UInt32(Self.tabKeyCodes.count)):
            selectTab(Int(id - Self.tabHotKeyBase) + 1)
        default:
            break
        }
    }
}
