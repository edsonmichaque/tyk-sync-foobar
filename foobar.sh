#!/usr/bin/env sh

# Exit on error, undefined vars, and pipe failures
set -euo pipefail

# Enable debug mode if DEBUG environment variable is set
[ "${DEBUG:-}" = "true" ] && set -x

# Constants
SCRIPT_NAME=$(basename "$0")
LOG_FILE="/tmp/${SCRIPT_NAME}.log"

# Logging functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2 | tee -a "$LOG_FILE"
}

# Cleanup function
cleanup() {
    # Add cleanup tasks here
    log "Cleaning up..."
}

# Set trap for cleanup on script exit
trap cleanup EXIT

# Usage information
usage() {
    cat << EOF
Usage: $SCRIPT_NAME [OPTIONS]
Options:
    -h, --help     Show this help message
    -v, --verbose  Enable verbose output
EOF
}

# Parse command line arguments
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--verbose)
                set -x
                shift
                ;;
            *)
                error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Main program
main() {
    log "Starting script execution"
    
    # Your main logic here
    log "Hello, world!"
    
    log "Script completed successfully"
    return 0
}

# Run main program
if ! parse_args "$@"; then
    error "Failed to parse arguments"
    exit 1
fi

if ! main; then
    error "Script failed"
    exit 1
fi
