SHELL := /bin/zsh
APP_PACKAGE_PATH := apps/macos
APP_TARGET := OpenStaffApp
CAPTURE_TARGET := OpenStaffCaptureCLI
ARGS ?=

.PHONY: build dev capture

build:
	swift build --package-path $(APP_PACKAGE_PATH)

dev:
	swift run --package-path $(APP_PACKAGE_PATH) $(APP_TARGET)

capture:
	swift run --package-path $(APP_PACKAGE_PATH) $(CAPTURE_TARGET) $(ARGS)
