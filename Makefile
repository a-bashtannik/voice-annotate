.PHONY: app install run test clean release

app:
	./scripts/build-app.sh

install: app
	rm -rf ~/Applications/voice-annotate.app
	mkdir -p ~/Applications
	cp -R build/voice-annotate.app ~/Applications/
	@echo "Installed to ~/Applications/voice-annotate.app"

run: install
	open ~/Applications/voice-annotate.app

test:
	swift test

# Download build for GitHub Releases. Signed ad-hoc: without a Developer ID it can't be
# notarized anyway, and a personal development certificate shouldn't ship in public binaries.
VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
release:
	SIGN_IDENTITY=- ./scripts/build-app.sh
	rm -f build/voice-annotate-$(VERSION).zip
	ditto -c -k --keepParent build/voice-annotate.app build/voice-annotate-$(VERSION).zip
	shasum -a 256 build/voice-annotate-$(VERSION).zip

clean:
	rm -rf .build build
