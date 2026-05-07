.PHONY: test build permissions displays windows snapshot state plan apply maintain start stop restart status logs doctor self-test config clean

test:
	./scripts/test

build:
	./scripts/with-xcode swift build

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

clean:
	./scripts/with-xcode swift package clean
