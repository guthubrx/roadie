import Foundation
import ApplicationServices
#if canImport(Carbon)
import Carbon
#endif

/// Activation inter-app fiable via API privée WindowServer (SkyLight).
///
/// Pourquoi : sur macOS Sonoma+/Sequoia/Tahoe, `NSRunningApplication.activate(...)`
/// — même avec `.activateIgnoringOtherApps` (deprecated) — ne franchit plus la barrière
/// du "yieldActivation pattern" : si l'app source ne possède pas l'activation et ne la
/// cède pas explicitement, le système ignore l'appel pour les apps qui ne se ré-activent
/// pas elles-mêmes au clic. Symptôme : iTerm2/Terminal ne passent pas devant Cursor/Finder
/// après un click-to-raise.
///
/// Cette API privée du WindowServer est utilisée par **yabai**, **AeroSpace**,
/// **Hammerspoon**, **Amethyst** et tous les WM macOS modernes. Stable depuis macOS 10.7.
/// Ne nécessite **PAS** SIP désactivé.
///
/// Référence : yabai/src/process_manager.c, AeroSpace/Sources/Common/.
public enum WindowActivator {

    /// Active une app et raise une fenêtre spécifique au front (combinaison atomique).
    /// - Parameters:
    ///   - pid: PID du processus possédant la fenêtre
    ///   - windowID: CGWindowID de la fenêtre à raiser (0 pour activer juste l'app)
    public static func bringToFront(pid: pid_t, windowID: CGWindowID) {
        var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: 0)
        guard GetProcessForPID(pid, &psn) == noErr else { return }

        // 1) Demande au WindowServer de mettre cette app au front avec raise de la window.
        //    Mode 0x200 = raise (cohérent avec ce que fait macOS sur un clic-Dock).
        _ = _SLPSSetFrontProcessWithOptions(&psn, UInt32(windowID), 0x200)

        // 2) Sur Sonoma+, l'étape 1 seule est parfois ignorée si l'app cible ne réagit
        //    pas à un event. On simule donc un click event ciblé envoyé directement à
        //    sa main thread via SLPSPostEventRecordTo. Layout du buffer reverse-engineered
        //    de Carbon EventRecord, identique à yabai.
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        let widCopy = UInt32(windowID)
        withUnsafeBytes(of: widCopy) { raw in
            for i in 0..<4 { bytes[0x3c + i] = raw[i] }
        }

        bytes[0x08] = 0x01   // mouseDown
        _ = SLPSPostEventRecordTo(&psn, &bytes)
        bytes[0x08] = 0x02   // mouseUp
        _ = SLPSPostEventRecordTo(&psn, &bytes)
    }
}

// MARK: - Private SkyLight bindings

@_silgen_name("_SLPSSetFrontProcessWithOptions")
private func _SLPSSetFrontProcessWithOptions(
    _ psn: UnsafeMutablePointer<ProcessSerialNumber>,
    _ wid: UInt32,
    _ mode: UInt32
) -> OSStatus

@_silgen_name("SLPSPostEventRecordTo")
private func SLPSPostEventRecordTo(
    _ psn: UnsafeMutablePointer<ProcessSerialNumber>,
    _ bytes: UnsafeMutablePointer<UInt8>
) -> OSStatus

// `GetProcessForPID` est marqué deprecated/unavailable en Swift, mais le symbole reste
// présent dans HIServices.framework et fonctionne sur macOS 26 (Tahoe). On le réexpose
// via @_silgen_name pour court-circuiter le check d'availability Swift.
@_silgen_name("GetProcessForPID")
private func GetProcessForPID(
    _ pid: pid_t,
    _ psn: UnsafeMutablePointer<ProcessSerialNumber>
) -> OSStatus

// MARK: - Compositor batching (CGSDisableUpdate / CGSReenableUpdate)

/// SPEC-028 — Batch atomique des mutations de fenêtres pour forcer le
/// compositor macOS à flusher en un seul frame. Sur Tahoe, le compositor
/// peut ignorer des AX setBounds successifs (= la fenêtre reste invisible
/// jusqu'à un event mouse natif). En les enrobant dans un disable/reenable,
/// on garantit que le compositor re-évalue tout en sortie de bloc.
///
/// API privée CoreGraphics (`/System/Library/Frameworks/CoreGraphics.framework`).
/// Auto-reenable de sécurité après 1s côté WindowServer.
public enum CGSCompositor {
    /// Exécute `block` entre `CGSDisableUpdate` et `CGSReenableUpdate`. Garantit
    /// le reenable même en cas d'exception (defer).
    public static func batch<T>(_ block: () throws -> T) rethrows -> T {
        let cid = CGSMainConnectionID()
        _ = CGSDisableUpdate(cid)
        defer { _ = CGSReenableUpdate(cid) }
        return try block()
    }
}

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> Int32

@_silgen_name("CGSDisableUpdate")
private func CGSDisableUpdate(_ cid: Int32) -> Int32

@_silgen_name("CGSReenableUpdate")
private func CGSReenableUpdate(_ cid: Int32) -> Int32

// MARK: - Spaces inspection (CGSCopySpacesForWindows / CGSGetActiveSpace)

/// SPEC-028 diagnostic — vérifier si une wid summoned est sur un Mission
/// Control Space différent du Space actif. Si oui, aucun setBounds/raise/
/// activate ne la fera apparaître ; il faut SIP-off + Dock injection.
public enum CGSSpaces {
    /// Liste des Mission Control Space IDs où est posée la wid donnée.
    /// Mask 7 = `kCGSAllSpacesMask` (current + others + user).
    public static func spacesForWindow(_ wid: CGWindowID) -> [UInt64] {
        let cid = CGSMainConnectionID()
        let widArray: CFArray = [wid] as CFArray
        guard let result = CGSCopySpacesForWindows(cid, 7, widArray) as? [NSNumber] else {
            return []
        }
        return result.map { $0.uint64Value }
    }

    /// Space ID actif (= visible au user) sur le display courant.
    public static func currentSpace() -> UInt64 {
        return CGSGetActiveSpace(CGSMainConnectionID())
    }
}

@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ cid: Int32) -> UInt64

@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(_ cid: Int32, _ mask: Int32, _ wids: CFArray) -> CFArray?

// MARK: - SLEventPostToPid (post events directement au PID, bypass HID tap)

/// SPEC-028 — Post un event CGEvent directement à un PID via SkyLight,
/// sans passer par le HID tap. yabai-style, utilisé par cua-driver pour
/// driver des apps en background. Sur Tahoe, c'est la seule façon fiable
/// d'amener un mouseDown event à une app cible quand HID tap est filtré.
public enum SLEvents {
    /// Post un mouseClicked (down + up) au pid à la position donnée.
    /// Ne déplace PAS le curseur visible (l'event est virtuel).
    public static func postClick(pid: pid_t, at point: CGPoint) {
        guard let down = CGEvent(mouseEventSource: nil,
                                  mouseType: .leftMouseDown,
                                  mouseCursorPosition: point,
                                  mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil,
                                mouseType: .leftMouseUp,
                                mouseCursorPosition: point,
                                mouseButton: .left)
        else { return }
        SLEventPostToPid(pid, down)
        SLEventPostToPid(pid, up)
    }
}

@_silgen_name("SLEventPostToPid")
private func SLEventPostToPid(_ pid: pid_t, _ event: CGEvent)
