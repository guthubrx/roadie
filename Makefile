.PHONY: test build install uninstall permissions displays windows snapshot state plan apply maintain dev-start stop restart status logs doctor self-test events config dmg package-dmg clean

test:
	./scripts/test

build:
	./scripts/with-xcode swift build

install:
	./scripts/install

uninstall:
	./scripts/uninstall

permissions:
	./scripts/roadie permissions

displays:
	./scripts/roadie display list

windows:
	./scripts/roadie windows list

snapshot:
	./scripts/roadied snapshot

state:
	./scripts/roadie state dump --json

config:
	./scripts/roadie config show

config-validate:
	./scripts/roadie config validate

package-dmg:
	./scripts/package-dmg

dmg: package-dmg

plan:
	./scripts/roadie layout plan

apply:
	./scripts/roadie layout apply --yes

maintain:
	./scripts/roadied run --yes

# Démarrage de développement : build debug, binaires dans ./bin, session tmux.
dev-start:
	./scripts/start

stop:
	./scripts/stop

# Redémarre le service installé par `make install` (binaires de ~/.local/bin). Ne lance jamais tmux.
# Un seul lanceur à la fois : le verrou d'instance du daemon refuse une 2e instance, et launchd
# (KeepAlive) la relancerait en boucle. On refuse donc si une session de développement tourne.
# Si le service est déchargé (après `make stop`), roadiedctl le recharge.
restart:
	@if command -v tmux >/dev/null 2>&1 && tmux has-session -t roadied 2>/dev/null; then \
		echo "Une session de développement (make dev-start) tourne. Lancez 'make stop' d'abord : un seul lanceur à la fois." >&2; \
		exit 1; \
	fi
	@if launchctl print gui/$$(id -u)/com.roadie.roadied >/dev/null 2>&1; then \
		for f in $$HOME/.roadies/roadied.stdout.log $$HOME/.roadies/roadied.stderr.log; do \
			if [ -s "$$f" ]; then mv -f "$$f" "$$f.1"; fi; \
		done; \
		launchctl kickstart -k gui/$$(id -u)/com.roadie.roadied; \
	else \
		./scripts/roadiedctl start; \
	fi

status:
	./scripts/status

logs:
	./scripts/logs

doctor:
	./scripts/doctor

self-test:
	./scripts/roadie self-test

events:
	./scripts/roadie events tail 30

clean:
	./scripts/with-xcode swift package clean
