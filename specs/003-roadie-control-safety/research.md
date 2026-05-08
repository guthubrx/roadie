# Recherche : Roadie Control & Safety

## Décision : Control Center macOS via AppKit/SwiftUI

**Décision**: Ajouter un item de barre de menus Roadie avec snapshot de statut, actions courantes et fenetre settings. L'UI consomme un `ControlCenterState` derive des services existants.

**Raison**: Miri montre qu'un window manager macOS gagne beaucoup en utilisabilite quand l'utilisateur peut voir l'etat, ouvrir la config, recharger et quitter proprement sans terminal. Roadie dispose deja de health, query, events et rail state : il faut les exposer sans dupliquer la logique.

**Alternatives étudiées**:

- CLI uniquement : insuffisant pour utilisateurs non developpeurs et diagnostics rapides.
- DMG app seulement sans menu : trop opaque, pas de surface de controle continue.
- Web UI locale : plus lourde, besoin serveur local, pas adapte a une app macOS de fond.

## Décision : Reload atomique de configuration

**Décision**: Introduire un service de reload qui charge et valide la nouvelle config dans un objet temporaire, puis remplace l'active uniquement si tout passe.

**Raison**: Miri conserve l'ancienne config si le fichier sauvegarde est invalide. Roadie doit faire pareil pour eviter qu'une erreur TOML casse le daemon ou le tiler.

**Alternatives étudiées**:

- Relire `RoadieConfigLoader.load()` partout : trop implicite, pas de rollback central.
- Redemarrer le daemon apres chaque changement : simple mais coupe l'etat utilisateur.
- Appliquer partiellement les sections valides : dangereux, difficile a expliquer.

## Décision : Restore safety best-effort, idempotent

**Décision**: Ecrire un snapshot de securite et lancer un watcher separe capable de restaurer les fenetres si `roadied` disparait.

**Raison**: Un WM doit echouer proprement. Miri utilise un cleanup watcher. Roadie peut reprendre le pattern sans private API : rendre les fenetres visibles et les replacer dans des frames recuperables via Accessibility.

**Alternatives étudiées**:

- Restaurer seulement a l'arret normal : ne couvre pas crash/kill.
- Ne rien restaurer : risque de fenetres cachees ou hors ecran.
- Restaurer exactement l'ancien layout : trop ambitieux pour un chemin de secours; la priorite est la recuperabilite.

## Décision : Pause sur fenetres systeme transitoires

**Décision**: Detecter les roles/subroles AX transitoires et le service open/save Apple, puis suspendre les adaptations non essentielles pendant leur presence.

**Raison**: Les sheets/dialogues/popovers ne doivent pas etre deplaces par le tiler. Miri detecte ces cas pour rester en retrait. Roadie doit privilegier la securite UX.

**Alternatives étudiées**:

- Ignorer les transitoires : cause des bugs visibles.
- Ajouter des exclusions par app uniquement : ne couvre pas les panels systeme.
- Gerer chaque app au cas par cas : trop fragile.

## Décision : Layout persistence v2 par score d'identite

**Décision**: Ajouter `WindowIdentityV2` avec bundle ID, app name, title, role/subrole et metadata optionnelle, puis restaurer seulement si le score de confiance est suffisant et non ambigu.

**Raison**: Les IDs de fenetres sont volatils. Miri restaure via bundle/app/title; Roadie doit aller plus loin avec anti-doublon car il gere stages/desktops/groups.

**Alternatives étudiées**:

- Persister seulement les WindowID : casse apres restart.
- Matcher uniquement par titre : trop ambigu.
- Matcher agressivement meme si ambigu : risque de mauvais stage/group.

## Décision : Width presets/nudge en dernier

**Décision**: Ajouter les commandes width presets/nudge apres les services de controle et securite.

**Raison**: La valeur power-user est claire, mais le risque est inferieur aux garanties de config/restore/transient. Les commandes doivent respecter les intentions de layout existantes.

**Alternatives étudiées**:

- En faire le MVP : moins utile pour la stabilite globale.
- Reporter a une future session : acceptable si les cinq premiers blocs consomment toute la session.

## Décision : Exclure animations et private frameworks

**Décision**: Aucune animation de fenetres, aucun usage SkyLight/MultitouchSupport dans cette session.

**Raison**: Roadie a deja tranche la prudence autour des APIs privees et des limitations Tahoe. Les animations Miri sont utiles pour son modele camera/colonnes, mais pas necessaires pour Roadie Control & Safety.

**Alternatives étudiées**:

- Porter le moteur d'animation Miri : trop risqué, peut interagir avec manual resize et focus drift.
- Ajouter un flag experimental : cree de la dette avant les fondations de securite.
