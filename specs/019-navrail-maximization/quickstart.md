# Essai

1. Ouvrir plusieurs fenêtres dans la même stage.
2. Focaliser une fenêtre et lancer `roadie toggle maximize`.
3. Vérifier qu'elle remplit la zone à droite du rail. Les voisines de sa stage sont cachées.
4. Relancer la commande pour retrouver la disposition.
5. Alterner `roadie toggle maximize` et `roadie toggle fullscreen`, puis répéter la dernière commande pour restaurer.
6. Tester le menu de titre activé : clic droit sur une fenêtre, « Fenêtre », maximiser/restaurer.
7. Avec auto-hide, le rail peut se masquer mais sa bande reste réservée. Ne pas modifier la configuration pour essayer la commande.

Vérification automatisée : `./scripts/with-xcode swift test`.
