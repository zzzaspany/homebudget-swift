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

# Where deployable images are built: a Linux host of the architecture the server runs. A Mac
# builds arm64, so anything destined for deployment is built there or by CI, never locally.
# Set BUILD_HOST in .env or on the command line — it is deliberately not committed.
BUILD_HOST ?= $(shell grep -s '^BUILD_HOST=' .env | cut -d= -f2-)
BUILD_DIR ?= ~/build/homebudget-swift

# Apple's container runs OCI images natively on Apple silicon; override for Docker or Podman.
CONTAINER ?= container

# The iOS app. Its Xcode project is generated from project.yml rather than committed, so it has to
# be built before anything can open or compile it.
IOS_DIR := Packages/HomeBudgetiOS
IOS_SIMULATOR ?= iPhone 17 Pro
IOS_BUNDLE_ID := lab.office.homebudget

# Loads .env for targets that need database credentials.
define with_env
set -a; [ -f .env ] && . ./.env; set +a;
endef

.DEFAULT_GOAL := help
.PHONY: help build core server web test test-core test-server run migrate revert \
        image image-run image-push image-remote image-remote-push shell db-psql db-backup db-reset \
        ios ios-open ios-build ios-run docs docs-open docs-html version release lint clean clean-all doctor

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

# --- iOS ---------------------------------------------------------------------
#
# SwiftPM cannot produce an app bundle — no Info.plist, signing or resources — so an Xcode project
# is still required. It is generated from project.yml so that changes read as diffs rather than as
# churn in a .pbxproj, which means regenerating after editing that file.

ios: ## Generate the Xcode project from project.yml
	cd $(IOS_DIR) && xcodegen generate

ios-open: ios ## Generate and open in Xcode
	open $(IOS_DIR)/HomeBudget.xcodeproj

ios-build: ios ## Build the app for the simulator
	cd $(IOS_DIR) && xcodebuild -project HomeBudget.xcodeproj -scheme HomeBudget \
		-destination 'platform=iOS Simulator,name=$(IOS_SIMULATOR)' \
		-derivedDataPath $(SCRATCH)/ios build

ios-run: ios-build ## Build, install and launch on the simulator
	@xcrun simctl boot "$(IOS_SIMULATOR)" 2>/dev/null || true
	@open -a Simulator
	@app=$$(find $(SCRATCH)/ios -name HomeBudget.app -path '*Debug-iphonesimulator*' | head -1); \
		xcrun simctl install "$(IOS_SIMULATOR)" "$$app" && \
		xcrun simctl launch "$(IOS_SIMULATOR)" $(IOS_BUNDLE_ID)

# --- Releasing ---------------------------------------------------------------

# VERSION is the single source of truth. The iOS project carries the same number so the app can
# say what it is, and CI checks the two agree rather than trusting anyone to remember.
VERSION := $(shell cat VERSION)

version: ## Print the current version and where it is recorded
	@echo "VERSION file:      $(VERSION)"
	@echo "iOS project.yml:   $$(grep -m1 MARKETING_VERSION $(IOS_DIR)/project.yml | sed 's/.*: *//' | tr -d '\"')"
	@echo "latest git tag:    $$(git describe --tags --abbrev=0 2>/dev/null || echo '(none)')"

# Bumps the version everywhere, then tags. Pushing the tag is left to you on purpose: it triggers
# the image build and push, which is the moment a release becomes real.
release: ## Cut a release: make release NEW=1.1.0
	@test -n "$(NEW)" || { echo "Usage: make release NEW=1.1.0"; exit 1; }
	@git diff --quiet || { echo "Working tree is dirty — commit or stash first."; exit 1; }
	@grep -q "^## \[$(NEW)\]" CHANGELOG.md || { \
		echo "CHANGELOG.md has no '## [$(NEW)]' section. Write it before tagging."; exit 1; }
	@echo "$(NEW)" > VERSION
	@sed -i '' 's/MARKETING_VERSION: ".*"/MARKETING_VERSION: "$(NEW)"/' $(IOS_DIR)/project.yml
	@git add VERSION CHANGELOG.md $(IOS_DIR)/project.yml
	@# Nothing to commit when the version was already written by hand — the first release was
	@# prepared that way. Tag the commit that is there rather than failing on an empty commit.
	@git diff --cached --quiet || git commit -q -m "Release $(NEW)"
	@git tag -a "v$(NEW)" -m "Release $(NEW)"
	@echo "Tagged v$(NEW). Push it when you mean it:"
	@echo "    git push && git push origin v$(NEW)"

# --- Documentation -----------------------------------------------------------

# DocC, Apple's own documentation compiler. Driven through xcodebuild rather than
# swift-docc-plugin so HomeBudgetCore's manifest gains no dependency — it is resolved by the
# WebAssembly build too, where a documentation plugin has no business being.
DOCS_ARCHIVE := $(SCRATCH)/docs/Build/Products/Debug/HomeBudgetCore.doccarchive

docs: ## Build the HomeBudgetCore documentation
	cd Packages/HomeBudgetCore && xcodebuild docbuild -scheme HomeBudgetCore \
		-destination 'platform=macOS' -derivedDataPath $(SCRATCH)/docs -quiet
	@echo "Built $(DOCS_ARCHIVE)"

docs-open: docs ## Build the documentation and open it in Xcode
	open $(DOCS_ARCHIVE)

# Rewritten for a plain web server: no server-side routing, and every link relative to the
# subdirectory it will be served from.
#
# Written outside the repository by default, like every other build output here — it is five
# megabytes of small files, and this checkout lives on an SMB share where that takes minutes.
# Override with DOCS_SITE=... to put it somewhere publishable.
DOCS_SITE ?= $(SCRATCH)/docs-site

docs-html: docs ## Export the documentation as a static site (DOCS_SITE=... to choose where)
	@rm -rf $(DOCS_SITE)
	xcrun docc process-archive transform-for-static-hosting $(DOCS_ARCHIVE) \
		--output-path $(DOCS_SITE) --hosting-base-path homebudget-swift/docs
	@echo "Static site in $(DOCS_SITE)"

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

image-remote: ## Build the image on a remote Linux host, natively (set BUILD_HOST)
	@test -n "$(BUILD_HOST)" || { echo "Set BUILD_HOST=user@host in .env"; exit 1; }
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
	@echo "xcodegen (iOS project)"
	@command -v xcodegen >/dev/null 2>&1 \
		&& echo "  ok    $$(xcodegen --version 2>&1 | head -1)" \
		|| echo "  MISSING — brew install xcodegen"
	@echo "Container runtime"
	@command -v $(CONTAINER) >/dev/null 2>&1 \
		&& echo "  ok    $$($(CONTAINER) --version 2>&1 | head -1)" \
		|| echo "  MISSING — brew install container"
	@echo "Database"
	@$(with_env) [ -n "$$DATABASE_URL" ] \
		&& echo "  ok    $$(echo $$DATABASE_URL | sed 's|://[^@]*@|://***@|')" \
		|| echo "  MISSING — copy .env.example to .env"
