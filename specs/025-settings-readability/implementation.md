# Journal — session 025

## Résultat

Tailles indépendantes et persistées pour les paramètres, le rail, les lettres,
la grille et la recherche. Application pendant le déplacement des curseurs,
le pas à pas et la saisie valide ; les sessions ouvertes gardent leur état.
Les menus natifs des paramètres et leurs boutons suivent la taille choisie.
`balanced` est affiché sans réécriture de la configuration à l'ouverture.

## Vérifications

- Test préalable : reproduit le refus de `balanced` dans le catalogue.
- 124 tests ciblés, 14 suites : succès après les corrections de revue.
- Reconstruction complète : 1 372 tests Swift, 146 suites, succès ; dernière vérification en 6,244 s après compilation.
- Scripts : 26 tests, succès.
- Test UI réel hors écran : le même menu natif passe de 16 à 24 points sans rouvrir la fenêtre ; aides et titres indépendants.
- Saisie `8.` puis `8.5` conservée ; nombres incomplets non appliqués ; pas à pas met le champ à jour.
- Rail étroit : cadres et six zones de clic vérifiés pour 90, 150 et 320 points.
- Rendus hors écran inspectés : Général, Tuilage en clair et sombre, textes de 16 et 24 points.
- Revue indépendante en quatre tours : pas de défaut bloquant dans le diff final.
- Installation release terminée ; signature `roadied-cert` conservée.
- Redémarrage vérifié : daemon PID 96907, version 0.4.0 ; quatre contrôles de santé OK, accès d'accessibilité et capture d'écran autorisés, configuration valide.
- Validation manuelle : l'utilisateur confirme « Oui, cela fonctionne » pour les changements immédiats et indépendants dans `/settings`.

## Décisions de revue

Conserver notification immédiate et surveillance du fichier : les changements dans
les paramètres et les changements externes ont besoin des deux chemins. Le rail
déduplique les événements avant le traitement coûteux. Les polices des badges sont
réutilisées pendant le dessin. Hauteur, dessin et clics des cartes partagent leur calcul.
Six icônes restent visibles, avec une septième case pour le compteur si nécessaire.
`balanced` et `largest_dim` sont équivalents dans le moteur ; la sélection de la valeur
héritée reste autorisée conformément à la demande initiale.

Les curseurs écrivent à chaque pas entier pour satisfaire la mise à jour immédiate
demandée. La saisie décimale conserve son brouillon. Les tailles effectives sont bornées,
sans réécrire une valeur brute hors plage lors de l'ouverture du fichier.

## Incident de validation

Deux suites complètes ont planté dans un ancien test de tuilage, avec SIGSEGV lors
de la copie de TilingConfig. Le rapport macOS et les dates des objets compilés ont
montré un test compilé avant l'ajout de InterfaceConfig. `swift package clean`, puis
reconstruction complète, ont éliminé le mélange de layouts compilés. Aucun correctif
du moteur de tuilage n'a été nécessaire.

## Limites et livraison

Les textes gérés par macOS, dont les infobulles et messages de dialogue natifs,
gardent leur police système. La capture du bureau reste indisponible ; les rendus
NSHostingView ne constituent pas un test physique des fenêtres sur tous les écrans.
La correction est installée, active et validée par l'utilisateur.
Le focus clavier et le contraste des boutons personnalisés restent à confirmer sur le bureau.
Aucune nouvelle release publiée.

## Livraison Git

Commit fonctionnel : `74412a16`. Les README français et anglais décrivent les réglages.
Le changelog les range dans « À publier », sans changement de version.
La livraison est fusionnée sur `main`. Le worktree et sa branche restent conservés
tant que cette conversation est liée à cet espace dans T3 ; aucun autre worktree
ou branche de session ne reste à nettoyer.
