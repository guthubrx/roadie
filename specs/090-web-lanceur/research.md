# Recherche 090

## R1 Reconnaître une adresse
Règles, dans l'ordre, sur une saisie sans espace : schéma `http://`/`https://` → adresse ;
`localhost` ou adresse IPv4, avec port facultatif → `http://` ; `www.` en tête → `https://` ;
`nom.suffixe` (plus éventuellement `/chemin`, `:port`, `?…`) où le suffixe est dans une liste
fermée de suffixes courants (com, net, org, io, dev, app, fr, de, uk, eu, be, ch, ca, us, info, ai,
co, me, tv, gg, ly, es, it, nl, se, no, dk, fi, pl, pt, at, jp, cn, ru, br, in, au, nz, xyz, site,
online, tech, cloud, page, so) → `https://`. Exclus volontairement : suffixes qui sont aussi des
extensions de fichiers courantes (md, sh, py, rs, js, ts, txt, pdf, zip, swift, json, yml, toml,
app après un nom de fichier…) sauf avec `/`, `:port` ou `www.`. `fichier.txt` et `a.b` ne sont
donc pas des adresses ; `readme.md/` le devient (choix explicite de l'utilisateur).

## R2 Ouvrir une adresse dans une stage
Les projets (080) rouvrent une adresse par `NSWorkspace.open([url], withApplicationAt:)` : le
navigateur ouvre souvent un onglet dans une fenêtre existante, et la mise en place attend une
nouvelle fenêtre (`placeNewWindow`, 10 s). Pour « Ouvrir dans… » : navigateurs Chromium (Chrome,
Brave, Edge, Arc, Vivaldi) → `open -na <app> --args --new-window <url>` (l'instance en cours ouvre
une fenêtre) ; Safari → AppleScript `make new document with properties {URL:…}` ; Firefox →
`open -a Firefox --args -new-window <url>` n'est pas pris en compte quand il tourne : ⌘N puis
ouverture de l'adresse (la nouvelle fenêtre reçoit l'adresse dans un onglet ; un onglet vide peut
rester, limite notée). Puis `placeNewWindow` (réutilisé) place la fenêtre neuve.

## R3 Recherches par mot-clé
TOMLKit décode les tableaux de tables (`[[...]]`) en `[WebSearch]` par `Codable` : pas de nouveau
format. Défauts (si la clé est absente) : g Google, yt YouTube, wp Wikipédia (fr), ddg
DuckDuckGo, maps Plans d'Apple (`maps://?q={query}`). Une clé présente et vide = aucune recherche.

## R4 Historique
`~/.roadies/launcher-history.json`, 20 entrées `{query, at}`, écrit à l'exécution d'une action
avec une saisie non vide (même endroit que `recordVisit`). Reprise sous 5 minutes : le champ natif
reçoit la saisie et `selectAll` ; la frappe remplace donc le texte comme dans Alfred. Barre vide :
la section « Recherches récentes » prend place après les propositions de la 081.
