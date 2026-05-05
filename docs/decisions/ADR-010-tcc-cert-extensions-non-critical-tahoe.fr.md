# ADR-010 — Extensions X.509 non-critical pour le cert dev TCC sur macOS Tahoe

🇫🇷 **Français** · 🇬🇧 [English](ADR-010-tcc-cert-extensions-non-critical-tahoe.md)

**Statut** : Accepté
**Date** : 2026-05-05
**Lié à** : ADR-008 (signing & distribution strategy)

## Contexte

ADR-008 fige `roadied-cert` (self-signed code-signing identity dans le login keychain) comme l'identité stable qui ancre les grants TCC entre rebuilds. Il précise que le cert est « créé via Keychain Access > Certificate Assistant » mais **sans expliquer pourquoi cette modalité de création est non-substituable**.

Le 2026-05-05, lors d'une session de polish SPEC-026, j'ai automatisé la création du cert via un script OpenSSL (`scripts/create-codesign-cert.sh`) pour éviter la friction GUI Keychain Access. Le script générait un cert valide pour `codesign -fs roadied-cert`, mais avec une structure d'extensions **différente** de celle produite par Keychain Access :

| Extension | Keychain Access (mode standard) | Mon premier OpenSSL.cnf |
|---|---|---|
| `basicConstraints CA:FALSE` | non-critical | **critical** |
| `keyUsage digitalSignature` | non-critical | **critical** |
| `extendedKeyUsage codeSigning` | non-critical | **critical** |
| `subjectKeyIdentifier` | présent (hash de la clé publique) | absent |
| `authorityKeyIdentifier` | présent (= SKI sur self-signed) | absent |

Le binaire signé avec ce cert satisfaisait correctement son designated requirement (`identifier "com.roadie.roadied" and certificate leaf = H"…"`), `codesign -v` retournait `valid`, et lancé en shell le binaire récupérait Screen Recording grant via héritage du parent process. **Mais sous launchd, TCC refusait obstinément de stabiliser le grant** :

- L'utilisateur cochait `roadied` dans Réglages → Confidentialité → Enregistrement d'écran.
- L'icône s'affichait normalement, le toggle ON, mais `CGPreflightScreenCaptureAccess()` retournait `false` au boot du daemon.
- Décocher/recocher 4 fois consécutives n'a rien changé.
- Reset complet via `tccutil reset All com.roadie.roadied` + nouveau toggle non plus.
- Ajouter `SessionCreate=true` au plist launchd, lancer via `open` (Launch Services), redémarrer `tccd` user — aucun de ces leviers n'a déplacé le grant.

Heure perdue à diagnostiquer : **environ une heure**, après une session de plus de 4 heures de travail productif.

