// stage — Stage Manager macOS suckless. Voir specs/001-stage-manager/.
// Constitution projet : mono-fichier, zero dependance.
// Cible 150 lignes Swift effectives, plafond 200 (constitution projet principe A).
// Compte actuel : ~190 lignes hors commentaires/blanches.

import Cocoa
import ApplicationServices
import CoreGraphics

// MARK: - API privee (recherche.md D2). Stable depuis macOS 10.7.

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

// MARK: - Modele (data-model.md WindowRef).

struct WindowRef {
	let pid: pid_t
	let bundleID: String
	let cgWindowID: CGWindowID

	func serialize() -> String { "\(pid)\t\(bundleID)\t\(cgWindowID)" }

	static func parse(_ line: String) -> WindowRef? {
		// Tolère les anciennes lignes à 7 champs (capture frame, abandonnée v4) :
		// on lit les 3 premiers et on ignore le reste.
		let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
		guard parts.count >= 3,
		      let pid = pid_t(parts[0]),
		      let wid = CGWindowID(parts[2]),
		      !parts[1].isEmpty
		else { return nil }
		return WindowRef(pid: pid, bundleID: String(parts[1]), cgWindowID: wid)
	}
}

// MARK: - Persistance (data-model.md Stage / CurrentStage).

let STAGE_DIR = ("~/.stage" as NSString).expandingTildeInPath

func stagePath(_ N: Int) -> String { "\(STAGE_DIR)/\(N)" }
func currentPath() -> String { "\(STAGE_DIR)/current" }

func ensureStageDir() throws {
	try FileManager.default.createDirectory(atPath: STAGE_DIR, withIntermediateDirectories: true,
	                                         attributes: [.posixPermissions: 0o755])
}

func readStage(_ N: Int) -> [WindowRef] {
	guard let raw = try? String(contentsOfFile: stagePath(N), encoding: .utf8) else { return [] }
	var refs: [WindowRef] = []
	for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
		if let r = WindowRef.parse(String(line)) {
			refs.append(r)
		} else {
			fputs("stage : ligne ignoree dans \(stagePath(N)) (corrompue) : \(line)\n", stderr)
		}
	}
	return refs
}

func writeStage(_ N: Int, _ refs: [WindowRef]) throws {
	try ensureStageDir()
	let body = refs.map { $0.serialize() }.joined(separator: "\n") + (refs.isEmpty ? "" : "\n")
	try body.write(toFile: stagePath(N), atomically: true, encoding: .utf8)
}

func readCurrent() -> Int {
	guard let raw = try? String(contentsOfFile: currentPath(), encoding: .utf8),
	      let n = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)),
	      (1...2).contains(n)
	else { return 1 }
	return n
}

func writeCurrent(_ N: Int) throws {
	try ensureStageDir()
	try "\(N)\n".write(toFile: currentPath(), atomically: true, encoding: .utf8)
}

// MARK: - Permissions (research.md D6).

func checkAccessibility() {
	if AXIsProcessTrusted() { return }
	let bin = CommandLine.arguments[0]
	let abs = (bin as NSString).standardizingPath
	fputs("""
	stage : permission Accessibility manquante.
	Ouvre Reglages Systeme > Confidentialite et securite > Accessibilite,
	ajoute le binaire (chemin : \(abs)) et coche-le.

	""", stderr)
	exit(2)
}

// MARK: - Routage CLI (contracts/cli-contract.md).

func printUsageAndExit() -> Never {
	fputs("usage: stage <1|2>\n       stage assign <1|2>\n", stderr)
	exit(64)
}

func parseStageNumber(_ s: String) -> Int {
	guard let n = Int(s), (1...2).contains(n) else { printUsageAndExit() }
	return n
}

// MARK: - Resolution AX <-> CG (research.md D3, D4).

func liveCGWindowIDs() -> Set<CGWindowID> {
	guard let arr = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID)
		as? [[String: Any]] else { return [] }
	var ids = Set<CGWindowID>()
	for info in arr {
		if let n = info[kCGWindowNumber as String] as? CGWindowID { ids.insert(n) }
	}
	return ids
}

func axWindows(forPID pid: pid_t) -> [AXUIElement] {
	let app = AXUIElementCreateApplication(pid)
	var raw: CFTypeRef?
	guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &raw) == .success,
	      let arr = raw as? [AXUIElement]
	else { return [] }
	return arr
}

func findAXWindow(pid: pid_t, target: CGWindowID) -> AXUIElement? {
	for win in axWindows(forPID: pid) {
		var wid: CGWindowID = 0
		if _AXUIElementGetWindow(win, &wid) == .success, wid == target {
			return win
		}
	}
	return nil
}

@discardableResult
func setMinimized(_ window: AXUIElement, _ value: Bool) -> AXError {
	let v = value as CFBoolean
	return AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, v)
}

