# Define the version and output directory
VERSION = v0.1.0
DIST_DIR = dist
IMAGE_NAME = edsonmichaque/tyk-sync-foobar

# Default target
all: build

# Build all platforms
build:
	@./scripts/ci.sh $(VERSION) $(DIST_DIR) $(IMAGE_NAME) build --compress

# Create GitHub release
release-github: clean
	@./scripts/ci.sh $(VERSION) $(DIST_DIR) $(IMAGE_NAME) release --github

# Create GitLab release  
release-gitlab: clean
	@./scripts/ci.sh $(VERSION) $(DIST_DIR) $(IMAGE_NAME) release --gitlab

# Build and push Docker images
docker:
	@./scripts/ci.sh $(VERSION) $(DIST_DIR) $(IMAGE_NAME) docker

# Clean up build artifacts
clean:
	@./scripts/ci.sh $(VERSION) $(DIST_DIR) $(IMAGE_NAME) clean

.PHONY: all build release-github release-gitlab docker clean