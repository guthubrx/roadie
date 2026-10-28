import ApplicationServices
import Darwin

/// Fenêtre clé rendue par SkyLight (session 098, ADR 020). Le panneau de la barre prend le clavier
/// sans activer Roadie ; à sa fermeture, l'application restée au premier plan garde son élément actif
/// mais ne reçoit plus la frappe. AXRaise et kAXFrontmostAttribute ne changent rien à une application
/// déjà au premier plan. Même méthode qu'AltTab et yabai : mise au premier plan liée à la fenêtre, puis
/// deux enregistrements d'événement qui la rendent clé. Symboles résolus par `dlsym` ; absents, rien
/// n'est fait. Aucun accès SIP requis.
public enum WindowKeyFocus {
    private typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias SetFrontProcess = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostEventRecord = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

    private static let processForPID: GetProcessForPID? = symbol("GetProcessForPID")
    private static let setFrontProcess: SetFrontProcess? = symbol("_SLPSSetFrontProcessWithOptions")
    private static let postEventRecord: PostEventRecord? = symbol("SLPSPostEventRecordTo")
    /// `kCPSUserGenerated` : la mise au premier plan vaut un geste de l'utilisateur.
    private static let userGenerated: UInt32 = 0x200

    /// Fenêtre AX : son numéro CoreGraphics, puis `makeKey(pid:windowID:)`. Faux si illisible.
    @discardableResult
    public static func makeKey(pid: pid_t, window: AXUIElement) -> Bool {
        var id = CGWindowID()
        guard AXUIElementGetWindowID(window, &id) == .success, id > 0 else { return false }
        return makeKey(pid: pid, windowID: id)
    }

    @discardableResult
    public static func makeKey(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard let processForPID, let setFrontProcess, let postEventRecord else { return false }
        var psn = ProcessSerialNumber()
        guard processForPID(pid, &psn) == noErr, setFrontProcess(&psn, windowID, userGenerated) == .success else { return false }
        for kind: UInt8 in [0x01, 0x02] {
            var bytes = record(kind, windowID: windowID)
            guard bytes.withUnsafeMutableBufferPointer({ postEventRecord(&psn, $0.baseAddress!) }) == .success else { return false }
        }
        return true
    }

    /// Enregistrement de 0xF8 octets : 1 puis 2 à l'octet 8, numéro de fenêtre à 0x3C (petit-boutiste).
    static func record(_ kind: UInt8, windowID: CGWindowID) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x08] = kind
        bytes[0x3a] = 0x10
        for offset in 0x20..<0x30 { bytes[offset] = 0xff }
        withUnsafeBytes(of: windowID.littleEndian) { bytes.replaceSubrange(0x3c..<0x40, with: $0) }
        return bytes
    }

    private static func symbol<T>(_ name: String) -> T? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2), name).map { unsafeBitCast($0, to: T.self) } // RTLD_DEFAULT
    }
}
