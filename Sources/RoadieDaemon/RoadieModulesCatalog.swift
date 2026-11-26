import Foundation
import RoadieAX
import RoadieCore
import SwiftUI

/// Descripteur d'un module activable/désactivable dans le tableau de bord Modules (Spec 171).
/// Chaque module pointe vers un véritable `SettingDescriptor` booléen de `SettingsCatalog` :
/// zéro duplication d'état, validation et sauvegarde TOML immédiates.
public struct RoadieModuleDescriptor: Equatable, Identifiable, Sendable {
    public var id: String { settingID }
    public let settingID: String
    public let symbolName: String
    public let titleFR: String
    public let titleEN: String
    public let summaryFR: String
    public let summaryEN: String
    public let offByDefault: Bool

    public init(
        settingID: String,
        symbolName: String,
        titleFR: String,
        titleEN: String,
        summaryFR: String,
        summaryEN: String,
        offByDefault: Bool
    ) {
        self.settingID = settingID
        self.symbolName = symbolName
        self.titleFR = titleFR
        self.titleEN = titleEN
        self.summaryFR = summaryFR
        self.summaryEN = summaryEN
        self.offByDefault = offByDefault
    }

    public var title: String { tr(titleFR, titleEN) }
    public var summary: String { tr(summaryFR, summaryEN) }
}