La cause racine n'a été trouvée qu'après recherche en ligne (issue OpenClaw#14138, thread Microsoft Q&A Teams sur Tahoe 26.4, Apple Developer Forums 730043) : **macOS Tahoe (15.x / 26.x) refuse de stabiliser un grant TCC pour un cert self-signed dont les extensions X.509 sont toutes flag `critical`**. Le binaire est exécutable, le grant est apparemment écrit dans `TCC.db`, mais à chaque vérif `Preflight` TCC ne valide pas la `csreq` stockée parce que la structure du cert sort des heuristiques internes que Tahoe accepte pour un cert non-Apple.

Le mode standard Keychain Access — celui auquel ADR-008 référait sans le nommer explicitement — produit toujours des extensions non-critical et inclut systématiquement `subjectKeyIdentifier` + `authorityKeyIdentifier`. C'est précisément cette structure qui satisfait les heuristiques TCC.

Le fix a été : régénérer le cert avec `basicConstraints`, `keyUsage`, `extendedKeyUsage` **non-critical**, en ajoutant `subjectKeyIdentifier = hash` et `authorityKeyIdentifier = keyid:always`. Re-signer le binaire, reset TCC, reboot Mac (purge des caches profonds TCC nécessaire après changement de cert leaf), re-cocher Accessibility + Screen Recording. Grant validé immédiatement, captures parallax-45 du rail fonctionnelles.

## Décision

### 1. Profile X.509 obligatoire pour `roadied-cert`

Le script `scripts/create-codesign-cert.sh` DOIT générer le cert avec exactement ce profile :

```ini
[v3_ext]
basicConstraints = CA:FALSE
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
```

Aucun `critical,` devant les directives. Toute déviation est une régression bloquante.

Si un développeur préfère créer le cert manuellement via Keychain Access > Certificate Assistant, il doit choisir le profile « Code Signing » (mode par défaut). C'est ce profile qui produit la structure attendue. Tout autre mode (« SSL Server », « SSL Client », template custom) produira un cert qui peut signer mais qui ne stabilisera pas la grant TCC sur Tahoe.

### 2. Vérification automatisée du profile

Le script `scripts/recheck-tcc.sh` est étendu (étape 1, signature) pour rejeter un cert dont l'une des extensions ci-dessus serait flag `critical`. Le check est :

```bash
# Extraction des extensions du cert avec leur flag critical/non-critical.
# Exit code 2 (signature corrompue) si Key Usage ou Extended Key Usage est critical.
EXTS_CRITICAL=$(security find-certificate -c roadied-cert -p login.keychain 2>&1 \
    | openssl x509 -text -noout 2>&1 \
    | grep -E "X509v3 (Basic Constraints|Key Usage|Extended Key Usage): critical" \
    | wc -l | tr -d ' ')

if [ "$EXTS_CRITICAL" -gt 0 ]; then
    echo "✗ cert 'roadied-cert' a des extensions flag 'critical' (incompatible TCC Tahoe)"
    echo "  → re-générer avec ./scripts/create-codesign-cert.sh --force"
    exit 2
fi
```

Cela pose un filet : la prochaine fois qu'un dev régénère le cert avec un mauvais template, le script bloque avant que le dev perde une heure à debug TCC.

### 3. Procédure post-changement de cert

Quand le cert leaf hash change (régénération volontaire ou non), TCC garde des `csreq` obsolètes en cache. **Un reboot complet du Mac est requis** — `killall tccd` ne suffit pas, le daemon TCC user-space relit le snapshot mais les caches kernel-level (responsibility chain, Launch Services bundle resolution) gardent l'ancien.

Procédure obligatoire :
1. `./scripts/create-codesign-cert.sh --force` (régénère le cert avec le bon profile)
2. `./scripts/install-dev.sh` (re-signe binaires, redémarre daemon)
3. `tccutil reset All com.roadie.roadied`
4. `rm -f ~/.roadies/last-tcc-toggle.hash`
5. **Reboot Mac**
6. Au boot, daemon en wait-loop AX → cocher Accessibility → daemon démarre
7. Au premier `CGWindowListCreateImage`, prompt Screen Recording → accepter
8. `./scripts/recheck-tcc.sh --mark-toggled` (fige la nouvelle baseline)

Aucun raccourci n'est connu. Tout `kickstart` ou `tccd` restart sans reboot a échoué dans nos tests.

### 4. Politique de conservation du cert

ADR-008 disait « si le cert est supprimé du keychain, en re-générer un (même nom) ». Cette formulation occulte le coût réel : la régénération **invalide tous les grants TCC accumulés** et exige le cycle complet de §3 (reboot + double toggle).

La consigne devient : **ne jamais régénérer le cert sans nécessité absolue**. La rotation préventive est interdite. Les seules raisons admises sont :
- Le cert a été supprimé/perdu (cf. orphelin sans clé privée — incident historique 2026-05-05).
- Le cert expire (la structure recommandée a `notAfter = +10 ans`, donc événement très rare).
- macOS rejette explicitement la signature (binaire non lançable).

## Conséquences

### Positives

- **Plus jamais d'heure perdue à debug TCC en aveugle** sur ce piège précis : le check automatique dans `recheck-tcc.sh` flag immédiatement un cert mal formé.
- **Le script `create-codesign-cert.sh` est désormais sûr par construction** : son template OpenSSL ne peut plus dériver vers un cert critical sans qu'on s'en rende compte.
- **La procédure post-changement de cert est documentée explicitement** : le « reboot obligatoire » n'est plus du folklore mais une étape figée.

### Négatives

- **Toute régénération de cert coûte un reboot Mac** : ce n'est pas une action triviale qu'on peut automatiser dans un workflow CI. Acceptable pour la phase dev solo, à reconsidérer pour une équipe.
- **L'ADR-008 ne suffit plus à lui seul** : tout dev qui rejoint le projet doit lire ADR-008 ET ADR-010 pour comprendre la stratégie complète signing/TCC.

### Neutres

- Pas d'impact sur la roadmap fonctionnelle (SPEC-026, famille HypRoadie SIP-off). C'est une couche infra orthogonale.

## Alternatives considérées

1. **Garder les extensions critical et patcher TCC.db directement.** Rejeté : la DB système est protégée par SIP, modification impossible sans désactiver SIP — hors scope core.
2. **Bypasser TCC via Developer ID Apple** (cf. ADR-008 chemin B). Rejeté pour la phase dev : 99 $/an + signature renewal cycle, le coût ne se justifie qu'en distribution end-user.
3. **Utiliser `ScreenCaptureKit` au lieu de `CGWindowListCreateImage`.** Considéré comme amélioration future indépendante : SCK est l'API moderne et probablement plus tolérante aux profiles cert exotiques. Mais le bug TCC reste sur la chaîne `CGRequestScreenCaptureAccess` / `CGPreflightScreenCaptureAccess`, donc SCK ne résout pas le problème de fond — il déplacerait juste le check ailleurs.
4. **Supprimer le check de cert dans `recheck-tcc.sh` et juste documenter le piège.** Rejeté : la doc seule est insuffisante, l'erreur s'est produite parce qu'ADR-008 ne mentionnait pas le profile X.509 explicitement et que je suis tombé dans le piège en automatisant. Un check programmatique est le seul filet fiable.

## Sources

- [Issue OpenClaw#14138 — `[macOS Tahoe] screencapture via exec tool fails — TCC Screen Recording permission not inherited by Gateway LaunchAgent`](https://github.com/openclaw/openclaw/issues/14138)
- [Microsoft Q&A — `Teams for Mac screen sharing permission loop on macOS Tahoe 26.4 — TCC permissions verified correct`](https://learn.microsoft.com/en-us/answers/questions/5848423/teams-for-mac-screen-sharing-permission-loop-on-ma)
- [Apple Developer Forums 730043 — `How to handle TCC permissions on multiple architectures`](https://developer.apple.com/forums/thread/730043)
- [Apple Developer Forums 682140 — `Issue with applying EV Code Signing Certificate on Big Sur`](https://developer.apple.com/forums/thread/682140) (historique : la même classe de bug existait avec Big Sur EV certs)
- [eclecticlight.co — `What's happening with code signing and future macOS?`](https://eclecticlight.co/2026/01/17/whats-happening-with-code-signing-and-future-macos/)
- ADR-008 — stratégie signing & distribution (référence amont qui ne mentionnait pas le profile X.509)
- Logs incident 2026-05-05 : `~/.local/state/roadies/daemon.log` (séquence `screen_capture_state granted=false` répétée pendant ~1h, résolue après régénération cert non-critical + reboot)
