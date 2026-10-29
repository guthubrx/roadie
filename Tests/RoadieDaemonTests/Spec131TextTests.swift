import Foundation
import Testing
@testable import RoadieDaemon

/// Session 131 : texte comme objet de la barre, adresses extraites, verbes d'un texte, d'une adresse et d'un onglet.
struct Spec131TextTests {
    @Test func addressesAreFoundInOrderWithoutDuplicates() {
        let text = "Voir https://roadie.example/doc et www.example.org, écrire à moi@example.com ; https://roadie.example/doc encore."
        let found = LauncherText.addresses(in: text)
        #expect(found.map(\.kind) == [.web, .web, .email])
        #expect(found[0].url.absoluteString == "https://roadie.example/doc")
        #expect(found[2].text == "moi@example.com")
        #expect(LauncherText.addresses(in: "rien ici").isEmpty)
    }

    @Test func previewAndMail() {
        #expect(LauncherText.preview("  un\n texte\tsur   plusieurs lignes ") == "un texte sur plusieurs lignes")
        #expect(LauncherText.preview(String(repeating: "a", count: 100)).count == 80)
        let mail = LauncherText.mailURL(body: "a b&c")
        #expect(mail?.scheme == "mailto" && mail?.absoluteString.contains("body=a%20b%26c") == true)
    }

    @Test func selectedTextComesBeforeTheWindow() {
        let window = LauncherSubject.project("fenêtre")
        #expect(LauncherText.initialSubject(selection: "bonjour", window: window) == .text("bonjour"))
        #expect(LauncherText.initialSubject(selection: "  \n", window: window) == window)
        #expect(LauncherText.initialSubject(selection: nil, window: nil) == nil)
    }

    @Test func verbsOfTextURLTabAndApp() {
        #expect(LauncherVerb.verbs(for: .text("x")) == [.copyText, .webSearch, .extractURLs, .emailText, .largeType])
        let url = URL(string: "https://example.com")!
        #expect(LauncherVerb.verbs(for: .url(url)).contains(.emailText))
        let tab = LauncherOpenItem(kind: .tab, windowID: nil, bundleID: "com.apple.Safari", appName: "Safari", title: "Doc",
                                   detail: "", url: "https://example.com", browserWindow: 1, tabIndex: 2)
        #expect(LauncherVerb.verbs(for: .openItem(tab)) == [.open, .closeTab, .copyURL, .newWindowTab])
        let app = LauncherApp(bundleID: "com.apple.TextEdit", path: "/System/Applications/TextEdit.app", name: "TextEdit", alternateNames: [])
        #expect(LauncherVerb.verbs(for: .app(app)).suffix(2) == [.relaunch, .quitOthers])
        // Mots compris dans les deux langues.
        #expect(LauncherVerb.extractURLs.matches("extract", app: "") && LauncherVerb.extractURLs.matches("extraire", app: ""))
        #expect(LauncherVerb.trash.matches("corbeille", app: "") && LauncherVerb.trash.matches("trash", app: ""))
    }

    @Test func tabScripts() {
        #expect(LauncherTabActions.script(.close, bundleID: "com.apple.Safari", window: 2, tab: 3, url: nil)
                == "tell application id \"com.apple.Safari\" to close tab 3 of window 2")
        let chrome = LauncherTabActions.script(.newWindow, bundleID: "com.google.Chrome", window: 1, tab: 1, url: "https://a.example/\"x")
        #expect(chrome?.contains("make new window") == true && chrome?.contains("\\\"x") == true)
        #expect(LauncherTabActions.script(.newWindow, bundleID: "com.apple.Safari", window: nil, tab: nil, url: "https://a")?.contains("make new document") == true)
        #expect(LauncherTabActions.script(.close, bundleID: "com.apple.Safari", window: nil, tab: nil, url: nil) == nil)
        #expect(LauncherTabActions.script(.close, bundleID: "org.mozilla.firefox", window: 1, tab: 1, url: nil) == nil)
        #expect(LauncherTabActions.firefoxNewWindowArguments(url: "https://a") == ["-na", "Firefox", "--args", "--new-window", "https://a"])
    }

    @Test func universalActionsOnTextAndAddresses() throws {
        var fixture = WorkflowFixture()
        fixture.add("UT", "trigger.universalaction", ["acceptstext": true])
        fixture.add("UU", "trigger.universalaction", ["acceptsurls": true])
        fixture.add("UF", "trigger.universalaction", ["acceptsfiles": true])
        fixture.add("CB", "output.clipboard", ["clipboardtext": "{query}"])
        for uid in ["UT", "UU", "UF"] { fixture.link(uid, "CB") }
        let workflow = try fixture.write()
        let entries = AlfredWorkflowIndex.triggers([workflow]).filter { $0.kind == .universalAction }
        #expect(Set(entries.filter(AlfredWorkflowIndex.acceptsText).map(\.objectUID)) == ["UT"])
        #expect(Set(entries.filter(AlfredWorkflowIndex.acceptsURL).map(\.objectUID)) == ["UT", "UU"])
    }
}