func frontmostWindowRef() -> WindowRef? {
	guard let app = NSWorkspace.shared.frontmostApplication else {
		fputs("stage : aucune application au premier plan\n", stderr); return nil
	}
	let bundleID = app.bundleIdentifier ?? ""
	let appElem = AXUIElementCreateApplication(app.processIdentifier)
	var raw: CFTypeRef?
	guard AXUIElementCopyAttributeValue(appElem, kAXFocusedWindowAttribute as CFString, &raw) == .success,
	      let focused = raw, CFGetTypeID(focused) == AXUIElementGetTypeID()
	else {
		fputs("stage : pas de fenetre focalisee dans l'app frontmost (\(bundleID))\n", stderr); return nil
	}
	var wid: CGWindowID = 0
	guard _AXUIElementGetWindow(focused as! AXUIElement, &wid) == .success, wid != 0 else {
		fputs("stage : impossible de recuperer le CGWindowID de la fenetre frontmost\n", stderr); return nil
	}
	return WindowRef(pid: app.processIdentifier, bundleID: bundleID, cgWindowID: wid)
}

// MARK: - Auto-GC (FR-006).

func pruneDeadRefs(_ N: Int, _ alive: Set<CGWindowID>) -> Int {
	let refs = readStage(N)
	let kept = refs.filter { ref in
		if alive.contains(ref.cgWindowID) { return true }
		fputs("stage : window \(ref.cgWindowID) from stage \(N) no longer exists, pruned\n", stderr)
		return false
	}
	if kept.count != refs.count {
		try? writeStage(N, kept)
	}
	return refs.count - kept.count
}

// MARK: - Manipulation des stages (data-model.md operations).

func removeFromAllStages(_ wid: CGWindowID) {
	for N in 1...2 {
		let refs = readStage(N)
		let kept = refs.filter { $0.cgWindowID != wid }
		if kept.count != refs.count { try? writeStage(N, kept) }
	}
}

func addToStage(_ N: Int, _ ref: WindowRef) {
	var refs = readStage(N)
	if !refs.contains(where: { $0.cgWindowID == ref.cgWindowID }) {
		refs.append(ref)
		do { try writeStage(N, refs) }
		catch { fputs("stage : ecriture \(stagePath(N)) impossible : \(error)\n", stderr); exit(1) }
	}
}

// MARK: - Commandes (contracts/cli-contract.md).

func cmdSwitch(_ N: Int) -> Never {
	let alive = liveCGWindowIDs()
	for s in 1...2 { _ = pruneDeadRefs(s, alive) }
	var hadError = false
	// 2-phase : minimiser puis dé-minimiser, séparés par un unique délai de 50 ms.
	// Réduit le clignotement yabai/JankyBorders sans accumuler de latence par fenêtre.
	func resolve(_ refs: [WindowRef]) -> [(WindowRef, AXUIElement)] {
		var out: [(WindowRef, AXUIElement)] = []
		for ref in refs {
			guard let win = findAXWindow(pid: ref.pid, target: ref.cgWindowID) else {
				fputs("stage : window \(ref.cgWindowID) introuvable cote AX (pid \(ref.pid))\n", stderr)
				hadError = true; continue
			}
			out.append((ref, win))
		}
		return out
	}
	let toHide = resolve((1...2).filter { $0 != N }.flatMap { readStage($0) })
	let toShow = resolve(readStage(N))
	for (ref, win) in toHide {
		let err = setMinimized(win, true)
		if err != .success {
			fputs("stage : AXError \(err.rawValue) sur window \(ref.cgWindowID)\n", stderr)
			hadError = true
		}
	}
	usleep(50_000)
	for (ref, win) in toShow {
		let err = setMinimized(win, false)
		if err != .success {
			fputs("stage : AXError \(err.rawValue) sur window \(ref.cgWindowID)\n", stderr)
			hadError = true
		}
	}
	do { try writeCurrent(N) }
	catch { fputs("stage : ecriture \(currentPath()) impossible : \(error)\n", stderr); exit(1) }
	exit(hadError ? 1 : 0)
}

func cmdAssign(_ N: Int) -> Never {
	do { try ensureStageDir() }
	catch { fputs("stage : creation \(STAGE_DIR) impossible : \(error)\n", stderr); exit(1) }
	guard let ref = frontmostWindowRef() else { exit(1) }
	removeFromAllStages(ref.cgWindowID)
	addToStage(N, ref)
	exit(0)
}

// MARK: - main.

checkAccessibility()
let args = CommandLine.arguments
switch args.count {
case 2:
	cmdSwitch(parseStageNumber(args[1]))
case 3 where args[1] == "assign":
	cmdAssign(parseStageNumber(args[2]))
default:
	printUsageAndExit()
}
