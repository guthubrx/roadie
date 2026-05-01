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
