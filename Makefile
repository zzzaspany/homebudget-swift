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

# The WebAssembly build needs the swift.org toolchain: Apple's clang has no Wasm backend, so
# JavaScriptKit's C target cannot compile under Xcode's.
SWIFTLY_ENV := $(HOME)/.swiftly/env.sh
WASM_SDK := swift-6.3.3-RELEASE_wasm

.PHONY: build test run core server web clean

build: core server web

core:
	cd Packages/HomeBudgetCore && swift build $(SWIFT_FLAGS) --scratch-path $(SCRATCH)/core

server:
	cd Packages/Server && swift build $(SWIFT_FLAGS) --scratch-path $(SCRATCH)/server

# Compiles the client to WebAssembly and writes the bundle into the server's public directory.
web:
	cd Packages/WebClient && . $(SWIFTLY_ENV) && unset DEVELOPER_DIR && \
		swift package --swift-sdk $(WASM_SDK) --scratch-path $(SCRATCH)/web \
		--allow-writing-to-package-directory js -c release --use-cdn \
		--output ../Server/Public/app

test:
	cd Packages/HomeBudgetCore && swift test $(SWIFT_FLAGS) --scratch-path $(SCRATCH)/core
	cd Packages/Server && swift test $(SWIFT_FLAGS) --scratch-path $(SCRATCH)/server

run:
	cd Packages/Server && swift run $(SWIFT_FLAGS) --scratch-path $(SCRATCH)/server App serve

clean:
	rm -rf $(SCRATCH)
