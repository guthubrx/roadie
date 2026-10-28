# Validation 107

- Tests : `Spec107SettingsSearchTests` (catégorie et groupe trouvés, colonne filtrée, catégorie choisie,
  retour à tous les résultats) ; `SettingsCatalogTests` et `SettingsViewModelTests` mis à jour : « bordure »
  trouve aussi la liste des exceptions par stage (7 réglages).
- 70 tests des paramètres réussis.
- Vitesse, mesures jetables sur une copie du fichier réel, fenêtre 1100 × 800 :
  « p » 4,6 s → 0,2 à 0,3 s ; « t » 3,3 s → 0,15 à 0,24 s ; « po » 0,86 s → 0,1 s ; « police » 0,04 s.
  Les mesures varient d'environ ±50 % selon la charge. Menus de police remplis à l'ouverture : gain dans le
  bruit (148 → 108 ms), changement retiré.
- `Spec107LiteralIndexTests` : index identique à `readLiteral` sur un fichier piégé ; vérification jetable
  identique sur les 246 réglages du fichier réel.
