# Spécification 128 - Publication de Roadie 0.11.0

Demande du 29 octobre 2026 : « on a tout commit, merge, push et release ? », puis choix « Oui, publier la 0.11.0 ».

## Périmètre
Version mineure depuis v0.10.0 : 115 commits, sessions 073 à 127. Lanceur dans la barre (applications, fenêtres,
fichiers, signets, réglages, web, calcul), verbes, destinations et phrases, workflows d'Alfred sans Powerpack,
thèmes, interface en anglais ou en français, fenêtres toujours flottantes par titre, sélecteur et paramètres.

## Exigences
- Version 0.11.0 dans `DaemonHealth`, `scripts/package-dmg`, CHANGELOG daté, README FR/EN sans l'avertissement
  « pas encore publié », notes FR/EN dans `docs/releases/`.
- Tests Swift et tests de scripts réussis ; DMG vérifié (intégrité, contenu, version, signature, architecture).
- Tag annoté v0.11.0, release GitHub Latest avec `Roadie.dmg` et `Roadie.dmg.sha256`, fichiers retéléchargés et
  comparés ; installation locale et santé.
