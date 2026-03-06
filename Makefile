SHELL := /bin/zsh
APP_PACKAGE_PATH := apps/macos
APP_TARGET := OpenStaffApp

.PHONY: build dev

build:
	swift build --package-path $(APP_PACKAGE_PATH)

dev:
	swift run --package-path $(APP_PACKAGE_PATH) $(APP_TARGET)
