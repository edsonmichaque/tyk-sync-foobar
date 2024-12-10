#!/usr/bin/env bash

# Exit on error, undefined variables, and prevent pipe errors
set -euo pipefail
IFS=$'\n\t'

# Script constants and defaults
readonly DEFAULT_VERSION="v0.1.0"
readonly DEFAULT_DIST_DIR="dist"
readonly DEFAULT_IMAGE_NAME="edsonmichaque/tyk-sync-foobar"

readonly VERSION=${1:-"${DEFAULT_VERSION}"}
readonly DIST_DIR=${2:-"${DEFAULT_DIST_DIR}"}
readonly IMAGE_NAME=${3:-"${DEFAULT_IMAGE_NAME}"}
readonly IMAGE_VERSION=${VERSION}

# Supported platforms
readonly PLATFORMS=(
    "windows_amd64"
    "windows_arm64"
    "macos_amd64"
    "macos_arm64"
    "linux_amd64"
    "linux_arm64"
)

# Colors for logging
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions with timestamps
log_info() { echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${GREEN}[INFO]${NC} $*" >&2; }
log_warn() { echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${RED}[ERROR]${NC} $*" >&2; }
log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${BLUE}[DEBUG]${NC} $*" >&2; }

# Error handler with more context
trap 'log_error "An error occurred in ${BASH_SOURCE[0]} on line $LINENO. Command: ${BASH_COMMAND}. Exit code: $?"' ERR

# Validate required tools with version checks
check_requirements() {
    local required_tools=(
        "docker:20.10.0"
        "gh:2.0.0"
    )
    
    for tool_spec in "${required_tools[@]}"; do
        local tool="${tool_spec%%:*}"
        local min_version="${tool_spec#*:}"
        
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error "Required tool not found: $tool"
            exit 1
        fi

        local current_version
        case "$tool" in
            docker) current_version=$(docker version --format '{{.Client.Version}}' 2>/dev/null) ;;
            gh) current_version=$(gh --version | head -n1 | cut -d' ' -f3) ;;
            *) current_version="0.0.0" ;;
        esac

        if ! verify_version "$current_version" "$min_version"; then
            log_warn "$tool version $current_version is lower than recommended version $min_version"
        fi
    done
}

# Version comparison helper
verify_version() {
    local current="$1"
    local required="$2"
    
    if [[ "$(printf '%s\n' "$required" "$current" | sort -V | head -n1)" == "$required" ]]; then
        return 0
    else
        return 1
    fi
}

# Validate environment variables for GitLab releases
validate_gitlab_env() {
    local required_vars=(
        "CI_PROJECT_URL"
        "CI_JOB_ID"
        "CI_COMMIT_SHA"
        "CI_PIPELINE_ID"
    )
    
    local missing_vars=()
    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        fi
    done

    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Required GitLab CI variables not set: ${missing_vars[*]}"
        exit 1
    fi
}

# Function to build for different platforms with checksums
build_platforms() {
    log_info "Building for platforms: ${PLATFORMS[*]}"
    
    if [[ ! -f "foobar.sh" ]]; then
        log_error "Source file foobar.sh not found"
        exit 1
    fi

    mkdir -p "${DIST_DIR}"
    
    # Create checksums file
    local checksums_file="${DIST_DIR}/checksums.txt"
    : > "${checksums_file}"
    
    for platform in "${PLATFORMS[@]}"; do
        log_info "Processing platform: $platform"
        local output_file="${DIST_DIR}/tyk-sync-foobar_${VERSION}_${platform}"
        
        cp foobar.sh "${output_file}"
        chmod +x "${output_file}"
        
        # Generate checksum
        (cd "${DIST_DIR}" && sha256sum "$(basename "${output_file}")" >> "${checksums_file}")
        
        log_debug "Generated artifact: ${output_file}"
    done
    
    log_info "Build completed successfully"
    log_info "Generated checksums file: ${checksums_file}"
}

