# Complexité et performance

Méthode : heuristique `nested_scan.py` (copie dans ce dossier) qui repère une recherche linéaire, un
tri ou un `removeFirst` dans le corps d'une boucle ou d'une fermeture de parcours : 181 signaux sur
Sources. Ceux des chemins chauds (LayoutMaintainer, DaemonSnapshot, StageStore, DisplayParking,
LauncherSearchContext, TargetModeRuntimeController, TargetOverlayPresenter) ont été relus.

- Écrans, bureaux, scopes : recherches linéaires sur n ≤ quelques dizaines (écrans ≤ 4 en pratique) :
  coût négligeable, conforme à la borne naturelle ; plusieurs ne sont pas annotées.
- Barre vide, « Souvent ici » : tri des entrées du classement puis recherche linéaire dans le catalogue
  d'applications pour chaque entrée, O(e log e + e × a), e et a de l'ordre de quelques centaines, à
  l'ouverture de la barre ; `prefix` appliqué après le parcours complet. Mesures de la session 123
  (ouverture 0,26 s au plus) : pas de défaut démontré.
- `FirefoxTabSelector.select` : O(n²) par `removeFirst`, n ≤ 4 000 (constat F-FIREFOX-BFS, LOW).
- Index des littéraux TOML : O(L) par texte, O(1) par valeur (session 107) ; correction de fidélité
  seulement (F-LITERAL-EMPTY).
- Historique Safari : sous-requêtes corrélées par élément, sur une copie hors du fil principal, LIMIT 2 000.
- Copies SQLite : `places.sqlite` copié à chaque relecture (cache 60 s pour les signets, 300 s pour
  l'historique), hors du fil principal ; coût disque proportionnel à la base, non mesuré ici.
- `RoadieCommandHotkeys` : relecture de la configuration et de la table clavier (128 traductions)
  toutes les 2 s sur le fil principal ; coût non mesuré, faible par construction.
- Caches bornés : historique 20, cache Script Filter 200, classement élagué ; dossier des icônes de
  favoris non élagué (un fichier par adresse de signet).

Aucune mesure avant/après n'a été faite dans cet audit : aucun gain ni régression de durée n'est affirmé.
