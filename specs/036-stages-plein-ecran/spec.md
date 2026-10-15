# Session 036 — Préserver les stages pendant le plein écran

Validée le 15 octobre 2026 par « corrige ». Correction, tests, installation et vérification réelle autorisés.

## Problème et preuve
Le plein écran Teams sur l’écran interne rend huit fenêtres existantes absentes du relevé limité aux fenêtres à l’écran. Le rail retire leurs vignettes après 15 secondes. La conservation des membres expire après 30 minutes. CGWindowList optionAll confirme les huit identités et leurs PID ; aucun groupe ne doit être reconstruit par simple ressemblance de titre.

## Exigences
- FR-001 : une fenêtre déjà gérée, confirmée existante avec le même ID et PID, garde sa stage et sa vignette, même sur un Space inactif.
- FR-002 : une fermeture confirmée ou un PID différent ne ressuscite pas une vignette.
- FR-003 : l’inventaire de présence ne participe ni à l’adoption ni au placement des fenêtres.
- FR-004 : aucune mutation des noms, rangs, groupes, favoris et écrans ; menus et positions utilisent la même présence que le rail.
- FR-005 : régression après plus de 30 minutes simulées et test réel de plein écran de plus de 15 secondes ; version installée et santé vérifiées.

Hors périmètre : autres corrections de l’audit 035 et refonte des bureaux macOS.
