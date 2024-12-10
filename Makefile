# Define the version and output directory
VERSION = v0.1.0
DIST_DIR = dist

# Define the target platforms
PLATFORMS = windows_amd64 macos_amd64 macos_arm64

# Default target
all: $(PLATFORMS)

# Rule to copy the script to each platform-specific directory
$(PLATFORMS):
	mkdir -p $(DIST_DIR)
	cp foobar.sh $(DIST_DIR)/tyk-sync-foobar_$(VERSION)_$@

# Target to create a release, tag the version, and attach assets using GitHub CLI
release: all
	git tag $(VERSION)
	git push origin $(VERSION)
	gh release create $(VERSION) $(DIST_DIR)/* --title "Release $(VERSION)" --notes "Automated release of version $(VERSION)"

# Clean up the dist directory
clean:
	rm -rf $(DIST_DIR) 