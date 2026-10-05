PROJECT := StageChase.xcodeproj
MAC_SCHEME := StageChaseMac
PHONE_SCHEME := StageChasePhone
CONFIGURATION := Debug
DERIVED_DATA ?= build
APP_NAME := StageChasePhone
BUNDLE_ID := com.cseibert.StageChasePhone
SIM_DEVICE_NAME ?= iPhone 17 Pro
SIM_DESTINATION ?= platform=iOS Simulator,name=$(SIM_DEVICE_NAME)
GENERIC_SIM_DESTINATION := generic/platform=iOS Simulator
GENERIC_DEVICE_DESTINATION := generic/platform=iOS
DEVICE_ID ?= 00008150-000E41422E40401C
DEVELOPMENT_TEAM ?= 96NAC4VTEN
PHONE_DEVELOPMENT_TEAM ?= $(DEVELOPMENT_TEAM)

.PHONY: setup format lint test runner-test sync-test codex-check build run clean sim-build sim-launch phone-verify phone-build phone-install phone-launch phone-deploy

runner-test:
	mkdir -p build/verification
	chmod +x Tests/Integration/fake-codex.py
	xcrun swiftc -swift-version 6 -module-cache-path build/verification/module-cache -parse-as-library Sources/StageChaseCore/*.swift Sources/StageChaseUI/*.swift Apps/StageChaseMac/CodexConnection.swift Apps/StageChaseMac/CodexRunner.swift Apps/StageChaseMac/GitService.swift Apps/StageChaseMac/MakeTargetService.swift Apps/StageChaseMac/MCPServer.swift Apps/StageChaseMac/SyncServer.swift Tests/Integration/RunnerSmoke.swift -o build/verification/runner-smoke
	build/verification/runner-smoke "$(CURDIR)/Tests/Integration/fake-codex.py"

codex-check:
	mkdir -p build/verification
	xcrun swiftc -swift-version 6 -parse-as-library Sources/StageChaseCore/Domain.swift Apps/StageChaseMac/CodexConnection.swift scripts/VerifyCodex.swift -o build/verification/codex-check
	build/verification/codex-check

setup:
	swift package resolve

format:
	xcrun swift-format format --recursive --in-place Sources Apps Tests

lint:
	swift package dump-package >/dev/null
	xcrun swift-format lint --recursive --strict Sources Apps Tests
	@echo "Package manifest is valid."

test:
	swift test

sync-test:
	swift test --filter 'syncMessagesAreAuthenticatedEncryptedAndBounded|syncSnapshotPreservesSharedStateButOmitsMacOnlyConfiguration|remoteCommandsAreTransactionalRevisionCheckedAndIdempotent|newerPhoneTaskEditWinsAndEqualTimestampMacEditWinsDeterministically|forcedSnapshotRequestSurvivesWireEncoding|syncFramesAreLengthBoundedAndRejectMalformedMessages|remoteCommandReceiptSurvivesRepositoryRestart|syncNetworkJournalPersistsOnlyBoundedExchangeMetadata'

build:
	xcodebuild -project $(PROJECT) -scheme $(MAC_SCHEME) -configuration $(CONFIGURATION) -destination 'platform=macOS' -derivedDataPath $(DERIVED_DATA) CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) CODE_SIGN_IDENTITY='Apple Development' build

run: build
	open "$(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/StageChaseMac.app"

clean:
	xcodebuild -project $(PROJECT) -scheme $(MAC_SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) clean
	swift package clean

sim-build:
	xcodebuild -project $(PROJECT) -scheme $(PHONE_SCHEME) -configuration $(CONFIGURATION) -destination '$(GENERIC_SIM_DESTINATION)' -derivedDataPath $(DERIVED_DATA) CODE_SIGNING_ALLOWED=NO build

sim-launch: sim-build
	@set -eu; \
	UDID=$$(xcrun simctl list devices available | awk -F '[()]' -v name="$(SIM_DEVICE_NAME)" '{ display=$$1; sub(/^[[:space:]]+/, "", display); sub(/[[:space:]]+$$/, "", display); if (display == name && $$0 !~ /unavailable/) { print $$2; exit } }'); \
	if [ -z "$$UDID" ]; then echo "No available simulator named $(SIM_DEVICE_NAME)."; xcrun simctl list devices available; exit 1; fi; \
	xcrun simctl boot "$$UDID" >/dev/null 2>&1 || true; \
	xcrun simctl bootstatus "$$UDID" -b; \
	SIM_APP="$$(xcode-select -p)/Applications/Simulator.app"; \
	if [ ! -d "$$SIM_APP" ]; then SIM_APP="$$(xcode-select -p)/../Applications/Simulator.app"; fi; \
	if [ ! -d "$$SIM_APP" ]; then SIM_APP="$$(xcode-select -p)/../Applications/DeviceHub.app"; fi; \
	open "$$SIM_APP" --args -CurrentDeviceUDID "$$UDID"; \
	xcrun simctl install "$$UDID" "$(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/$(APP_NAME).app"; \
	xcrun simctl launch "$$UDID" $(BUNDLE_ID)

phone-verify:
	xcodebuild -project $(PROJECT) -scheme $(PHONE_SCHEME) -showdestinations
	xcrun devicectl list devices

phone-build:
	xcodebuild -project $(PROJECT) -scheme $(PHONE_SCHEME) -configuration $(CONFIGURATION) -destination '$(GENERIC_DEVICE_DESTINATION)' -derivedDataPath $(DERIVED_DATA) CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(PHONE_DEVELOPMENT_TEAM) -allowProvisioningUpdates -allowProvisioningDeviceRegistration build

phone-install:
	xcrun devicectl device install app --device $(DEVICE_ID) "$(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphoneos/$(APP_NAME).app"

phone-launch:
	xcrun devicectl device process launch --device $(DEVICE_ID) --terminate-existing $(BUNDLE_ID)

phone-deploy: phone-build
	$(MAKE) phone-install
	$(MAKE) phone-launch
