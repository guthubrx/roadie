# Mesures de Roadie installé (session 131)

- Installation : Roadie signé `roadied-cert`, PID 65429, santé 5/5 (process, daemon-status, self-test, state-audit,
  macos-window-settings), UUID 7A80EA05-6ABB-3822-A501-C52F59FD3137, configuration identique avant et après
  (empreinte 166624a713447bc4). Fonctions nouvelles non exercées à l'écran (clics simulés refusés).
- Mémoire : roadied 246 Mio résidents après redémarrage (pas de mesure antérieure à la session pour comparer) ;
  catalogue SF Symbols (`mesure-memoire.swift`) : 23 ms et environ 5 Mio, chargé seulement à l'ouverture du
  navigateur et gardé ensuite.
- Poids : binaire `roadied` 21 833 056 octets contre 21 326 944 pour la 0.11.1 publiée (DMG retéléchargé), soit
  +506 112 octets (+2,4 %) ; aucune dépendance ajoutée.
- Compatibilité des réglages : les six clés ajoutées (`return_cmd`, `return_alt`, `return_ctrl`,
  `workflow_view_style`) sont facultatives avec des défauts identiques au comportement antérieur ; une valeur
  inconnue revient au défaut (`Spec131ReturnModifiersTests`, `Spec131ThemeTests`) ; fichier d'épinglage nouveau,
  absent = vide.
