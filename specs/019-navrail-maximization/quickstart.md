# Essai

1. Ouvrir plusieurs fenêtres dans la même stage.
2. Focaliser une fenêtre et lancer `roadie toggle maximize`.
3. Vérifier qu'elle remplit la zone à droite du rail. Les voisines de sa stage sont cachées.
4. Relancer la commande pour retrouver la disposition.
5. Alterner `roadie toggle maximize` et `roadie toggle fullscreen`, puis répéter la dernière commande pour restaurer.
6. Tester le menu de titre activé : clic droit sur une fenêtre, « Fenêtre », maximiser/restaurer.
7. Avec auto-hide, le rail masqué laisse toute la zone utile. Un survol ou `roadie rail pin` redimensionne la fenêtre pour dégager le rail. Ne pas modifier la configuration pour essayer la commande.

Vérification automatisée : `./scripts/with-xcode swift test`.


## Vérification des corrections de placement

1. Maximiser une fenêtre, changer de stage puis revenir : le zoom et la disposition précédente doivent rester disponibles.
2. Activer volontairement une voisine ou ouvrir une nouvelle fenêtre de la stage zoomée : sortie de zoom et disposition directement visible, sans cacher puis réafficher la cible.
3. Redimensionner réellement une fenêtre active : conserver le geste. Un déplacement automatique du rail ou d’une stage ne doit pas compter comme ce geste.
4. Entrer et sortir du plein écran natif : ne pas appliquer de cible tilée au natif. Les reprises doivent rester bornées et les refus permanents explicites.
5. Redémarrer avec une fenêtre déjà visible et une fenêtre cachée : préserver la visible, restaurer la cachée, garder un refus réel en reprise. Ne pas déclarer un faux crash pour un arrêt intentionnel.

6. Lorsque le focus système est momentanément absent, conserver le zoom pendant plusieurs passages de maintenance ; le focus mémorisé seul ne déclenche pas une activation de voisine.
