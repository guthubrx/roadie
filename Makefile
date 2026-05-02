.PHONY: build install install-all clean test app-bundle install-app build-fx install-fx uninstall-fx uninstall-all verify-no-cgs-write build-rail install-rail uninstall-rail

PREFIX ?= $(HOME)/.local
APPDIR ?= $(HOME)/Applications
APP_ID := local.roadies.daemon
APP_NAME := roadied.app

# Override PATH pour éviter le ld d'anaconda qui ne supporte pas
# l'option -no_warn_duplicate_libraries (Memory: SPEC-001).
SHELL := /bin/bash
export PATH := /usr/bin:/usr/local/bin:/bin:$(PATH)

build:
	swift build -c release

clean:
	swift package clean
	rm -rf .build .swiftpm
	rm -rf $(APP_NAME)

test:
	swift test

# Install les 2 binaires CLI dans ~/.local/bin/
install: build
	mkdir -p $(PREFIX)/bin
	install -m 755 .build/release/roadie  $(PREFIX)/bin/roadie
	install -m 755 .build/release/roadied $(PREFIX)/bin/roadied

# Bundle .app pour TCC Sequoia+ (leçon SPEC-001)
app-bundle: build
	rm -rf $(APP_NAME)
	mkdir -p $(APP_NAME)/Contents/MacOS
	cp .build/release/roadied $(APP_NAME)/Contents/MacOS/roadied
	printf '<?xml version="1.0" encoding="UTF-8"?>\n\
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n\
<plist version="1.0">\n\
<dict>\n\
	<key>CFBundleExecutable</key><string>roadied</string>\n\
	<key>CFBundleIdentifier</key><string>$(APP_ID)</string>\n\
	<key>CFBundleName</key><string>roadied</string>\n\
	<key>CFBundlePackageType</key><string>APPL</string>\n\
	<key>CFBundleShortVersionString</key><string>0.1.0</string>\n\
	<key>CFBundleVersion</key><string>1</string>\n\
	<key>LSUIElement</key><true/>\n\
	<key>LSMinimumSystemVersion</key><string>14.0</string>\n\
</dict>\n\
</plist>\n' > $(APP_NAME)/Contents/Info.plist
	codesign --force --deep --sign - --identifier "$(APP_ID)" $(APP_NAME)

# Install bundle .app dans ~/Applications + symlink CLI
install-app: app-bundle
	rm -rf $(APPDIR)/$(APP_NAME)
	mkdir -p $(APPDIR)
	cp -R $(APP_NAME) $(APPDIR)/$(APP_NAME)
	mkdir -p $(PREFIX)/bin
	install -m 755 .build/release/roadie $(PREFIX)/bin/roadie
	ln -sf $(APPDIR)/$(APP_NAME)/Contents/MacOS/roadied $(PREFIX)/bin/roadied
	@echo ""
	@echo "✅ Installation OK"
	@echo "   Bundle  : $(APPDIR)/$(APP_NAME)"
	@echo "   CLI     : $(PREFIX)/bin/roadie"
	@echo "   Symlink : $(PREFIX)/bin/roadied -> bundle/Contents/MacOS/roadied"
	@echo ""
	@echo "Étape suivante manuelle :"
	@echo "  Réglages Système > Confidentialité et sécurité > Accessibilité"
	@echo "  + ajouter $(APPDIR)/$(APP_NAME) et activer l'interrupteur"
	@echo ""
	@echo "Puis : roadied --daemon"

# === SPEC-004 famille SIP-off opt-in ============================

# Build osax bundle Objective-C++
build-fx: build
	bash osax/build.sh

# Install osax + dylibs (sudo requis pour /Library/ScriptingAdditions/)
install-fx: build-fx
	bash scripts/install-fx.sh

# Uninstall osax + dylibs (laisse le daemon vanilla)
uninstall-fx:
	bash scripts/uninstall-fx.sh

# Gate sécurité SC-007 : vérifier qu'aucun symbole CGS d'écriture
# n'est linké statiquement au daemon. Doit retourner 0.
verify-no-cgs-write: build
	@count=$$(nm .build/release/roadied 2>/dev/null | grep -E 'CGSSetWindowAlpha|CGSSetWindowShadow|CGSSetWindowBlur|CGSSetWindowTransform|CGSAddWindowsToSpaces|CGSSetStickyWindow' | wc -l | tr -d ' '); \
	if [ "$$count" -eq 0 ]; then \
		echo "✓ SC-007 PASS : 0 symbole CGS d'écriture linké au daemon"; \
	else \
		echo "✗ SC-007 FAIL : $$count symboles CGS d'écriture détectés"; \
		nm .build/release/roadied | grep -E 'CGSSetWindowAlpha|CGSSetWindowShadow|CGSSetWindowBlur|CGSSetWindowTransform|CGSAddWindowsToSpaces|CGSSetStickyWindow'; \
		exit 1; \
	fi

# === SPEC-014 stage-rail (binaire UI séparé, opt-in) =============

# Build le binaire roadie-rail (release)
build-rail:
	export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin"; \
	swift build --configuration release --product roadie-rail
	@echo "✓ build : .build/release/roadie-rail"

# Install roadie-rail dans ~/.local/bin
install-rail: build-rail
	mkdir -p $(PREFIX)/bin
	install -m 755 .build/release/roadie-rail $(PREFIX)/bin/roadie-rail
	@echo "✓ installé : $(PREFIX)/bin/roadie-rail"
	@echo ""
	@echo "Lancer : roadie-rail &"
	@echo "Toggle : roadie rail toggle"
	@echo "Status : roadie rail status"

# Uninstall roadie-rail
uninstall-rail:
	rm -f $(PREFIX)/bin/roadie-rail
	rm -f $$HOME/.roadies/rail.pid
	@echo "✓ roadie-rail désinstallé. Daemon roadied non affecté."

# === Tout-en-un : daemon + CLI + rail + bundle .app =========
# Cible recommandée pour un setup utilisateur fraîche.
install-all: install install-rail install-app
	@echo ""
	@echo "================================================================"
	@echo "✅ Installation complète OK"
	@echo "================================================================"
	@echo ""
	@echo "Composants installés :"
	@echo "   • daemon    : $(APPDIR)/$(APP_NAME) (bundle .app pour TCC)"
	@echo "   • CLI       : $(PREFIX)/bin/roadie"
	@echo "   • daemon ln : $(PREFIX)/bin/roadied"
	@echo "   • rail UI   : $(PREFIX)/bin/roadie-rail"
	@echo ""
	@echo "Étapes manuelles restantes :"
	@echo "   1. Réglages Système > Confidentialité > Accessibilité"
	@echo "      → cocher $(APPDIR)/$(APP_NAME)"
	@echo "   2. (Recommandé) Réglages Système > Confidentialité > Enregistrement d'écran"
	@echo "      → cocher $(APPDIR)/$(APP_NAME) (sinon vignettes en fallback)"
	@echo "   3. Lancer le daemon :"
	@echo "        roadied --daemon &"
	@echo "   4. Lancer le rail :"
	@echo "        roadie rail toggle"
	@echo "   5. Survoler le bord gauche de l'écran"
	@echo ""

# Désinstallation complète : retire tout, restaure une machine vierge.
uninstall-all: uninstall-rail
	@echo "Désinstallation complète..."
	-rm -f $(PREFIX)/bin/roadie
	-rm -f $(PREFIX)/bin/roadied
	-rm -rf $(APPDIR)/$(APP_NAME)
	@echo "✓ roadies entièrement désinstallé."
	@echo "Note : config $$HOME/.config/roadies/ et state $$HOME/.roadies/ préservés."
