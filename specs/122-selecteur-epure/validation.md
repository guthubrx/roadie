# Validation 122 : sélecteur réduit aux fenêtres

- 2 tests `Spec122SwitcherChromeTests` : aucun texte hors cartes avec le profil par défaut, grille à 16 points des
  bords ; recherche en haut et refus d'action en bas quand ils sont montrés.
- Rendu natif hors écran du panneau (`ROADIE_SWITCHER_RENDER_DIR`) : ni titre, ni résumé, ni aide.
- Profil réel « all » : action au relâchement « focus », recherche et Actions automatiques, donc masqués.
- Non vérifié à l'écran avec de vraies fenêtres : clics et touches simulés refusés sur ce poste, pas de diaporama.
