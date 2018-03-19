.PHONY: all clean help build build-% push push-% check-current
.DEFAULT_GOAL := help

variants := 9.5 9.5-alpine 9.6 9.6-alpine 10 10-alpine

all: push

build/docker-entrypoint.sh: upstream-docker-entrypoint.sh docker-entrypoint.patch
	mkdir -p build
	patch -i docker-entrypoint.patch upstream-docker-entrypoint.sh -o build/docker-entrypoint.sh

build/docker-entrypoint-current.sh:
	mkdir -p build
	curl 'https://raw.githubusercontent.com/docker-library/postgres/master/docker-entrypoint.sh' > build/docker-entrypoint-current.sh

check-current: build/docker-entrypoint-current.sh upstream-docker-entrypoint.sh ## Compare docker-entrypoint.sh to current upstream master
	diff -u upstream-docker-entrypoint.sh build/docker-entrypoint-current.sh

clean: ## Start fresh - re-check docker-entrypoint.sh & rebuild docker directories
	rm -rf build

build: $(addprefix build-,$(variants)) ## Build all supported variants (use build-VARIANT) to build only a specific variant
	@echo Building $*

build-%: check-current Dockerfile setup-replication.sh docker-entrypoint-patcher.sh build/docker-entrypoint.sh ## Build a specific variant
	mkdir -p build/$*
	cp Dockerfile setup-replication.sh docker-entrypoint-patcher.sh build/docker-entrypoint.sh build/$*
	sed -i '' 's/postgres:latest/postgres:$*/' build/$*/Dockerfile
	docker build --no-cache --pull -t danieldent/docker-postgres-replication-dev:$* build/$*

push-%: build-%
	docker push danieldent/docker-postgres-replication-dev:$*

push: $(addprefix push-,$(variants)) ## Push current builds to docker registry (use push-VARIANT to push only one of the builds)

help: ## To build a specific variant, use the variant as the first parameter to make
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

