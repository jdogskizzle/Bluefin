PROJECT = Bluefin.xcodeproj
SCHEME = Bluefin
DESTINATION = platform=iOS Simulator,name=iPhone 17 Pro
BUNDLE_ID = com.jdogskizzle.Bluefin
BUILD_DIR = build

.PHONY: build deploy test clean

build:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(BUILD_DIR) \
		build

deploy:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(BUILD_DIR) \
		build
	xcrun simctl install booted \
		$(BUILD_DIR)/Build/Products/Debug-iphonesimulator/Bluefin.app
	xcrun simctl launch booted $(BUNDLE_ID)

deploy-device:
	@DEVICE_ID=$$(xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-showdestinations 2>/dev/null | \
		grep 'platform:iOS, arch:arm64, id:' | \
		grep -v 'placeholder' | \
		head -1 | \
		sed -E 's/.*id:([^,}]+).*/\1/'); \
	if [ -z "$$DEVICE_ID" ]; then \
		echo "No connected iOS device found."; \
		echo "Make sure your iPhone is connected, unlocked, and trusted."; \
		exit 1; \
	fi; \
	echo "Deploying to device: $$DEVICE_ID"; \
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-destination "platform=iOS,id=$$DEVICE_ID" \
		-derivedDataPath $(BUILD_DIR) \
		build && \
	xcrun devicectl device install app \
		--device "$$DEVICE_ID" \
		$(BUILD_DIR)/Build/Products/Debug-iphoneos/Bluefin.app && \
	xcrun devicectl device process launch \
		--device "$$DEVICE_ID" \
		$(BUNDLE_ID)

test:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		test

clean:
	xcodebuild \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		clean