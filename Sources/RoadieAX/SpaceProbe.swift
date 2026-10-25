import ApplicationServices
import Darwin
import Foundation
import RoadieCore

/// Lecture seule du type du bureau courant d'un écran (SPEC-017 A5, ADR 010). Elle ferme la
/// garde de transition de bureau dès que l'écran affiche un bureau utilisateur, comme
/// `space_is_user` chez yabai. Fonctions privées de SkyLight résolues par `dlsym` : aucun
/// lien à la compilation, aucun appel en écriture, aucune désactivation de SIP.
public enum SpaceProbe {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?

    // Résolus une fois ; nil si le système ne les expose plus (repli public chez l'appelant).
    private static let mainConnection: MainConnection? =
        symbol(["CGSMainConnectionID", "SLSMainConnectionID"])
    private static let copyManagedDisplaySpaces: CopyManagedDisplaySpaces? =
        symbol(["CGSCopyManagedDisplaySpaces", "SLSCopyManagedDisplaySpaces"])
    private static let copySpacesForWindows: CopySpacesForWindows? =
        symbol(["CGSCopySpacesForWindows", "SLSCopySpacesForWindows"])

    /// Fenêtres rattachées à aucun bureau, tous types confondus (masque 7) : une fenêtre retirée
    /// de l'écran par son application, mais aussi une fenêtre réduite ou d'application cachée.
    /// L'appelant doit donc écarter ces deux cas. nil si un symbole est absent. O(k) appels.
    public static func windowsWithoutSpace(_ ids: Set<WindowID>) -> Set<WindowID>? {
        guard let mainConnection, let copySpacesForWindows else { return nil }
        let connection = mainConnection()
        return ids.filter { id in
            let spaces = copySpacesForWindows(connection, 7, [NSNumber(value: id.rawValue)] as CFArray)?
                .takeRetainedValue() as? [NSNumber]
            return spaces?.isEmpty ?? false
        }
    }

    /// Vrai si le bureau courant de l'écran est un bureau utilisateur (type 0), faux pendant un
    /// plein écran natif ou sa transition (type 4). nil si un symbole est absent, si la réponse
    /// n'est pas conforme ou si l'écran est introuvable. O(d), d = nombre d'écrans.
    public static func isUserSpaceActive(displayUUID: String) -> Bool? {
        guard let mainConnection, let copyManagedDisplaySpaces,
              let displays = copyManagedDisplaySpaces(mainConnection())?.takeRetainedValue() as? [[String: Any]]
        else { return nil }
        let mainDisplayUUID = CGDisplayCreateUUIDFromDisplayID(CGMainDisplayID()).map {
            CFUUIDCreateString(nil, $0.takeRetainedValue()) as String
        }
        return parse(displays, displayUUID: displayUUID, mainDisplayUUID: mainDisplayUUID)
    }

    /// Décode la réponse de `CGSCopyManagedDisplaySpaces` : entrée de l'écran par
    /// « Display Identifier » (UUID, ou « Main » pour l'écran principal), puis
    /// « Current Space » → « type ». Fonction pure. O(d).
    static func parse(_ displays: [[String: Any]], displayUUID: String, mainDisplayUUID: String?) -> Bool? {
        func isRequested(_ identifier: String) -> Bool {
            if identifier.caseInsensitiveCompare(displayUUID) == .orderedSame { return true }
            guard identifier == "Main", let mainDisplayUUID else { return false }
            return mainDisplayUUID.caseInsensitiveCompare(displayUUID) == .orderedSame
        }
        guard let display = displays.first(where: { ($0["Display Identifier"] as? String).map(isRequested) ?? false }),
              let current = display["Current Space"] as? [String: Any],
              let type = current["type"] as? NSNumber
        else { return nil }
        return type.intValue == 0
    }

    private static func symbol<T>(_ names: [String]) -> T? {
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        for name in names {
            if let pointer = dlsym(handle, name) { return unsafeBitCast(pointer, to: T.self) }
        }
        return nil
    }
}
