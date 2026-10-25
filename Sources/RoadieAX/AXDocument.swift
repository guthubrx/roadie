import ApplicationServices
import Foundation

/// Chemin du document qu'affiche une fenêtre, lu dans son attribut `AXDocument` (applications à
/// documents : TextEdit, Aperçu, Pages…) ; nil si l'application ne l'expose pas (SPEC-077). Selon
/// l'application, la valeur est une chaîne (`file://…` ou chemin) ou une URL. Une lecture AX.
public func axDocumentPath(_ window: AXUIElement) -> String? {
    axDocumentRead(window).path
}

/// Même lecture, avec le résultat AX et le type reçu pour le diagnostic (aucun chemin journalisé).
/// `web` : adresse non fichier (Chrome, applications Electron), utile pour rouvrir une fenêtre (SPEC-080).
public func axDocumentRead(_ window: AXUIElement) -> (path: String?, web: URL?, status: String) {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(window, kAXDocumentAttribute as CFString, &value)
    guard error == .success, let value else { return (nil, nil, "ax\(error.rawValue)") }
    let url: URL?
    if let text = value as? String {
        url = text.hasPrefix("/") ? URL(fileURLWithPath: text) : URL(string: text)
    } else if CFGetTypeID(value) == CFURLGetTypeID() {
        url = (value as! CFURL) as URL
    } else {
        return (nil, nil, "type\(CFGetTypeID(value))")
    }
    guard let url else { return (nil, nil, "invalid") }
    guard url.isFileURL else { return (nil, ["http", "https"].contains(url.scheme ?? "") ? url : nil, "notfile") }
    return (url.standardizedFileURL.resolvingSymlinksInPath().path, nil, "ok")
}
