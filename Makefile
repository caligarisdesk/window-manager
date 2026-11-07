# Shelf builds with plain swiftc: SwiftPM fails on some Command Line Tools installs
# ("unable to lookup item 'PlatformPath'"), and XCTest ships only with Xcode.

ARCH    := $(shell uname -m)
TARGET  := $(ARCH)-apple-macos13.0
CORE    := $(shell find Sources/Core -name '*.swift')
APP_SRC := $(shell find Sources/App -name '*.swift')
TESTS   := $(shell find Tests -name '*.swift')
BUILD   := .build

.PHONY: app run test coverage icon clean

app: ## Build Shelf.app
	./scripts/bundle.sh

run: app
	open Shelf.app

test: ## Build and run the unit tests
	@mkdir -p $(BUILD)
	swiftc -parse-as-library -target $(TARGET) $(CORE) $(TESTS) -o $(BUILD)/ShelfTests
	$(BUILD)/ShelfTests

coverage: ## Run the tests with coverage and report on Sources/Core
	@mkdir -p $(BUILD)/cov
	swiftc -parse-as-library -target $(TARGET) -profile-generate -profile-coverage-mapping \
		$(CORE) $(TESTS) -o $(BUILD)/cov/ShelfTests
	LLVM_PROFILE_FILE=$(BUILD)/cov/tests.profraw $(BUILD)/cov/ShelfTests
	xcrun llvm-profdata merge -sparse $(BUILD)/cov/tests.profraw -o $(BUILD)/cov/tests.profdata
	xcrun llvm-cov report $(BUILD)/cov/ShelfTests -instr-profile=$(BUILD)/cov/tests.profdata $(CORE)

icon: ## Regenerate Resources/AppIcon.icns
	@mkdir -p $(BUILD)
	swiftc scripts/make_icon.swift -o $(BUILD)/make_icon && $(BUILD)/make_icon

clean:
	rm -rf $(BUILD) Shelf.app
