.PHONY: build install clean test app-bundle install-app

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
