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