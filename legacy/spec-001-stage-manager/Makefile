CC      = swiftc
FLAGS   = -O -whole-module-optimization
BIN     = stage
APP     = $(BIN).app
APP_ID  = local.suckless.stage
PREFIX ?= $(HOME)/.local
APPDIR ?= $(HOME)/Applications

$(BIN): stage.swift
	$(CC) $(FLAGS) -target x86_64-apple-macos11 -o $(BIN).x86_64 stage.swift
	$(CC) $(FLAGS) -target arm64-apple-macos11   -o $(BIN).arm64  stage.swift
	lipo -create -output $(BIN) $(BIN).x86_64 $(BIN).arm64
	rm $(BIN).x86_64 $(BIN).arm64
	# Re-signature ad-hoc avec identifier stable (TCC refuse linker-signed sur Sequoia+).
	codesign --force --sign - --identifier "$(BIN)" $(BIN)

# Bundle .app : indispensable sur macOS Sequoia/Tahoe pour que TCC accepte
# d'ajouter le binaire a Accessibility (les binaires CLI bruts sont rejetes
# silencieusement par le panneau Reglages Systeme).
$(APP): $(BIN)
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(BIN) $(APP)/Contents/MacOS/$(BIN)
	printf '<?xml version="1.0" encoding="UTF-8"?>\n\
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n\
<plist version="1.0">\n\
<dict>\n\
	<key>CFBundleExecutable</key><string>$(BIN)</string>\n\
	<key>CFBundleIdentifier</key><string>$(APP_ID)</string>\n\
	<key>CFBundleName</key><string>$(BIN)</string>\n\
	<key>CFBundlePackageType</key><string>APPL</string>\n\
	<key>CFBundleShortVersionString</key><string>1.0</string>\n\
	<key>CFBundleVersion</key><string>1</string>\n\
	<key>LSUIElement</key><true/>\n\
	<key>LSMinimumSystemVersion</key><string>11.0</string>\n\
</dict>\n\
</plist>\n' > $(APP)/Contents/Info.plist
	codesign --force --deep --sign - --identifier "$(APP_ID)" $(APP)

install: $(BIN)
	install -m 755 $(BIN) $(PREFIX)/bin/$(BIN)

# Installe le bundle dans ~/Applications et met a jour le symlink CLI.
install-app: $(APP)
	rm -rf $(APPDIR)/$(APP)
	mkdir -p $(APPDIR)
	cp -R $(APP) $(APPDIR)/$(APP)
	mkdir -p $(PREFIX)/bin
	ln -sf $(APPDIR)/$(APP)/Contents/MacOS/$(BIN) $(PREFIX)/bin/$(BIN)
	@echo ""
	@echo "Bundle installe : $(APPDIR)/$(APP)"
	@echo "Symlink CLI     : $(PREFIX)/bin/$(BIN) -> $(APPDIR)/$(APP)/Contents/MacOS/$(BIN)"
	@echo ""
	@echo "Etape suivante manuelle :"
	@echo "  Reglages Systeme > Confidentialite et securite > Accessibilite"
	@echo "  Cliquer + et ajouter : $(APPDIR)/$(APP)"

clean:
	rm -rf $(BIN) $(APP)

test: $(BIN)
	@for t in tests/*.sh; do \
		[ "$$(basename $$t)" = "01-permission.sh" ] && continue ; \
		bash "$$t" || exit 1 ; \
	done

.PHONY: install install-app clean test
