# Validation de Roadie 0.7.0

## Périmètre
Version mineure depuis v0.6.0, sessions 055 à 058. Publication explicitement
demandée. Version applicative et défaut du script DMG alignés à 0.7.0 ; dépendance
TOMLKit inchangée. README, guides, index et notes FR/EN synchronisés.
Cette session ne change pas le comportement de l'interface et n'ajoute pas de
nouvelle preuve visuelle. Les limites de la session 058 restent applicables.

## Vérifications
Validation de livraison en cours. Le reçu sera complété avant le tag.
La suite précédente sur le code 058 a réussi : 1 876 tests dans 231 suites,
puis tests ciblés du dernier ajustement. Les contrôles de la version 0.7.0,
du DMG et de la publication sont consignés ci-dessous après exécution.

## Distribution
Compilation sur macOS 26.2, arm64. Cible : macOS 14 et ultérieur, Apple Silicon.
Pas d'essai sur Intel ou macOS 14 dans cette livraison. Paquet signé ad hoc,
non notarisé. La recette de paquet utilise --skip-jenkins pour éviter les
actions Finder indisponibles ; les fichiers et le lien Applications sont
conservés, sans présentation Finder personnalisée. Installation locale avec
le certificat existant, distinct de la signature du paquet public.
