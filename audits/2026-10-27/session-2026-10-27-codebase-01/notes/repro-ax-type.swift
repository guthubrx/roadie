import ApplicationServices
import Foundation

// Valeur AX synthétique de mauvais type : aucun accès à une fenêtre réelle.
let value: CFTypeRef = "texte à la place d'une fenêtre" as CFString
print("type=\(CFGetTypeID(value)) attendu=\(AXUIElementGetTypeID())")
fflush(stdout)
let element = value as! AXUIElement
var pid: pid_t = 0
let result = AXUIElementGetPid(element, &pid)
print("result=\(result.rawValue) pid=\(pid)")
