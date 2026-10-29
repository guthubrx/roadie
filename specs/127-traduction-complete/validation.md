# Validation 127 - Interface entièrement traduite

- Environ 1 300 textes passés par `tr(fr, en)` dans 60 fichiers, au moyen d'un relevé des littéraux et d'un tableau
  de traductions par lot (`specs/127-traduction-complete/agent-brief.md` : règles et glossaire).
- Délégation : les trois lots prévus pour Bridget ont été refusés à l'admission (`expected_base_commit_required`,
  puis `routing_candidate_unavailable` : 18 candidats sans capacité, 10 aux droits modifiés), sans tâche créée.
  Traduction faite par le responsable de la session.
- Rendu réel vérifié : fenêtre des paramètres dessinée hors écran en anglais (Général, Raccourcis, Tuilage, Rail,
  Sélecteur, Règles, Recherche) par un test jetable, relue à l'écran puis supprimée.
- Messages de validation anglais existants désormais traduits en français (`configuration valide`, `doit être entre
  12 et 96`…) ; `ConfigTests` et `TitlebarContextMenuTests` (« Bureau 1 ») mis à jour.
- Tests : `Spec127InterfaceLanguageSettingTests` (priorité environnement > réglage > macOS, trois choix).
  Suite complète : 2 278 tests / 333 suites réussis.
- Installation signée `roadied-cert`, PID 31686, santé 5/5. Choix de l'utilisateur : réglage par défaut
  (`auto`), donc anglais sur ce poste ; configuration non modifiée.
- Non vérifié : relance automatique au changement de langue depuis les paramètres (clic non simulable ici) ;
  `roadie daemon restart` reste la voie manuelle.
- Preuves : pas de diaporama, clics simulés refusés sur ce poste ; rendu des paramètres relu en image.
