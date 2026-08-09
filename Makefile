# Makefile for batch-ocr
# Swift CLI that batch-OCRs images using the Apple Vision framework.

# Configuration variables
SWIFT ?= swift
CONFIGURATION ?= debug
BUILD_DIR ?= .build
PREFIX ?= /usr/local

# Project variables
PROJECT_NAME := batch-ocr
BINARY := $(BUILD_DIR)/$(CONFIGURATION)/$(PROJECT_NAME)

# Phony targets
.PHONY: all build release test test-tsan clean install run help

# Default target
all: build

# Build the project
build:
	$(SWIFT) build --configuration $(CONFIGURATION)

# Build the optimized release binary
release:
	$(SWIFT) build --configuration release

# Run the test suite
test:
	$(SWIFT) test

# Run the test suite with the thread sanitizer
test-tsan:
	$(SWIFT) test --sanitize=thread

# Clean build artifacts
clean:
	rm -rf $(BUILD_DIR)

# Install the release binary
install: release
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 755 $(BUILD_DIR)/release/$(PROJECT_NAME) $(DESTDIR)$(PREFIX)/bin/$(PROJECT_NAME)

# Run the CLI (pass arguments via ARGS, e.g. make run ARGS="--help")
run: build
	$(BINARY) $(ARGS)

# Show help
help:
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  all       Build the project (default, debug configuration)"
	@echo "  build     Build with CONFIGURATION (debug|release)"
	@echo "  release   Build the optimized release binary"
	@echo "  test      Run the test suite"
	@echo "  test-tsan Run the test suite with the thread sanitizer"
	@echo "  clean     Remove build artifacts"
	@echo "  install   Install the release binary to $(PREFIX)/bin"
	@echo "  run       Run the CLI (ARGS=\"...\" to pass arguments)"
	@echo "  help      Show this help"