# Function to handle GitHub releases with retries
do_github_release() {
    log_info "Creating GitHub release for version ${VERSION}"
    
    if ! gh auth status >/dev/null 2>&1; then
        log_error "GitHub CLI not authenticated. Please run 'gh auth login' first"
        exit 1
    fi

    if [[ ! -d "${DIST_DIR}" ]]; then
        log_error "Distribution directory not found: ${DIST_DIR}"
        exit 1
    fi

    local max_retries=3
    local retry_count=0
    local success=false

    while [[ $retry_count -lt $max_retries && $success == false ]]; do
        if gh release create "${VERSION}" "${DIST_DIR}"/* \
            --title "Release ${VERSION}" \
            --notes "Automated release of version ${VERSION}" \
            --generate-notes; then
            success=true
            log_info "GitHub release created successfully"
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                log_warn "Failed to create GitHub release, retrying in 5 seconds... (Attempt $retry_count of $max_retries)"
                sleep 5
            else
                log_error "Failed to create GitHub release after $max_retries attempts"
                exit 1
            fi
        fi
    done
}

# Function to handle GitLab releases with improved asset handling
do_gitlab_release() {
    log_info "Creating GitLab release for version ${VERSION}"
    
    validate_gitlab_env

    if [[ ! -d "${DIST_DIR}" ]]; then
        log_error "Distribution directory not found: ${DIST_DIR}"
        exit 1
    fi

    # Create asset links JSON with improved formatting
    local assets_json
    assets_json=$(generate_assets_json)

    if ! release-cli create \
        --name "Release ${VERSION}" \
        --tag-name "${VERSION}" \
        --description "Automated release of version ${VERSION}" \
        --ref "${CI_COMMIT_SHA}" \
        --assets-links="${assets_json}"; then
        log_error "Failed to create GitLab release"
        exit 1
    fi
    
    log_info "GitLab release created successfully"
}

# Helper function to generate assets JSON
generate_assets_json() {
    if command -v jq >/dev/null 2>&1; then
        # Use jq if available
        local json_array=()
        for file in "${DIST_DIR}"/*; do
            json_array+=("$(jq -n \
                --arg name "$(basename "${file}")" \
                --arg url "${CI_PROJECT_URL}/-/jobs/${CI_JOB_ID}/artifacts/file/$(basename "${file}")" \
                '{name: $name, url: $url, link_type: "package"}')")
        done
        printf '%s\n' "[$(IFS=,; echo "${json_array[*]}")]"
    else
        # Fallback to manual JSON construction
        local json="["
        local first=true
        
        for file in "${DIST_DIR}"/*; do
            [[ "${first}" == "false" ]] && json+=","
            json+=$(printf '{
                "name": "%s",
                "url": "%s/-/jobs/%s/artifacts/file/%s",
                "link_type": "package"
            }' "$(basename "${file}")" "${CI_PROJECT_URL}" "${CI_JOB_ID}" "$(basename "${file}")")
            first=false
        done
        json+="]"
        
        echo "${json}"
    fi
}

# Function to handle Docker operations with improved error handling
do_docker() {
    log_info "Setting up Docker buildx"
    
    # Setup buildx if needed
    setup_docker_buildx

    log_info "Building and pushing Docker images"
    
    # Build and push multi-platform image with improved configuration
    if ! docker buildx build \
        --platform linux/amd64,linux/arm64 \
        --build-arg VERSION="${VERSION}" \
        --build-arg BUILD_DATE="$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        --build-arg VCS_REF="${CI_COMMIT_SHA:-$(git rev-parse HEAD)}" \
        --label "org.opencontainers.image.created=$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
        --label "org.opencontainers.image.version=${VERSION}" \
        --label "org.opencontainers.image.revision=${CI_COMMIT_SHA:-$(git rev-parse HEAD)}" \
        -t "${IMAGE_NAME}:${IMAGE_VERSION}" \
        -t "${IMAGE_NAME}:latest" \
        --push .; then
        log_error "Failed to build and push Docker images"
        exit 1
    fi
    
    log_info "Docker images built and pushed successfully"
}

# Helper function to setup Docker buildx
setup_docker_buildx() {
    if ! docker buildx ls | grep -q "builder \* docker"; then
        if ! docker buildx create --use --name builder; then
            log_error "Failed to create Docker buildx builder"
            exit 1
        fi
        if ! docker buildx inspect --bootstrap; then
            log_error "Failed to bootstrap Docker buildx"
            exit 1
        fi
    fi
}

# Function to clean up with safety checks
do_clean() {
    if [[ -d "${DIST_DIR}" ]]; then
        log_info "Cleaning up ${DIST_DIR}"
        rm -rf "${DIST_DIR}"
        log_info "Cleanup completed"
    else
        log_warn "Nothing to clean up - ${DIST_DIR} does not exist"
    fi
}

# Function to display usage with improved formatting
show_usage() {
    cat << EOF
Usage: $(basename "$0") [version] [dist_dir] [image_name] [command]

Commands:
    build          - Build platform-specific distributions
    release        - Create releases (use --github and/or --gitlab flags)
    docker         - Build and push Docker images
    clean          - Clean up build artifacts
    all            - Build all platforms (default)

Arguments:
    version     - Version tag (default: ${DEFAULT_VERSION})
    dist_dir    - Distribution directory (default: ${DEFAULT_DIST_DIR})
    image_name  - Docker image name (default: ${DEFAULT_IMAGE_NAME})

Release Flags:
    --github    - Create GitHub release
    --gitlab    - Create GitLab release

Environment Variables:
    DEBUG      - Enable debug logging when set to "true"
    CI_*       - GitLab CI variables (required for GitLab releases)

Example:
    $(basename "$0") v1.0.0 dist myorg/myimage build
    $(basename "$0") v1.0.0 dist myorg/myimage release --github --gitlab
EOF
}

# Main function with improved command handling
main() {
    check_requirements

    local cmd=${4:-all}
    shift 4 2>/dev/null || true
    
    case "${cmd}" in
        build|release|docker|clean|all|help)
            log_info "Executing command: ${cmd}"
            case "${cmd}" in
                build) build_platforms ;;
                release) 
                    build_platforms
                    local do_github=false
                    local do_gitlab=false
                    while [[ $# -gt 0 ]]; do
                        case "$1" in
                            --github) do_github=true ;;
                            --gitlab) do_gitlab=true ;;
                            *) log_error "Unknown release flag: $1"; show_usage; exit 1 ;;
                        esac
                        shift
                    done
                    if [[ "$do_github" == "true" ]]; then
                        do_github_release
                    fi
                    if [[ "$do_gitlab" == "true" ]]; then
                        do_gitlab_release
                    fi
                    if [[ "$do_github" == "false" && "$do_gitlab" == "false" ]]; then
                        log_error "Must specify at least one of --github or --gitlab"
                        show_usage
                        exit 1
                    fi
                    ;;
                docker) do_docker ;;
                clean) do_clean ;;
                all) build_platforms ;;
                help) show_usage ;;
            esac
            ;;
        *)
            log_error "Unknown command: ${cmd}"
            show_usage
            exit 1
            ;;
    esac
}

# Execute main function with all arguments
main "$@"