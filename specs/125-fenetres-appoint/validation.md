# Validation 125 - Fenêtres d'appoint

- Tests : `Spec125AuxiliaryWindowsTests` (titre généralisé et jokers, règle plus forte que celle de
  l'application, ajout et retrait par le menu avec commentaires conservés, premier cadre) et catalogue des
  paramètres. Suite complète : 2 272 tests / 331 suites réussis.
- `roadie rules validate` : ok. Installation signée `roadied-cert`, PID 53726, santé 5/5.
- Essai réel par l'utilisateur le 29 octobre 2026 : menu Fenêtre sur le rappel de Thunderbird, puis rappels
  flottants. Confirmation : « Pour les reminders, ça marche très bien ». Ligne relue dans `roadies.toml` :
  `app = "Thunderbird"`, `title = "# Reminder"`.
- Preuves : pas de diaporama, les clics et touches simulés sont refusés sur ce poste ; essai confirmé par
  l'utilisateur.
- Non vérifié : fenêtres d'Excel (aucun titre réel relevé).