/// Catalogue central des modules activables/désactivables de Roadie (Spec 171).
public enum RoadieModuleCatalog {
    public static let all: [RoadieModuleDescriptor] = [
        RoadieModuleDescriptor(
            settingID: "target_mode.file_dialog_jump",
            symbolName: "folder.badge.gearshape",
            titleFR: "Saut dans les dialogues Ouvrir/Enregistrer",
            titleEN: "Open/Save dialog folder jump",
            summaryFR: "Téléporte les fenêtres Ouvrir/Enregistrer vers un dossier depuis la barre (0 polling).",
            summaryEN: "Jump Open/Save file dialogs straight to any folder from the bar (zero polling).",
            offByDefault: false
        ),
        RoadieModuleDescriptor(
            settingID: "target_mode.history_arrow_navigation",
            symbolName: "clock.arrow.circlepath",
            titleFR: "Historique du lanceur avec les flèches ↑ / ↓",
            titleEN: "Launcher history via ↑ / ↓ arrows",
            summaryFR: "Appuie sur ↑ tout en haut de la barre pour remonter dans tes 20 dernières commandes/saisies, et ↓ pour revenir.",
            summaryEN: "Press ↑ at the top of the bar to step back through your last 20 queries, and ↓ to return.",
            offByDefault: false
        ),
        RoadieModuleDescriptor(
            settingID: "app_targets.ocr_fallback",
            symbolName: "text.viewfinder",
            titleFR: "OCR local sur l'écran (Apple Vision)",
            titleEN: "Local screen OCR (Apple Vision)",
            summaryFR: "Lit en local le texte visible à l'écran dans « Rechercher à l'écran » (~11-35 ms à chaud, ~200 Mo RAM au 1er appel). Désactivé par défaut : 0 Mo et 0 capture.",
            summaryEN: "Locally reads visible screen text in Find on screen (~11-35 ms warm, ~200 MB RAM on first call). Off by default: 0 MB and zero capture.",
            offByDefault: true
        ),
        RoadieModuleDescriptor(
            settingID: "tiling.display_profiles_enabled",
            symbolName: "display.2",
            titleFR: "Profils matériels d'écrans automatiques",
            titleEN: "Automatic display profiles",
            summaryFR: "Rappelle un profil enregistré selon vos écrans branchés sans écraser les changements récents. Désactivé par défaut.",
            summaryEN: "Restores a saved profile when your monitor setup changes without overwriting recent edits. Off by default.",
            offByDefault: true
        ),
        RoadieModuleDescriptor(
            settingID: "clipboard.enabled",
            symbolName: "doc.on.clipboard",
            titleFR: "Historique du presse-papiers sécurisé",
            titleEN: "Secure clipboard history",
            summaryFR: "Stockage 100 % local (0600), exclut mots de passe et gestionnaires. 0 timer quand éteint.",
            summaryEN: "100% local (0600) storage, skips passwords and password managers. Zero timers when off.",
            offByDefault: false
        ),
        RoadieModuleDescriptor(
            settingID: "snippets.enabled",
            symbolName: "text.badge.plus",
            titleFR: "Snippets locaux dans le lanceur",
            titleEN: "Local snippets in launcher",
            summaryFR: "Modèles dynamiques (`snip …`) avec `{date}`, `{clipboard}`, `{cursor}`.",
            summaryEN: "Dynamic templates (`snip …`) with `{date}`, `{clipboard}`, `{cursor}`.",
            offByDefault: false
        ),
        RoadieModuleDescriptor(
            settingID: "snippets.auto_expand",
            symbolName: "keyboard.badge.ellipsis",
            titleFR: "Auto-expansion clavier des snippets",
            titleEN: "Snippet keyboard auto-expansion",
            summaryFR: "Étend un mot-clé suivi d'espace partout (hors champs mot de passe). Désactivé par défaut.",
            summaryEN: "Expands a keyword followed by space globally (skips password fields). Off by default.",
            offByDefault: true
        ),
        RoadieModuleDescriptor(
            settingID: "tiling.scratchpad_enabled",
            symbolName: "rectangle.on.rectangle.angled",
            titleFR: "Scratchpad flottant nommé",
            titleEN: "Named floating scratchpad",
            summaryFR: "Fenêtre tiroir flottante accessible d'une touche au-dessus de toute stage.",
            summaryEN: "Toggleable floating drawer window one shortcut away above any stage.",
            offByDefault: false
        ),
        RoadieModuleDescriptor(
            settingID: "dim_inactive.enabled",
            symbolName: "circle.lefthalf.filled",
            titleFR: "Assombrir les fenêtres inactives (Dim Inactive)",
            titleEN: "Dim inactive windows",
            summaryFR: "Voile doux traversant aux clics sur les fenêtres inactives. Désactivé par défaut : 0 panneau.",
            summaryEN: "Subtle click-through veil over unfocused tiled windows. Off by default: zero panels.",
            offByDefault: true
        ),
        RoadieModuleDescriptor(
            settingID: "tiling.scrolling_smooth_scroll",
            symbolName: "arrow.left.and.right.square",
            titleFR: "Défilement fluide 120 Hz du ruban",
            titleEN: "120 Hz smooth scrolling ribbon",
            summaryFR: "Glissement à ressort position-seule en mode `scrolling`.",
            summaryEN: "Position-only spring gliding in `scrolling` ribbon mode.",
            offByDefault: false
        ),
        RoadieModuleDescriptor(
            settingID: "tiling.scrolling_trackpad_gestures",
            symbolName: "hand.draw",
            titleFR: "Gestes trackpad du ruban (et ⌥ + molette)",
            titleEN: "Scrolling ribbon trackpad gestures (and ⌥ + scroll)",
            summaryFR: "Balayage horizontal 3/4 doigts au trackpad sans BetterTouchTool.",
            summaryEN: "Horizontal 3/4-finger trackpad swiping without BetterTouchTool.",
            offByDefault: false
        ),
        RoadieModuleDescriptor(
            settingID: "overview.trackpad_gesture",
            symbolName: "rectangle.3.group",
            titleFR: "Geste 4 doigts pour la Vue d'ensemble",
            titleEN: "4-finger swipe for Overview",
            summaryFR: "Balayage vertical 4 doigts haut/bas pour ouvrir ou fermer la Vue d'ensemble.",
            summaryEN: "Vertical 4-finger swipe up/down to open or close Overview.",
            offByDefault: false
        ),
        RoadieModuleDescriptor(
            settingID: "target_mode.calc_conversions",
            symbolName: "arrow.left.arrow.right.circle",
            titleFR: "Convertisseur hors ligne (unités, bases, fuseaux)",
            titleEN: "Offline converter (units, bases, time zones)",
            summaryFR: "Convertit unités, hex/bin et fuseaux horaires directement dans la barre.",
            summaryEN: "Converts units, hex/bin, and time zones directly inside the launcher bar.",
            offByDefault: false
        ),
        RoadieModuleDescriptor(
            settingID: "target_mode.emoji_picker",
            symbolName: "face.smiling",
            titleFR: "Émojis et symboles macOS intégrés",
            titleEN: "Built-in emojis and macOS symbols",
            summaryFR: "Tapez `:mot` ou `emoji …` pour copier un émoji ou symbole typographique.",
            summaryEN: "Type `:word` or `emoji …` to copy an emoji or typography symbol.",
            offByDefault: false
        ),
        RoadieModuleDescriptor(
            settingID: "target_mode.timer_enabled",
            symbolName: "timer",
            titleFR: "Minuteur et Pomodoro local",
            titleEN: "Local timer and Pomodoro",
            summaryFR: "Tapez `timer 15m` ou `pomodoro` dans la barre (notifications locales).",
            summaryEN: "Type `timer 15m` or `pomodoro` in the bar (local notifications).",
            offByDefault: false
        ),
    ]
}

/// Bilan structuré d'accueil au premier lancement (Spec 171 : `roadie onboarding [--json]`).
public struct OnboardingStep: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let done: Bool
    public let actionHint: String

    public init(id: String, title: String, done: Bool, actionHint: String) {
        self.id = id
        self.title = title
        self.done = done
        self.actionHint = actionHint
    }
}

