# Gradle 8.14 needs JDK 17–24; this machine's default is newer. Override with
# `make JAVA_HOME=... install-android` if nix isn't around.
JAVA_HOME ?= $(shell nix build --no-link --print-out-paths nixpkgs#jdk17 2>/dev/null)/lib/openjdk
export JAVA_HOME

APK_DIR := build/app/outputs/flutter-apk

.PHONY: apk install-android test

# Release APKs, one per ABI.
apk:
	flutter build apk --release --split-per-abi

# Build, then install the APK matching the connected phone's ABI (over adb).
install-android: apk
	@abi=$$(adb shell getprop ro.product.cpu.abi | tr -d '\r'); \
	test -n "$$abi" || { echo "No device: plug the phone in with USB debugging on (adb devices)"; exit 1; }; \
	echo "Installing for $$abi"; \
	adb install -r $(APK_DIR)/app-$$abi-release.apk

test:
	flutter analyze
	flutter test
