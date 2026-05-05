# ADR-010 — Non-critical X.509 extensions for the dev TCC cert on macOS Tahoe

🇬🇧 **English** · 🇫🇷 [Français](ADR-010-tcc-cert-extensions-non-critical-tahoe.fr.md)

**Status**: Accepted
**Date**: 2026-05-05
**Related to**: ADR-008 (signing & distribution strategy)

## Context

ADR-008 pins `roadied-cert` (self-signed code-signing identity in the login keychain) as the stable identity that anchors TCC grants across rebuilds. It states that the cert is "created via Keychain Access > Certificate Assistant" but **does not explain why this creation modality is non-substitutable**.

On 2026-05-05, during a SPEC-026 polish session, I automated cert creation via an OpenSSL script (`scripts/create-codesign-cert.sh`) to avoid the GUI Keychain Access friction. The script produced a cert valid for `codesign -fs roadied-cert`, but with an extension structure **different** from what Keychain Access produces:

| Extension | Keychain Access (default mode) | My initial OpenSSL.cnf |
|---|---|---|
| `basicConstraints CA:FALSE` | non-critical | **critical** |
| `keyUsage digitalSignature` | non-critical | **critical** |
| `extendedKeyUsage codeSigning` | non-critical | **critical** |
| `subjectKeyIdentifier` | present (hash of public key) | absent |
| `authorityKeyIdentifier` | present (= SKI on self-signed) | absent |

The binary signed with this cert correctly satisfied its designated requirement (`identifier "com.roadie.roadied" and certificate leaf = H"…"`), `codesign -v` returned `valid`, and when launched from a shell the binary picked up Screen Recording grant via parent-process inheritance. **But under launchd, TCC stubbornly refused to stabilize the grant**:

- The user ticked `roadied` in System Settings → Privacy → Screen Recording.
- The icon rendered correctly, the toggle was ON, but `CGPreflightScreenCaptureAccess()` returned `false` at daemon boot.
- Untick/retick four times in a row changed nothing.
- A full reset via `tccutil reset All com.roadie.roadied` plus a fresh toggle either.
- Adding `SessionCreate=true` to the launchd plist, launching via `open` (Launch Services), restarting the user `tccd` — none of these levers moved the grant.

Time wasted diagnosing: **about an hour**, after a productive 4+ hour session.

