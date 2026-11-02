.PHONY: app install run test clean

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

clean:
	rm -rf .build build
