# Vérification — 144

1. Exécuter scripts/test --filter Spec144. Vérifier courbes, quatre combinaisons d’aperçu, annulation, refus, contexte et résultat différé.
2. Exécuter scripts/test puis python3 -m unittest discover -s scripts/tests. Conserver sorties et codes de retour.
3. Dans Paramètres > Effets, tester on/off, chaque profil, surcharge, aperçu local et retour aux défauts. Relire le TOML. Tester FR et EN.
4. Ouvrir des fenêtres de test sans contenu privé. Stabiliser frame, CG ID/PID, scope et écran pendant une seconde avant tout clic. Dans Aperçu réel, glisser paysage vers portrait ; poursuivre le mouvement ; relâcher, puis rejouer et annuler. Vérifier cadre avant/pendant/après et affectations.
5. Rejouer sur Finder, navigateur, éditeur et taille imposée ; titre, rail, écran interne/externe ; contenu/tab/contrôles non captés. Changement de stage, fermeture d’application et nouveau clic pendant animation.
6. Comparer off/on : 30 s repos, séries de 10 gestes, mêmes fenêtres. CPU/RSS Roadie+WindowServer+app, latences p50/p95. GPU : noter outil et accès ; absence d’accès = mesure non disponible.
7. Capturer uniquement les fenêtres fictives contrôlées. Générer le diaporama de parcours observé. Limites et étapes non observées explicites.
8. Audit V15 puis intégration/push vérifié/build signé/installation. Vérifier UUID, signature, PID et daemon health 5/5. Ne pas annoncer livré avant cette vérification.
