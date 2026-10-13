import Carbon.HIToolbox
import Combine
import RecorgiCore

/// Registers up to four global hotkeys (start/stop recording, pause/resume
/// recording, toggle microphone, toggle system audio) via Carbon's
/// RegisterEventHotKey —
/// still, as of this writing, the only public macOS API for a true
/// system-wide hotkey that fires even while this app isn't frontmost,
/// *without* requiring Accessibility/Input Monitoring permission the way a
/// raw CGEventTap or NSEvent global monitor would. Each slot re-registers
/// itself automatically whenever the matching RecordingSettings property
/// changes, so the in-app recorder UI (HotkeyRecorderField, RecorgiUI) just
/// has to write to settings and this picks it up.
@MainActor
public final class GlobalHotkeyManager: ObservableObject {
    private enum Slot: UInt32, CaseIterable {
        case startStop = 1
        case toggleMicrophone = 2
        case toggleSystemAudio = 3
        case pauseResume = 4
    }

    private var settings: RecordingSettings?
    private var engine: ScreenRecordingEngine?
    private var cancellables = Set<AnyCancellable>()
    // nonisolated(unsafe): plain C pointers (Carbon opaque refs), not
    // Swift objects — read in deinit (a nonisolated context even on a
    // @MainActor class), mutated only on the main actor during normal
    // operation.
    nonisolated(unsafe) private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    nonisolated(unsafe) private var eventHandlerRef: EventHandlerRef?

    // 'Rcgi' as a four-char OSType, the conventional way to namespace a
    // hotkey ID so it can't collide with another app's registrations.
    private static let signature: OSType = {
        Array("Rcgi".utf8).reduce(OSType(0)) { ($0 << 8) | OSType($1) }
    }()

    public init() {}

    /// Call once, after `settings` and `engine` exist — RecorgiApp does
    /// this from its root `.task`. Safe to call more than once; only the
    /// first call does anything.
    public func start(settings: RecordingSettings, engine: ScreenRecordingEngine) {
        guard self.settings == nil else { return }
        self.settings = settings
        self.engine = engine
        installEventHandler()
        observe(settings)
    }

    deinit {
        // Carbon handles/refs are plain C pointers, not Swift objects —
        // safe to read and tear down from a nonisolated deinit; nothing
        // here is actually MainActor-isolated *data*, only the methods
        // that mutate it during normal operation are.
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
    }

    private func observe(_ settings: RecordingSettings) {
        settings.$startStopHotkey
            .sink { [weak self] in self?.register($0, slot: .startStop) }
            .store(in: &cancellables)
        settings.$toggleMicrophoneHotkey
            .sink { [weak self] in self?.register($0, slot: .toggleMicrophone) }
            .store(in: &cancellables)
        settings.$toggleSystemAudioHotkey
            .sink { [weak self] in self?.register($0, slot: .toggleSystemAudio) }
            .store(in: &cancellables)
        settings.$pauseResumeHotkey
            .sink { [weak self] in self?.register($0, slot: .pauseResume) }
            .store(in: &cancellables)
    }

    private func register(_ binding: HotkeyBinding?, slot: Slot) {
        if let existing = hotKeyRefs[slot.rawValue] {
            UnregisterEventHotKey(existing)
            hotKeyRefs[slot.rawValue] = nil
        }
        guard let binding else { return }
        let id = EventHotKeyID(signature: Self.signature, id: slot.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers.carbonFlags,
            id,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        // A failure here (most likely: the same key combo already
        // registered for another slot — Carbon allows only one
        // registration per combo within this app) just leaves that one
        // hotkey silently inactive rather than crashing; the settings UI
        // is expected to warn about duplicate bindings on its own.
        if status == noErr, let ref {
            hotKeyRefs[slot.rawValue] = ref
            Log.hotkeys.notice("registered \(String(describing: slot), privacy: .public) -> \(binding.displayLabel, privacy: .public)")
        } else {
            Log.hotkeys.error("RegisterEventHotKey failed for \(String(describing: slot), privacy: .public) (\(binding.displayLabel, privacy: .public)), status=\(status, privacy: .public) — likely already bound to another slot")
        }
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            // Carbon dispatches this on the main run loop, but the handler
            // itself is a bare C function pointer with no actor isolation
            // the compiler can see — same situation as SCStreamOutput's
            // callback elsewhere in this target.
            MainActor.assumeIsolated {
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                manager.handle(id: hotKeyID.id)
            }
            return noErr
        }, 1, &eventType, selfPtr, &eventHandlerRef)
    }

    private func handle(id: UInt32) {
        guard let slot = Slot(rawValue: id), let settings, let engine else { return }
        Log.hotkeys.notice("fired: \(String(describing: slot), privacy: .public)")
        switch slot {
        case .startStop:
            Task {
                switch engine.state {
                case .idle:
                    try? await engine.start(settings: settings)
                case .recording, .paused:
                    await engine.stop()
                case .starting, .pausing, .resuming, .stopping:
                    break
                }
            }
        case .pauseResume:
            Task {
                switch engine.state {
                case .recording:
                    await engine.pause()
                case .paused:
                    await engine.resume()
                case .idle, .starting, .pausing, .resuming, .stopping:
                    break
                }
            }
        case .toggleMicrophone:
            settings.isMicrophoneEnabled.toggle()
        case .toggleSystemAudio:
            settings.isSystemAudioEnabled.toggle()
        }
    }
}
