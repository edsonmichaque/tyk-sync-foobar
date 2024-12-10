#!/bin/sh
set -e

# Configuration
GITHUB_ORG="TykTechnologies"
GITLAB_ORG="TykTechnologies"
REPO="tyk-sync-foobar"
DEFAULT_DIRS="/usr/local/bin $HOME/bin $HOME/.local/bin"
VERSION="latest"
VERIFY_CHECKSUM=true
FORCE=false
QUIET=false
SHELL_COMPLETION=true
UNINSTALL=false
USE_GITHUB=true
USE_GITLAB=false
CUSTOM_INSTALL_DIR=""

# Styling
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log() { [ "$QUIET" = false ] && printf "${BLUE}==>${NC} %s\n" "$1"; }
success() { [ "$QUIET" = false ] && printf "${GREEN}✓${NC} %s\n" "$1"; }
warn() { printf "${YELLOW}Warning:${NC} %s\n" "$1" >&2; }
error() { printf "${RED}Error:${NC} %s\n" "$1" >&2; exit 1; }

# Find first writable directory from list
find_install_dir() {
    if [ -n "$CUSTOM_INSTALL_DIR" ]; then
        if [ -w "$CUSTOM_INSTALL_DIR" ] || [ -w "$(dirname "$CUSTOM_INSTALL_DIR")" ]; then
            echo "$CUSTOM_INSTALL_DIR"
            return 0
        fi
        error "Custom installation directory is not writable: $CUSTOM_INSTALL_DIR"
    fi

    for dir in $DEFAULT_DIRS; do
        if [ -w "$dir" ] || [ -w "$(dirname "$dir")" ]; then
            echo "$dir"
            return 0
        fi
    done
    error "No writable installation directory found"
}

# Platform detection
detect_platform() {
    OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        *) error "Unsupported architecture: $ARCH" ;;
    esac

    case $OS in
        linux|darwin) : ;;
        *) error "Unsupported operating system: $OS" ;;
    esac

    log "Detected platform: ${OS}/${ARCH}"
}

# Version management
get_latest_version() {
    if [ "$VERSION" = "latest" ]; then
        log "Fetching latest version..."
        if [ "$USE_GITHUB" = true ]; then
            VERSION=$(curl -sL "https://api.github.com/repos/${GITHUB_ORG}/${REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        elif [ "$USE_GITLAB" = true ]; then
            VERSION=$(curl -sL "https://gitlab.com/api/v4/projects/${GITLAB_ORG}%2F${REPO}/releases" | grep '"tag_name":' | head -n1 | sed -E 's/.*"([^"]+)".*/\1/')
        fi
        [ -z "$VERSION" ] && error "Failed to get latest version"
        success "Latest version is ${VERSION}"
    fi
}

# Parse command line arguments
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --no-verify) VERIFY_CHECKSUM=false ;;
            --force) FORCE=true ;;
            --quiet) QUIET=true ;;
            --no-completion) SHELL_COMPLETION=false ;;
            --version) VERSION="$2"; shift ;;
            --uninstall) UNINSTALL=true ;;
            --gitlab) USE_GITLAB=true; USE_GITHUB=false ;;
            --github) USE_GITHUB=true; USE_GITLAB=false ;;
            --dir) CUSTOM_INSTALL_DIR="$2"; shift ;;
            --help) show_help; exit 0 ;;
            *) error "Unknown option: $1" ;;
        esac
        shift
    done
}

# Show help message
show_help() {
    cat << EOF
Usage: install.sh [options]

Options:
  --no-verify      Skip checksum verification
  --force          Force installation even if already installed
  --quiet          Minimal output
  --no-completion  Skip shell completion installation
  --version VER    Install specific version
  --uninstall      Uninstall portal-sync
  --gitlab         Use GitLab as download source
  --github         Use GitHub as download source (default)
  --dir DIR        Custom installation directory
  --help           Show this help message
EOF
}

