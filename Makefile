# HomeBudget — everything you need to build, test, run and ship the app.
# Run `make` on its own for the list.

# --- Environment -------------------------------------------------------------
#
# Builds keep their scratch directory on local disk. The repository lives on an SMB share where
# SwiftPM's index writes fail on rename and dependency checkouts crawl.
SCRATCH := $(HOME)/Library/Caches/homebudget-swift
SWIFT_FLAGS := --disable-index-store

# XCTest and Swift Testing ship with Xcode but not with the Command Line Tools, so point at Xcode
# here rather than requiring a `sudo xcode-select --switch`.
XCODE_DIR := /Applications/Xcode.app/Contents/Developer
ifneq ($(wildcard $(XCODE_DIR)),)
export DEVELOPER_DIR := $(XCODE_DIR)
endif

# WebAssembly needs the swift.org toolchain instead: Apple's clang has no Wasm backend, so
# JavaScriptKit's C target cannot compile under Xcode's.
SWIFTLY_ENV := $(HOME)/.swiftly/env.sh
WASM_SDK := swift-6.3.3-RELEASE_wasm

IMAGE ?= homebudget-swift
TAG ?= latest
REGISTRY ?= ghcr.io/zzzaspany

# The Podman host, which is x86_64 — the architecture the server actually runs. A Mac builds
# arm64, so anything destined for deployment is built there or by CI, never locally.
BUILD_HOST ?= user@build-host
BUILD_DIR ?= ~/build/homebudget-swift

# Apple's container runs OCI images natively on Apple silicon; override for Docker or Podman.
CONTAINER ?= container

# Loads .env for targets that need database credentials.
define with_env
set -a; [ -f .env ] && . ./.env; set +a;
endef

.DEFAULT_GOAL := help
.PHONY: help build core server web test test-core test-server run migrate revert \
        image image-run image-push image-remote image-remote-push shell db-psql db-backup db-reset lint clean clean-all doctor

# --- Help --------------------------------------------------------------------

help: ## Show this list
	@echo "HomeBudget — available targets"
	@echo
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'
	@echo
	@echo "Override defaults like: make image TAG=v1.0.0 CONTAINER=podman"

# --- Building ----------------------------------------------------------------

build: core server web ## Build all three packages

core: ## Build the domain core
	cd Packages/HomeBudgetCore && swift build $(SWIFT_FLAGS) --scratch-path $(SCRATCH)/core

server: ## Build the Vapor server
	cd Packages/Server && swift build $(SWIFT_FLAGS) --scratch-path $(SCRATCH)/server

web: ## Compile the client to WebAssembly, into the server's public directory
	cd Packages/WebClient && . $(SWIFTLY_ENV) && unset DEVELOPER_DIR && \
		swift package --swift-sdk $(WASM_SDK) --scratch-path $(SCRATCH)/web \
		--allow-writing-to-package-directory js -c release \
		--output ../Server/Public/app

# --- Testing -----------------------------------------------------------------

test: test-core test-server ## Run every test suite

test-core: ## Test the domain logic
	cd Packages/HomeBudgetCore && swift test $(SWIFT_FLAGS) --scratch-path $(SCRATCH)/core

test-server: ## Test the API, reports and PDF writer
	cd Packages/Server && swift test $(SWIFT_FLAGS) --scratch-path $(SCRATCH)/server

# --- Running locally ---------------------------------------------------------

run: ## Serve on http://localhost:8000, reading .env
	@$(with_env) cd Packages/Server && \
		swift run $(SWIFT_FLAGS) --scratch-path $(SCRATCH)/server App serve \
		--hostname 127.0.0.1 --port $${PORT:-8000}

migrate: ## Apply pending database migrations
	@$(with_env) cd Packages/Server && \
		swift run $(SWIFT_FLAGS) --scratch-path $(SCRATCH)/server App migrate --yes

revert: ## Roll back the last migration
	@$(with_env) cd Packages/Server && \
		swift run $(SWIFT_FLAGS) --scratch-path $(SCRATCH)/server App migrate --revert --yes

# --- Container ---------------------------------------------------------------

image: ## Build the container image
	$(CONTAINER) build --file Containerfile --tag $(IMAGE):$(TAG) .

image-run: ## Run the built image on port 8000, reading .env
	@$(with_env) $(CONTAINER) run --rm --name homebudget \
		--publish 8000:8000 \
		--env DATABASE_URL="$$DATABASE_URL" \
		--env DEV_MODE="$${DEV_MODE:-false}" \
		--env SMTP_HOST="$$SMTP_HOST" \
		--env SMTP_PORT="$$SMTP_PORT" \
		--env SMTP_FROM="$$SMTP_FROM" \
		--env NOTIFICATION_EMAIL_TO="$$NOTIFICATION_EMAIL_TO" \
		$(IMAGE):$(TAG)