public struct OnboardingChecklist: Codable, Equatable, Sendable {
    public let ready: Bool
    public let steps: [OnboardingStep]
    public let quickActions: [String]

    public init(ready: Bool, steps: [OnboardingStep], quickActions: [String]) {
        self.ready = ready
        self.steps = steps
        self.quickActions = quickActions
    }

    public static func evaluate(
        permissions: PermissionSnapshot,
        config: RoadieConfig,
        configFileExists: Bool
    ) -> OnboardingChecklist {
        let steps: [OnboardingStep] = [
            OnboardingStep(
                id: "accessibility",
                title: tr("Permission Accessibilité accordée", "Accessibility permission granted"),
                done: permissions.accessibilityTrusted,
                actionHint: tr("Réglages Système > Confidentialité et sécurité > Accessibilité > activer Roadie.", "System Settings > Privacy & Security > Accessibility > enable Roadie.")
            ),
            OnboardingStep(
                id: "screen_recording",
                title: tr("Enregistrement d'écran (optionnel : vignettes et OCR)", "Screen Recording (optional: thumbnails and OCR)"),
                done: permissions.screenRecordingGranted,
                actionHint: tr("Réglages Système > Confidentialité et sécurité > Enregistrement de l'écran > Roadie.", "System Settings > Privacy & Security > Screen Recording > Roadie.")
            ),
            OnboardingStep(
                id: "config_file",
                title: tr("Fichier de configuration initialisé", "Configuration file initialized"),
                done: configFileExists,
                actionHint: "roadie config init --preset standard"
            ),
            OnboardingStep(
                id: "shortcuts",
                title: tr("Raccourcis clavier configurés (\(config.shortcuts.count))", "Keyboard shortcuts configured (\(config.shortcuts.count))"),
                done: !config.shortcuts.isEmpty,
                actionHint: tr("Paramètres > Raccourcis (préréglage 1 clic) ou `roadie shortcuts apply-preset standard`.", "Settings > Shortcuts (1-click preset) or `roadie shortcuts apply-preset standard`.")
            ),
        ]
        let quickActions = [
            tr("Maintiens ⌥ Option en glissant une fenêtre sur une autre pour créer des onglets (tous modes tuilés).", "Hold ⌥ Option while dragging one window onto another to stack tabs (all tiled modes)."),
            tr("Ouvre la barre de recherche puis tape une appli, un calcul, `cb` (presse-papiers) ou `snip` (snippets).", "Open the launcher bar and type an app, calculation, `cb` (clipboard), or `snip` (snippets)."),
            tr("Dans Paramètres > Général, active ou coupe chaque module à la carte (coût zéro quand éteint).", "In Settings > General, toggle every module on or off individually (zero overhead when off)."),
        ]
        let ready = permissions.accessibilityTrusted && configFileExists
        return OnboardingChecklist(ready: ready, steps: steps, quickActions: quickActions)
    }
}

/// Carte « Modules activables » affichée dans `Paramètres > Général` (Spec 171).
struct SettingsModulesCard: View {
    @ObservedObject var model: SettingsViewModel
    private var fonts: InterfaceConfig { model.interfaceFonts }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("Modules activables", "Toggleable modules"))
                    .font(.system(size: fonts.settingsTextFontSize, weight: .semibold))
                Text(tr("Active ou désactive chaque capacité indépendamment. Un module éteint ne consomme ni timer ni capture.", "Enable or disable each capability independently. Disabled modules use zero timers and zero capture."))
                    .font(.system(size: fonts.settingsHelpFontSize))
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                let items = RoadieModuleCatalog.all.compactMap { module -> (RoadieModuleDescriptor, SettingDescriptor)? in
                    guard let descriptor = SettingsCatalog.find(id: module.settingID) else { return nil }
                    return (module, descriptor)
                }
                ForEach(Array(items.enumerated()), id: \.element.0.id) { index, pair in
                    let (module, descriptor) = pair
                    if index > 0 { Divider().padding(.leading, 14) }
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: module.symbolName)
                            .font(.system(size: min(16, fonts.settingsTextFontSize)))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(module.title)
                                    .font(.system(size: fonts.settingsTextFontSize, weight: .medium))
                                if module.offByDefault {
                                    Text(tr("Optionnel", "Optional"))
                                        .font(.system(size: max(10, fonts.settingsHelpFontSize - 1), weight: .medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.secondary.opacity(0.16)))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(module.summary)
                                .font(.system(size: fonts.settingsHelpFontSize))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Button(tr("Régler", "Configure")) {
                            model.select(descriptor.category)
                        }
                        .font(.system(size: fonts.settingsHelpFontSize))
                        Toggle("", isOn: Binding(
                            get: { model.value(descriptor) == .bool(true) },
                            set: { model.apply(descriptor, raw: $0 ? "true" : "false") }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .disabled(model.isLocked)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
            )
        }
    }
}