# Installation
install_binary() {
    local tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT

    local filename="${REPO}_${VERSION#v}_${OS}_${ARCH}"
    local url
    local checksums_url

    if [ "$USE_GITHUB" = true ]; then
        url="https://github.com/${GITHUB_ORG}/${REPO}/releases/download/${VERSION}/${filename}.tar.gz"
        checksums_url="https://github.com/${GITHUB_ORG}/${REPO}/releases/download/${VERSION}/checksums.txt"
    elif [ "$USE_GITLAB" = true ]; then
        url="https://gitlab.com/${GITLAB_ORG}/${REPO}/-/releases/${VERSION}/downloads/${filename}.tar.gz"
        checksums_url="https://gitlab.com/${GITLAB_ORG}/${REPO}/-/releases/${VERSION}/downloads/checksums.txt"
    fi

    # Check if already installed
    if [ "$FORCE" = false ] && command -v tyk-sync-foobar >/dev/null; then
        local current_version=$(tyk-sync-foobar version 2>/dev/null || echo "unknown")
        if [ "$current_version" = "$VERSION" ]; then
            log "Version ${VERSION} already installed"
            exit 0
        fi
    fi

    log "Downloading ${REPO} ${VERSION}..."
    curl -#L -o "$tmpdir/${filename}.tar.gz" "$url" || error "Download failed"

    if [ "$VERIFY_CHECKSUM" = true ]; then
        log "Verifying checksum..."
        curl -sL -o "$tmpdir/checksums.txt" "$checksums_url" || error "Checksum download failed"
        (cd "$tmpdir" && sha256sum -c --ignore-missing checksums.txt) || error "Checksum verification failed"
        success "Checksum verified"
    fi

    INSTALL_DIR=${INSTALL_DIR:-$(find_install_dir)}
    mkdir -p "$INSTALL_DIR"

    log "Installing to ${INSTALL_DIR}..."
    tar xzf "$tmpdir/${filename}.tar.gz" -C "$tmpdir"
    install -m 755 "$tmpdir/tyk-sync-foobar" "$INSTALL_DIR/"

    if [ "$SHELL_COMPLETION" = true ]; then
        install_completions "$tmpdir"
    fi

    # Add binary verification
    if ! "$INSTALL_DIR/tyk-sync-foobar" version >/dev/null 2>&1; then
        error "Binary verification failed after installation"
    fi
}

# Install shell completions
install_completions() {
    local tmpdir="$1"
    local completion_dir

    case "$SHELL" in
        */bash)
            completion_dir="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"
            ;;
        */zsh)
            completion_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
            ;;
        */fish)
            completion_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fish/vendor_completions.d"
            ;;
        *)
            return 0
            ;;
    esac

    if [ -f "$tmpdir/completions" ]; then
        mkdir -p "$completion_dir"
        install -m 644 "$tmpdir/completions" "$completion_dir/tyk-sync-foobar"
        success "Installed shell completions"
    fi
}

# Uninstall
uninstall() {
    if ! command -v tyk-sync-foobar >/dev/null; then
        error "tyk-sync-foobar is not installed"
    fi

    local install_path=$(command -v tyk-sync-foobar)
    rm -f "$install_path"
    success "Uninstalled tyk-sync-foobar"

    # Remove completions
    rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/tyk-sync-foobar"
    rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions/tyk-sync-foobar"
    rm -f "${XDG_DATA_HOME:-$HOME/.local/share}/fish/vendor_completions.d/tyk-sync-foobar"
}

# Main process
main() {
    parse_args "$@"

    if [ "$UNINSTALL" = true ]; then
        uninstall
        exit 0
    fi

    detect_platform
    get_latest_version
    install_binary

    if command -v tyk-sync-foobar >/dev/null; then
        success "Successfully installed tyk-sync-foobar ${VERSION} to ${INSTALL_DIR}"
        if [ "$QUIET" = false ]; then
            echo
            echo "To get started:"
            echo "  tyk-sync-foobar --help"
            echo
            echo "Documentation: https://github.com/${GITHUB_ORG}/${REPO}/docs"
            echo
        fi
    else
        error "Installation failed"
    fi
}

main "$@"