The root cause was only found via online search (OpenClaw#14138, Microsoft Q&A thread on Teams under Tahoe 26.4, Apple Developer Forums 730043): **macOS Tahoe (15.x / 26.x) refuses to stabilize a TCC grant for a self-signed cert whose X.509 extensions are all flagged `critical`**. The binary is executable, the grant is apparently written into `TCC.db`, but each `Preflight` check rejects the stored `csreq` because the cert structure falls outside the heuristics Tahoe accepts for a non-Apple cert.

The Keychain Access default mode — what ADR-008 was implicitly referring to — always produces non-critical extensions and consistently includes `subjectKeyIdentifier` + `authorityKeyIdentifier`. That structure is precisely what satisfies the TCC heuristics.

The fix was: regenerate the cert with `basicConstraints`, `keyUsage`, `extendedKeyUsage` **non-critical**, adding `subjectKeyIdentifier = hash` and `authorityKeyIdentifier = keyid:always`. Re-sign the binary, reset TCC, reboot the Mac (deep TCC cache purge is mandatory after a cert leaf change), re-tick Accessibility + Screen Recording. Grant validated immediately, rail parallax-45 captures functional.

## Decision

### 1. Mandatory X.509 profile for `roadied-cert`

The `scripts/create-codesign-cert.sh` script MUST generate the cert with exactly this profile:

```ini
[v3_ext]
basicConstraints = CA:FALSE
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
```

No `critical,` prefix on any directive. Any deviation is a blocking regression.

If a developer prefers to create the cert manually via Keychain Access > Certificate Assistant, they must select the "Code Signing" profile (default mode). That profile produces the expected structure. Any other mode ("SSL Server", "SSL Client", custom template) yields a cert that can sign but will not stabilize the TCC grant on Tahoe.

### 2. Automated profile verification

The `scripts/recheck-tcc.sh` script is extended (step 1, signature) to reject any cert with critical-flagged extensions. The check is:

```bash
# Extract cert extensions with their critical/non-critical flag.
# Exit code 2 (corrupted signature) if Key Usage or Extended Key Usage is critical.
EXTS_CRITICAL=$(security find-certificate -c roadied-cert -p login.keychain 2>&1 \
    | openssl x509 -text -noout 2>&1 \
    | grep -E "X509v3 (Basic Constraints|Key Usage|Extended Key Usage): critical" \
    | wc -l | tr -d ' ')

if [ "$EXTS_CRITICAL" -gt 0 ]; then
    echo "✗ cert 'roadied-cert' has 'critical'-flagged extensions (incompatible with TCC Tahoe)"
    echo "  → regenerate via ./scripts/create-codesign-cert.sh --force"
    exit 2
fi
```

This is a safety net: the next time a dev regenerates the cert with a wrong template, the script blocks before the dev wastes an hour debugging TCC.

### 3. Procedure after a cert change

When the cert leaf hash changes (whether or not the regeneration was intentional), TCC keeps stale `csreq` entries in cache. **A full Mac reboot is required** — `killall tccd` is not sufficient. The user-space TCC daemon re-reads the snapshot, but kernel-level caches (responsibility chain, Launch Services bundle resolution) keep the old one.

Mandatory procedure:
1. `./scripts/create-codesign-cert.sh --force` (regenerate the cert with the correct profile)
2. `./scripts/install-dev.sh` (re-sign binaries, restart daemon)
3. `tccutil reset All com.roadie.roadied`
4. `rm -f ~/.roadies/last-tcc-toggle.hash`
5. **Reboot Mac**
6. At boot, daemon enters AX wait-loop → tick Accessibility → daemon starts
7. On the first `CGWindowListCreateImage`, Screen Recording prompt appears → accept
8. `./scripts/recheck-tcc.sh --mark-toggled` (pin the new baseline)

No shortcut is known. Every `kickstart` or `tccd` restart without a reboot failed in our tests.

### 4. Cert retention policy

ADR-008 used to say "if the cert is deleted from the keychain, regenerate one (same name)". This formulation hides the real cost: regeneration **invalidates every accumulated TCC grant** and forces the full §3 cycle (reboot + double toggle).

The rule becomes: **never regenerate the cert unless absolutely necessary**. Preventive rotation is forbidden. The only admissible reasons are:
- The cert was deleted/lost (cf. orphaned without private key — historical incident 2026-05-05).
- The cert expires (recommended structure has `notAfter = +10 years`, so very rare event).
- macOS explicitly rejects the signature (binary unlaunchable).

## Consequences

### Positive

- **No more hour-long blind TCC debugging** on this specific trap: the automated check in `recheck-tcc.sh` flags a malformed cert immediately.
- **The `create-codesign-cert.sh` script is now safe by construction**: its OpenSSL template can no longer drift toward a critical-flagged cert without us noticing.
- **The post-cert-change procedure is documented explicitly**: the "mandatory reboot" is no longer folklore but a pinned step.

### Negative

- **Every cert regeneration costs a Mac reboot**: this is not a trivial action one can automate in a CI workflow. Acceptable for the solo dev phase, to be reconsidered for a team.
- **ADR-008 is no longer self-sufficient**: any dev joining the project must read both ADR-008 AND ADR-010 to understand the full signing/TCC strategy.

### Neutral

- No impact on the functional roadmap (SPEC-026, HypRoadie SIP-off family). This is an orthogonal infra layer.

## Considered alternatives

1. **Keep critical extensions and patch TCC.db directly.** Rejected: the system DB is SIP-protected, modification is impossible without disabling SIP — out of core scope.
2. **Bypass TCC via Apple Developer ID** (cf. ADR-008 path B). Rejected for the dev phase: $99/year + signature renewal cycle, the cost is justified only for end-user distribution.
3. **Use `ScreenCaptureKit` instead of `CGWindowListCreateImage`.** Considered as an independent future improvement: SCK is the modern API and probably more tolerant of exotic cert profiles. But the TCC bug sits on the `CGRequestScreenCaptureAccess` / `CGPreflightScreenCaptureAccess` chain, so SCK does not solve the underlying issue — it just moves the check elsewhere.
4. **Drop the cert check in `recheck-tcc.sh` and just document the trap.** Rejected: documentation alone is insufficient. The error happened because ADR-008 didn't mention the X.509 profile explicitly and I fell into the trap while automating. A programmatic check is the only reliable safety net.

## Sources

- [OpenClaw issue #14138 — `[macOS Tahoe] screencapture via exec tool fails — TCC Screen Recording permission not inherited by Gateway LaunchAgent`](https://github.com/openclaw/openclaw/issues/14138)
- [Microsoft Q&A — `Teams for Mac screen sharing permission loop on macOS Tahoe 26.4 — TCC permissions verified correct`](https://learn.microsoft.com/en-us/answers/questions/5848423/teams-for-mac-screen-sharing-permission-loop-on-ma)
- [Apple Developer Forums 730043 — `How to handle TCC permissions on multiple architectures`](https://developer.apple.com/forums/thread/730043)
- [Apple Developer Forums 682140 — `Issue with applying EV Code Signing Certificate on Big Sur`](https://developer.apple.com/forums/thread/682140) (historical: same class of bug existed with Big Sur EV certs)
- [eclecticlight.co — `What's happening with code signing and future macOS?`](https://eclecticlight.co/2026/01/17/whats-happening-with-code-signing-and-future-macos/)
- ADR-008 — signing & distribution strategy (upstream reference that did not mention the X.509 profile)
- Incident logs 2026-05-05: `~/.local/state/roadies/daemon.log` (sequence of `screen_capture_state granted=false` repeated for ~1h, resolved after non-critical cert regeneration + reboot)
