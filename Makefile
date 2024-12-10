# Define the version and output directory
VERSION = v0.1.0
DIST_DIR = dist

# Define the target platforms
PLATFORMS = windows_amd64 windows_arm64 macos_amd64 macos_arm64 linux_amd64 linux_arm64

# Docker image name and version
IMAGE_NAME = edsonmichaque/tyk-sync-foobar
IMAGE_VERSION = $(VERSION)

# Default target
all: $(PLATFORMS)

# Rule to copy the script to each platform-specific directory
$(PLATFORMS):
	mkdir -p $(DIST_DIR)
	cp foobar.sh $(DIST_DIR)/tyk-sync-foobar_$(VERSION)_$@

# Target to create a release, tag the version, and attach assets using GitHub CLI
release: all
	gh release create $(VERSION) $(DIST_DIR)/* --title "Release $(VERSION)" --notes "Automated release of version $(VERSION)"

# Target to build and publish the Docker image for multiple platforms
docker-build:
	@if ! docker buildx ls | grep -q "builder \* docker"; then \
		echo "Setting up Docker buildx..."; \
		docker buildx create --use --name builder || true; \
		docker buildx inspect --bootstrap; \
	fi
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t $(IMAGE_NAME):$(IMAGE_VERSION) \
		-t $(IMAGE_NAME):latest \
		--push .

# Target to publish the Docker image (now just an alias for docker-build)
docker-publish: docker-build

# Clean up the dist directory
clean:
	rm -rf $(DIST_DIR) 


# Target to create a release and attach assets using GitLab CLI
release-gitlab: all
	release-cli create \
		--name "Release $(VERSION)" \
		--tag-name $(VERSION) \
		--description "Automated release of version $(VERSION)" \
		--assets-links='[$(shell for file in dist/*; do \
			echo -n "{\"name\":\"$$(basename $$file)\",\"url\":\"${CI_PROJECT_URL}/-/jobs/${CI_JOB_ID}/artifacts/file/$$(basename $$file)\"},"; \
		done | sed "s/,$$//" )]'