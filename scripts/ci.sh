#!/usr/bin/env bash

# Exit on error, undefined variables, and prevent pipe errors
set -euo pipefail
IFS=$'\n\t'

# Script constants and defaults
readonly DEFAULT_VERSION="v0.1.0"
readonly DEFAULT_DIST_DIR="dist"
readonly DEFAULT_IMAGE_NAME="edsonmichaque/tyk-sync-foobar"

# Validate input arguments
if [[ $# -lt 1 ]]; then
    echo "Error: Missing required arguments" >&2
    exit 1
fi

readonly VERSION=${1:-"${DEFAULT_VERSION}"}
readonly DIST_DIR=${2:-"${DEFAULT_DIST_DIR}"}
readonly IMAGE_NAME=${3:-"${DEFAULT_IMAGE_NAME}"}
readonly IMAGE_VERSION=${VERSION}

# Validate version format
if ! [[ ${VERSION} =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    echo "Error: Invalid version format. Must be in format vX.Y.Z[-tag]" >&2
    exit 1
fi

# Supported platforms
readonly PLATFORMS=(
    "windows_amd64"
    "windows_arm64"
    "windows_386"
    "macos_amd64" 
    "macos_arm64"
    "macos_386"
    "linux_amd64"
    "linux_arm64"
    "linux_386"
    "linux_arm"
    "linux_ppc64le"
)

# Colors for logging
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions with timestamps and error codes
log_info() { echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${GREEN}[INFO]${NC} $*" >&2; }
log_warn() { echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${YELLOW}[WARN]${NC} $*" >&2; }
log_error() { 
    local code=$1
    shift
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${RED}[ERROR]${NC} $* (Code: ${code})" >&2
    return "${code}"
}
log_debug() { 
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] ${BLUE}[DEBUG]${NC} $*" >&2
    fi
}

# Error handler with detailed context and cleanup
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error $exit_code "Script failed in ${BASH_SOURCE[0]} on line $LINENO"
        log_error $exit_code "Command that failed: ${BASH_COMMAND}"
        log_error $exit_code "Call stack:"
        local frame=0
        while caller $frame; do
            ((frame++))
        done
    fi
    exit $exit_code
}

trap cleanup ERR EXIT

# Validate required tools with version checks and detailed errors
check_requirements() {
    local required_tools=(
        "gh:2.0.0"
    )
    
    local failed=0
    for tool_spec in "${required_tools[@]}"; do
        local tool="${tool_spec%%:*}"
        local min_version="${tool_spec#*:}"
        
        if ! command -v "$tool" >/dev/null 2>&1; then
            log_error 127 "Required tool not found: $tool"
            failed=1
            continue
        fi

        local current_version
        case "$tool" in
            gh)
                if ! current_version=$(gh --version | head -n1 | cut -d' ' -f3); then
                    log_error 1 "Failed to get GitHub CLI version"
                    failed=1
                    continue
                fi
                ;;
            *)
                log_error 1 "Unknown tool: $tool"
                failed=1
                continue
                ;;
        esac

        if ! verify_version "$current_version" "$min_version"; then
            log_warn "$tool version $current_version is lower than recommended version $min_version"
        fi
    done

    if [[ $failed -eq 1 ]]; then
        return 1
    fi
}

# Version comparison helper with input validation
verify_version() {
    if [[ $# -ne 2 ]]; then
        log_error 1 "verify_version requires exactly 2 arguments"
        return 1
    fi

    local current="$1"
    local required="$2"
    
    if [[ ! $current =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]] || 
       [[ ! $required =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
        log_error 1 "Invalid version format. Must be in format X.Y.Z[-tag]"
        return 1
    fi
    
    if [[ "$(printf '%s\n' "$required" "$current" | sort -V | head -n1)" == "$required" ]]; then
        return 0
    else
        return 1
    fi
}

# Validate environment variables for GitLab releases with detailed errors
validate_gitlab_env() {
    local required_vars=(
        "CI_PROJECT_URL"
        "CI_JOB_ID"
        "CI_COMMIT_SHA"
        "CI_PIPELINE_ID"
    )
    
    local missing_vars=()
    local invalid_vars=()

    for var in "${required_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing_vars+=("$var")
        elif [[ $var == "CI_PROJECT_URL" && ! "${!var}" =~ ^https?:// ]]; then
            invalid_vars+=("$var")
        elif [[ $var =~ ^CI_.*_ID$ && ! "${!var}" =~ ^[0-9]+$ ]]; then
            invalid_vars+=("$var")
        fi
    done

    local errors=0
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error 1 "Required GitLab CI variables not set: ${missing_vars[*]}"
        errors=1
    fi
    
    if [[ ${#invalid_vars[@]} -gt 0 ]]; then
        log_error 1 "Invalid GitLab CI variable values: ${invalid_vars[*]}"
        errors=1
    fi

    return $errors
}

# Function to build for different platforms with enhanced error handling
build_platforms() {
    local compress=${1:-false}
    log_info "Building for platforms: ${PLATFORMS[*]}"
    
    # Validate source file
    local source_file="foobar.sh"
    if [[ ! -f "${source_file}" ]]; then
        log_error 1 "Source file '${source_file}' not found in current directory: $(pwd)"
        log_error 1 "Please ensure the source file exists and you're running the script from the correct directory"
        return 1
    fi

    if [[ ! -r "${source_file}" ]]; then
        log_error 1 "Source file '${source_file}' is not readable"
        return 1
    fi

    # Create dist directory with error handling
    if ! mkdir -p "${DIST_DIR}"; then
        log_error 1 "Failed to create distribution directory: ${DIST_DIR}"
        return 1
    fi
    
    local checksums_file="${DIST_DIR}/checksums.txt"
    if ! rm -f "${checksums_file}"; then
        log_error 1 "Failed to remove existing checksums file"
        return 1
    fi
    
    if ! touch "${checksums_file}"; then
        log_error 1 "Failed to create new checksums file"
        return 1
    fi
    
    local build_errors=0
    for platform in "${PLATFORMS[@]}"; do
        log_info "Processing platform: $platform"
        local output_file="${DIST_DIR}/tyk-sync-foobar_${VERSION}_${platform}"
        
        # Add .exe extension for Windows platforms
        if [[ "${platform}" == windows* ]]; then
            output_file="${output_file}.exe"
        fi
        
        if ! cp "${source_file}" "${output_file}"; then
            log_error 1 "Failed to copy source file to ${output_file}"
            build_errors=$((build_errors + 1))
            continue
        fi
        
        if ! chmod +x "${output_file}"; then
            log_error 1 "Failed to make ${output_file} executable"
            build_errors=$((build_errors + 1))
            continue
        fi
        
        # Compress if requested
        if [[ "${compress}" == "true" ]]; then
            if [[ "${platform}" == windows* ]]; then
                # Create zip for Windows
                if ! (cd "${DIST_DIR}" && zip -q "$(basename "${output_file}").zip" "$(basename "${output_file}")"); then
                    log_error 1 "Failed to create zip for ${output_file}"
                    build_errors=$((build_errors + 1))
                    continue
                fi
                rm "${output_file}"
                output_file="${output_file}.zip"
            else
                # Create tar.gz for other platforms
                if ! (cd "${DIST_DIR}" && tar -czf "$(basename "${output_file}").tar.gz" "$(basename "${output_file}")"); then
                    log_error 1 "Failed to create tar.gz for ${output_file}"
                    build_errors=$((build_errors + 1))
                    continue
                fi
                rm "${output_file}"
                output_file="${output_file}.tar.gz"
            fi
        fi
        
        # Generate checksum with error handling
        if ! (cd "${DIST_DIR}" && sha256sum "$(basename "${output_file}")" >> "checksums.txt"); then
            log_error 1 "Failed to generate checksum for ${output_file}"
            build_errors=$((build_errors + 1))
            continue
        fi
        
        log_debug "Generated artifact: ${output_file}"
    done
    
    # Delete any remaining raw binaries after compression
    if [[ "${compress}" == "true" ]]; then
        find "${DIST_DIR}" -type f -not -name "*.zip" -not -name "*.tar.gz" -not -name "checksums.txt" -delete
    fi
    
    if [[ $build_errors -gt 0 ]]; then
        log_error 1 "Build completed with ${build_errors} errors"
        return 1
    fi
    
    log_info "Build completed successfully"
    log_info "Generated checksums file: ${checksums_file}"
}

# Function to handle GitHub releases with enhanced error handling and retries
do_github_release() {
    log_info "Creating GitHub release for version ${VERSION}"
    
    # Check for gh CLI tool
    if ! command -v gh >/dev/null 2>&1; then
        log_error 127 "Required tool not found: gh"
        return 1
    fi

    # Check gh version
    local current_version
    if ! current_version=$(gh --version | head -n1 | cut -d' ' -f3); then
        log_error 1 "Failed to get GitHub CLI version"
        return 1
    fi

    if ! verify_version "$current_version" "2.0.0"; then
        log_warn "gh version $current_version is lower than recommended version 2.0.0"
    fi
    
    # Validate GitHub authentication
    if ! gh auth status >/dev/null 2>&1; then
        log_error 1 "GitHub CLI not authenticated. Please run 'gh auth login' first"
        return 1
    fi

    # Validate distribution directory
    if [[ ! -d "${DIST_DIR}" ]]; then
        log_error 1 "Distribution directory not found: ${DIST_DIR}"
        return 1
    fi

    # Check for artifacts
    local artifact_count
    artifact_count=$(find "${DIST_DIR}" -type f | wc -l)
    if [[ $artifact_count -eq 0 ]]; then
        log_error 1 "No artifacts found in ${DIST_DIR}"
        return 1
    fi

    local max_retries=3
    local retry_count=0
    local success=false
    local wait_time=5

    while [[ $retry_count -lt $max_retries && $success == false ]]; do
        if gh release view "${VERSION}" >/dev/null 2>&1; then
            log_error 1 "Release ${VERSION} already exists"
            return 1
        fi

        if gh release create "${VERSION}" "${DIST_DIR}"/* \
            --title "Release ${VERSION}" \
            --notes "Automated release of version ${VERSION}" \
            --generate-notes; then
            success=true
            log_info "GitHub release created successfully"
        else
            retry_count=$((retry_count + 1))
            if [[ $retry_count -lt $max_retries ]]; then
                log_warn "Failed to create GitHub release, retrying in ${wait_time} seconds... (Attempt $retry_count of $max_retries)"
                sleep $wait_time
                wait_time=$((wait_time * 2))  # Exponential backoff
            else
                log_error 1 "Failed to create GitHub release after $max_retries attempts"
                return 1
            fi
        fi
    done
}

# Function to handle GitLab releases with enhanced error handling
do_gitlab_release() {
    log_info "Creating GitLab release for version ${VERSION}"
    
    if ! validate_gitlab_env; then
        return 1
    fi

    if [[ ! -d "${DIST_DIR}" ]]; then
        log_error 1 "Distribution directory not found: ${DIST_DIR}"
        return 1
    fi

    # Validate artifact existence
    local artifact_count
    artifact_count=$(find "${DIST_DIR}" -type f | wc -l)
    if [[ $artifact_count -eq 0 ]]; then
        log_error 1 "No artifacts found in ${DIST_DIR}"
        return 1
    fi

    # Create asset links JSON with error handling
    local assets_json
    if ! assets_json=$(generate_assets_json); then
        log_error 1 "Failed to generate assets JSON"
        return 1
    fi

    # Validate release-cli availability
    if ! command -v release-cli >/dev/null 2>&1; then
        log_error 1 "release-cli not found. Please install GitLab release-cli"
        return 1
    fi

    if ! release-cli create \
        --name "Release ${VERSION}" \
        --tag-name "${VERSION}" \
        --description "Automated release of version ${VERSION}" \
        --ref "${CI_COMMIT_SHA}" \
        --assets-links="${assets_json}"; then
        log_error 1 "Failed to create GitLab release"
        return 1
    fi
    
    log_info "GitLab release created successfully"
}

# Helper function to generate assets JSON with error handling
generate_assets_json() {
    local temp_file
    temp_file=$(mktemp) || {
        log_error 1 "Failed to create temporary file"
        return 1
    }
    
    trap 'rm -f "${temp_file}"' RETURN

    if command -v jq >/dev/null 2>&1; then
        # Use jq if available
        local json_array=()
        local success=true
        
        for file in "${DIST_DIR}"/*; do
            if ! json_entry=$(jq -n \
                --arg name "$(basename "${file}")" \
                --arg url "${CI_PROJECT_URL}/-/jobs/${CI_JOB_ID}/artifacts/file/$(basename "${file}")" \
                '{name: $name, url: $url, link_type: "package"}'); then
                success=false
                break
            fi
            json_array+=("$json_entry")
        done
        
        if [[ $success == true ]]; then
            printf '%s\n' "[$(IFS=,; echo "${json_array[*]}")]" > "${temp_file}"
        else
            log_error 1 "Failed to generate JSON using jq"
            return 1
        fi
    else
        # Fallback to manual JSON construction
        {
            echo "["
            local first=true
            
            for file in "${DIST_DIR}"/*; do
                [[ "${first}" == "false" ]] && echo ","
                printf '    {
                "name": "%s",
                "url": "%s/-/jobs/%s/artifacts/file/%s",
                "link_type": "package"
            }' "$(basename "${file}")" "${CI_PROJECT_URL}" "${CI_JOB_ID}" "$(basename "${file}")"
                first=false
            done
            echo "]"
        } > "${temp_file}"
    fi
    
    cat "${temp_file}"
}

# Function to handle Docker operations with enhanced error handling and idempotency
do_docker() {
    log_info "Setting up Docker buildx"
    
    # Validate Docker daemon availability
    if ! docker info >/dev/null 2>&1; then
        log_error 1 "Docker daemon is not running or not accessible"
        return 1
    fi

    # Setup buildx with error handling
    if ! setup_docker_buildx; then
        log_error 1 "Failed to setup Docker buildx"
        return 1
    fi

    log_info "Building and pushing Docker images"
    
    # Validate Docker credentials
    if ! docker system info | grep -q "Username"; then
        log_error 1 "Docker is not logged in. Please authenticate first"
        return 1
    fi

    # Check if images already exist
    local tags=("${IMAGE_VERSION}" "latest")
    local all_exist=true
    for tag in "${tags[@]}"; do
        if ! docker manifest inspect "${IMAGE_NAME}:${tag}" >/dev/null 2>&1; then
            all_exist=false
            break
        fi
    done

    if [[ "${all_exist}" == "true" ]]; then
        log_info "Docker images already exist, skipping build"
        return 0
    fi

    local build_date
    build_date=$(date -u +'%Y-%m-%dT%H:%M:%SZ') || {
        log_error 1 "Failed to generate build date"
        return 1
    }

    local vcs_ref
    vcs_ref=${CI_COMMIT_SHA:-$(git rev-parse HEAD)} || {
        log_error 1 "Failed to determine VCS reference"
        return 1
    }

    # Build and push multi-platform image with enhanced error handling
    if ! docker buildx build \
        --platform linux/amd64,linux/arm64 \
        --build-arg VERSION="${VERSION}" \
        --build-arg BUILD_DATE="${build_date}" \
        --build-arg VCS_REF="${vcs_ref}" \
        --label "org.opencontainers.image.created=${build_date}" \
        --label "org.opencontainers.image.version=${VERSION}" \
        --label "org.opencontainers.image.revision=${vcs_ref}" \
        -t "${IMAGE_NAME}:${IMAGE_VERSION}" \
        -t "${IMAGE_NAME}:latest" \
        --push .; then
        log_error 1 "Failed to build and push Docker images"
        return 1
    fi
    
    # Verify pushed images
    for tag in "${tags[@]}"; do
        if ! docker manifest inspect "${IMAGE_NAME}:${tag}" >/dev/null 2>&1; then
            log_error 1 "Failed to verify pushed image: ${IMAGE_NAME}:${tag}"
            return 1
        fi
    done
    
    log_info "Docker images built and pushed successfully"
}

# Helper function to setup Docker buildx with enhanced error handling
setup_docker_buildx() {
    # Add timeout for Docker operations
    local timeout=30
    local interval=5

    # Wait for Docker daemon to be responsive
    local retries=$((timeout / interval))
    local attempt=0
    while ! docker info >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $retries ]]; then
            log_error 1 "Timeout waiting for Docker daemon to be responsive"
            return 1
        fi
        log_warn "Waiting for Docker daemon to be responsive... (${attempt}/${retries})"
        sleep $interval
    done

    # Check if builder already exists and is running
    if docker buildx ls 2>/dev/null | grep -q "builder.*running"; then
        log_info "Docker buildx builder already exists and is running"
        return 0
    fi

    # Remove existing builder if it exists but isn't running
    if docker buildx ls 2>/dev/null | grep -q "builder"; then
        log_info "Removing existing builder..."
        docker buildx rm builder >/dev/null 2>&1 || true
    fi
    
    # Create new builder with timeout
    attempt=0
    while ! docker buildx create --use --name builder >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $retries ]]; then
            log_error 1 "Failed to create Docker buildx builder after ${timeout} seconds"
            return 1
        fi
        log_warn "Retrying builder creation... (${attempt}/${retries})"
        sleep $interval
    done
    
    # Bootstrap builder with timeout
    attempt=0
    while ! docker buildx inspect --bootstrap >/dev/null 2>&1; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $retries ]]; then
            log_error 1 "Failed to bootstrap Docker buildx after ${timeout} seconds"
            return 1
        fi
        log_warn "Retrying builder bootstrap... (${attempt}/${retries})"
        sleep $interval
    done
    
    # Verify builder is working with timeout
    attempt=0
    while ! docker buildx inspect builder 2>/dev/null | grep -q "Status: running"; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $retries ]]; then
            log_error 1 "Docker buildx builder failed to enter running state after ${timeout} seconds"
            return 1
        fi
        log_warn "Waiting for builder to be ready... (${attempt}/${retries})"
        sleep $interval
    done

    log_info "Docker buildx setup completed successfully"
    return 0
}

# Function to clean up with enhanced safety checks
do_clean() {
    if [[ -d "${DIST_DIR}" ]]; then
        log_info "Cleaning up ${DIST_DIR}"
        
        # Check if directory is writable
        if [[ ! -w "${DIST_DIR}" ]]; then
            log_error 1 "Cannot clean ${DIST_DIR} - directory is not writable"
            return 1
        fi
        
        # Check for required space in parent directory
        local parent_dir
        parent_dir=$(dirname "${DIST_DIR}")
        if ! df -P "${parent_dir}" | awk 'NR==2 {exit($4<1000)}'; then
            log_error 1 "Insufficient space in ${parent_dir} for cleanup operation"
            return 1
        fi
        
        # Remove directory with error handling
        if ! rm -rf "${DIST_DIR}"; then
            log_error 1 "Failed to remove ${DIST_DIR}"
            return 1
        fi
        
        log_info "Cleanup completed successfully"
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

Build/Release Flags:
    --compress  - Create compressed archives (zip for Windows, tar.gz for others)
    --github    - Create GitHub release
    --gitlab    - Create GitLab release

Environment Variables:
    DEBUG      - Enable debug logging when set to "true"
    CI_*       - GitLab CI variables (required for GitLab releases)

Example:
    $(basename "$0") v1.0.0 dist myorg/myimage build --compress
    $(basename "$0") v1.0.0 dist myorg/myimage release --github --gitlab --compress
EOF
}

# Main function with enhanced error handling
main() {
    if [[ $# -lt 4 ]]; then
        log_error 1 "Insufficient arguments"
        show_usage
        return 1
    fi

    local cmd=${4}
    shift 4 || {
        log_error 1 "Failed to process arguments"
        return 1
    }
    
    case "${cmd}" in
        build) 
            local compress=false
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --compress) compress=true ;;
                    *) 
                        log_error 1 "Unknown build flag: $1"
                        show_usage
                        return 1
                        ;;
                esac
                shift
            done
            if ! build_platforms "${compress}"; then
                log_error 1 "Build command failed"
                return 1
            fi
            ;;
        release) 
            local compress=false
            local do_github=false
            local do_gitlab=false
            while [[ $# -gt 0 ]]; do
                case "$1" in
                    --github) do_github=true ;;
                    --gitlab) do_gitlab=true ;;
                    --compress) compress=true ;;
                    *) 
                        log_error 1 "Unknown release flag: $1"
                        show_usage
                        return 1
                        ;;
                esac
                shift
            done
            
            if [[ "$do_github" == "false" && "$do_gitlab" == "false" ]]; then
                log_error 1 "Must specify at least one of --github or --gitlab"
                show_usage
                return 1
            fi
            
            if ! build_platforms "${compress}"; then
                log_error 1 "Build failed during release"
                return 1
            fi
            
            if [[ "$do_github" == "true" ]]; then
                if ! do_github_release; then
                    log_error 1 "GitHub release failed"
                    return 1
                fi
            fi
            
            if [[ "$do_gitlab" == "true" ]]; then
                if ! do_gitlab_release; then
                    log_error 1 "GitLab release failed"
                    return 1
                fi
            fi
            ;;
        docker) 
            if ! do_docker; then
                log_error 1 "Docker command failed"
                return 1
            fi
            ;;
        clean) 
            if ! do_clean; then
                log_error 1 "Clean command failed"
                return 1
            fi
            ;;
        all) 
            if ! build_platforms; then
                log_error 1 "All command failed"
                return 1
            fi
            ;;
        help) show_usage ;;
        *)
            log_error 1 "Unknown command: ${cmd}"
            show_usage
            return 1
            ;;
    esac
}

# Execute main function with all arguments
if ! main "$@"; then
    exit 1
fi