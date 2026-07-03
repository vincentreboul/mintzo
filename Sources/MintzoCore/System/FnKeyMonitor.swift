import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Source des transitions de la touche Fn/Globe (keycode 63) via CGEventTap
/// `flagsChanged` en listen-only, sur un thread dédié.
///
/// - Exige la permission Accessibility : sans elle, `start()` retourne `nil`
///   et le service continue avec le seul raccourci configurable — jamais de crash.
/// - Réactive le tap désactivé par le système (`tapDisabledByTimeout`, piège
///   documenté : TCC lie la permission à la signature du binaire).
/// - Listen-only : ne consomme JAMAIS l'événement — le double-appui Fn de la
///   dictée système Apple continue de fonctionner (bug kitty#9661 évité).
@MainActor
public final class FnKeyMonitor: FnKeyEventSource {

    /// État partagé entre le thread du tap (callback C) et le monitor.
    /// `@unchecked Sendable` : `tap`/`runLoop` sont écrits une fois avant le
    /// démarrage du thread puis seulement lus ; la continuation est Sendable ;
    /// le monitor garde la boîte vivante strictement plus longtemps que le tap.
    final class TapBox: @unchecked Sendable {
        let continuation: AsyncStream<FnKeyTransition>.Continuation
        var tap: CFMachPort?
        var runLoop: CFRunLoop?

        init(continuation: AsyncStream<FnKeyTransition>.Continuation) {
            self.continuation = continuation
        }
    }

    private var box: TapBox?
    private let accessibilityProbe: @Sendable () -> Bool

    /// - Parameter accessibilityProbe: injectable pour les tests ; défaut `AXIsProcessTrusted`.
    public init(accessibilityProbe: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() }) {
        self.accessibilityProbe = accessibilityProbe
    }

    /// Démarre le monitoring. `nil` si Accessibility manque ou si la création
    /// du tap échoue (l'appelant retombe alors sur le raccourci seul).
    public func start() -> AsyncStream<FnKeyTransition>? {
        stop()
        guard accessibilityProbe() else { return nil }

        let (stream, continuation) = AsyncStream.makeStream(of: FnKeyTransition.self)
        let box = TapBox(continuation: continuation)
        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: fnTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(box).toOpaque())
        ) else {
            continuation.finish()
            return nil
        }

        box.tap = tap
        self.box = box

        let thread = Thread {
            box.runLoop = CFRunLoopGetCurrent()
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            // Tourne jusqu'à CFRunLoopStop (stop()) ou invalidation du port
            // (plus aucune source → le run loop rend la main).
            CFRunLoopRun()
        }
        thread.name = "eus.mintzo.fn-event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()

        return stream
    }

    public func stop() {
        guard let box else { return }
        if let tap = box.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop = box.runLoop {
            CFRunLoopStop(runLoop)
        }
        box.continuation.finish()
        self.box = nil
    }

    deinit {
        // Le deinit est nonisolated : on ne touche qu'à la boîte (@unchecked
        // Sendable) pour libérer le thread du tap si stop() n'a pas été appelé.
        if let box {
            if let tap = box.tap {
                CGEvent.tapEnable(tap: tap, enable: false)
                CFMachPortInvalidate(tap)
            }
            if let runLoop = box.runLoop {
                CFRunLoopStop(runLoop)
            }
            box.continuation.finish()
        }
    }
}

/// Callback C du tap — hors de tout contexte d'isolation, exécuté sur le
/// thread dédié du run loop. `refcon` = TapBox non-retenue (le monitor
/// garantit sa durée de vie).
private func fnTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let box = Unmanaged<FnKeyMonitor.TapBox>.fromOpaque(refcon).takeUnretainedValue()

    // Le système désactive un tap trop lent ou re-signé : on le réactive
    // (watchdog documenté — danielraffel 2026-02, Speak2).
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = box.tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .flagsChanged,
          event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Function)
    else {
        return Unmanaged.passUnretained(event)
    }

    let now = CFAbsoluteTimeGetCurrent()
    if event.flags.contains(.maskSecondaryFn) {
        box.continuation.yield(.down(at: now))
    } else {
        box.continuation.yield(.up(at: now))
    }
    // Listen-only : la valeur de retour est ignorée, on repasse l'événement.
    return Unmanaged.passUnretained(event)
}