image-push: image ## Push the image to the registry
	$(CONTAINER) tag $(IMAGE):$(TAG) $(REGISTRY)/$(IMAGE):$(TAG)
	$(CONTAINER) push $(REGISTRY)/$(IMAGE):$(TAG)

image-remote: ## Build the x86_64 image on the Podman host, natively
	@echo "Syncing to $(BUILD_HOST)"
	@rsync -az --delete \
		--exclude='.git' --exclude='.build' --exclude='backups' \
		--exclude='Packages/Server/Public/app' --exclude='.env' \
		./ $(BUILD_HOST):$(BUILD_DIR)/
	@ssh $(BUILD_HOST) 'cd $(BUILD_DIR) && podman build --file Containerfile --tag $(REGISTRY)/$(IMAGE):$(TAG) .'

image-remote-push: image-remote ## Build on the Podman host and push to the registry
	@ssh $(BUILD_HOST) 'podman push $(REGISTRY)/$(IMAGE):$(TAG)'

shell: ## Open a shell inside the image, to inspect what shipped
	$(CONTAINER) run --rm --interactive --tty --entrypoint /bin/bash $(IMAGE):$(TAG)

# --- Database ----------------------------------------------------------------
#
# These run the client out of the Postgres image rather than expecting psql on the machine, so they
# work wherever the container runtime does and always match the server's major version.
PSQL_IMAGE := docker.io/library/postgres:17-alpine

db-psql: ## Open psql against the configured database
	@$(with_env) $(CONTAINER) run --rm --interactive --tty $(PSQL_IMAGE) psql "$$DATABASE_URL"

db-backup: ## Dump the database to backups/ with a timestamp
	@$(with_env) mkdir -p backups && stamp=$$(date +%Y%m%d-%H%M%S) && \
		$(CONTAINER) run --rm $(PSQL_IMAGE) pg_dump "$$DATABASE_URL" > backups/homebudget-$$stamp.sql && \
		echo "Wrote backups/homebudget-$$stamp.sql ($$(wc -c < backups/homebudget-$$stamp.sql) bytes)"

db-reset: ## Delete every expense and payment. Asks first.
	@$(with_env) printf 'Delete all expenses and payments? [y/N] ' && read answer && \
		[ "$$answer" = "y" ] && \
		$(CONTAINER) run --rm $(PSQL_IMAGE) psql "$$DATABASE_URL" \
			-c 'TRUNCATE payments, expenses CASCADE;' && \
		echo "Cleared." || echo "Left alone."


# --- Housekeeping ------------------------------------------------------------

lint: ## Format every Swift source in place
	@command -v swift-format >/dev/null 2>&1 \
		&& swift-format format --in-place --recursive Packages/*/Sources Packages/*/Tests \
		&& echo "Formatted." \
		|| echo "swift-format not installed: brew install swift-format"

clean: ## Remove build products
	rm -rf $(SCRATCH)
	rm -rf Packages/Server/Public/app

clean-all: clean ## Also remove the built image
	-$(CONTAINER) rmi $(IMAGE):$(TAG)

doctor: ## Check that the toolchains and services this project needs are present
	@echo "Xcode toolchain (tests)"
	@[ -d "$(XCODE_DIR)" ] && echo "  ok    $(XCODE_DIR)" || echo "  MISSING — install Xcode"
	@echo "swift.org toolchain (WebAssembly)"
	@[ -f "$(SWIFTLY_ENV)" ] && echo "  ok    $(SWIFTLY_ENV)" || echo "  MISSING — https://swift.org/install"
	@echo "WebAssembly SDK"
	@. $(SWIFTLY_ENV) 2>/dev/null && swift sdk list 2>/dev/null | grep -q $(WASM_SDK) \
		&& echo "  ok    $(WASM_SDK)" || echo "  MISSING — see docs/deployment.md"
	@echo "Container runtime"
	@command -v $(CONTAINER) >/dev/null 2>&1 \
		&& echo "  ok    $$($(CONTAINER) --version 2>&1 | head -1)" \
		|| echo "  MISSING — brew install container"
	@echo "Database"
	@$(with_env) [ -n "$$DATABASE_URL" ] \
		&& echo "  ok    $$(echo $$DATABASE_URL | sed 's|://[^@]*@|://***@|')" \
		|| echo "  MISSING — copy .env.example to .env"
