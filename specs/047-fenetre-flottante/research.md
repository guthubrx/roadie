# Recherche - 047

- TrellisWM 0.9.5 : libellés « Docks and floats windows », « Float All Windows on
  Desktop » ; « Desktop » y désigne une zone propre à Trellis, non retenue.
- Roadie : `toggle floating` déclarée non implémentée (`CLICommandRouter.swift:243`).
  La règle `action.floating` existe mais demande d'éditer la configuration.
- Option écartée : rendre la fenêtre non candidate au tuilage par une liste dédiée.
  Elle quitterait sa stage et resterait visible sur toutes les stages, comme une
  fenêtre exclue. L'épinglage conserve déjà la stage d'origine et le dernier cadre.
