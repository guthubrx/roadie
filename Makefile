.PHONY: test build install permissions displays windows snapshot state plan apply maintain start stop restart status logs doctor self-test events config dmg package-dmg clean

test:
	./scripts/test

build:
	./scripts/with-xcode swift build

install:
	./scripts/install

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

start:
	./scripts/start

stop:
	./scripts/stop

restart: stop start

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
