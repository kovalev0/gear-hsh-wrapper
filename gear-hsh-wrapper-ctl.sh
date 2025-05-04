#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Copyright (C) 2025 Vasiliy Kovalev <kovalev@altlinux.org>
#
# Inspired by a hasher build script concept by Alex Vesev (ALT Linux, 2012).
#

# Exit immediately if a command exits with a non-zero status
set -e
# Exit if any command in a pipeline fails
set -o pipefail
# Exit upon usage of an uninitialized variable (enabled after config load)
# set -u

# --- Constants ---
# Base directory for environment configurations
declare -r HSH_SANDBOXES_BASE_DIR="${HOME}/hsh-sandboxes"
# Mandatory prefix for symlink names
declare -r SCRIPT_NAME_PREFIX="gear-hsh-wrapper-"

# --- Script Variables ---
declare script_name=""          # Script name (basename $0)
declare env_name=""             # Environment name (extracted from script_name)
declare tmp_mode=0              # Temporary directory mode (1 = /tmp, 0 = $HOME)
declare config_dir=""           # Path to environment config directory
declare config_file=""          # Path to env.conf
declare apt_config_file=""      # Path to apt.conf
declare VERBOSE=0               # Verbose mode (0 = off, 1 = on)

# Function to print INFO messages
info() {
    if [[ "$VERBOSE" -eq 1 ]]; then
        echo "INFO: $*"
    fi
}

# Display usage information
usage() {
cat << EOF
Usage: ${script_name} [-v | --verbose] [command | query_option] [options]

Script to manage hasher environments via symlinks. Determines environment
from the symlink name it was called with.

Symlink name pattern: '${SCRIPT_NAME_PREFIX}<env_name>' or '${SCRIPT_NAME_PREFIX}<env_name>.tmp'.
Example: gear-hsh-wrapper-sisyphus-x86_64 build

'<env_name>' corresponds to the directory ${HSH_SANDBOXES_BASE_DIR}/<env_name>,
which must contain env.conf, apt.conf, etc.

Options:
  -v, --verbose        Enable verbose output (must be the first argument if used
                       with a command).

Query Options (print configuration value and exit):
  --target             Print target architecture (e.g., x86_64).
  --workdir            Print hasher sandbox workdir path.
  --apt-config         Print path to the apt.conf file used.
  --repo               Print path to the repository inside the sandbox.
  --mountpoints        Print default base mount points.

Detected environment: '${env_name:-Not determined}'
Config directory: '${config_dir:-Not determined}'
Temporary mode: ${tmp_mode} ('1' means using /tmp)
Log file pattern: log.${env_name}[.tmp]

Available Commands:
  init | ini             Initialize hasher environment (with cache).
  init-no-cache | inin   Initialize hasher environment (without cache).
  shell | sh             Enter builder shell.
  shell-net | shn        Enter builder shell with network access.
  shell-kvm | shk        Enter builder shell with /dev/kvm mounted.
  shell-net-kvm | shnk   Enter builder shell with share network and /dev/kvm.
  shroot | shr           Enter builder shell as root.
  shroot-net | shrn      Enter builder shell as root with share network.
  shroot-kvm | shrk      Enter builder shell as root with /dev/kvm.
  shroot-net-kvm | shrnk Enter builder shell as root with share network and /dev/kvm.
  build | bu [nprocs]    Build package (init + build). [nprocs]: number of CPU cores (default: all available).
  rebuild | reb | rbu    Rebuild package (without init).
  install | ins PKG...   Install packages into hasher environment.
  run CMD [ARG...]       Execute command as builder inside hasher environment.
  run-root CMD [ARG...]  Execute command as rooter inside hasher environment.
  cleanup | clean | cl   Clean up hasher environment.
  help | --help | -h     Show this help message.
EOF
}

# Determine environment details from script name
determine_environment() {
    local name_to_parse="${script_name}"

    # Check for .tmp suffix
    if [[ "${name_to_parse}" == *.tmp ]]; then
        tmp_mode=1
        name_to_parse="${name_to_parse%.tmp}" # Remove suffix for further parsing
    fi

    # Check prefix
    if [[ "${name_to_parse}" != ${SCRIPT_NAME_PREFIX}* ]]; then
        echo "Error: Script name '${script_name}' does not start with prefix '${SCRIPT_NAME_PREFIX}'." >&2
        echo "       Please create a symlink named like '${SCRIPT_NAME_PREFIX}<env_name>'." >&2
        exit 1
    fi

    # Extract environment name
    env_name="${name_to_parse#${SCRIPT_NAME_PREFIX}}" # Remove prefix

    if [[ -z "${env_name}" ]]; then
        echo "Error: Could not extract environment name from script name '${script_name}'." >&2
        exit 1
    fi

    # Build path to config directory
    config_dir="${HSH_SANDBOXES_BASE_DIR}/${env_name}"

    # Check if config directory exists
    if [[ ! -d "${config_dir}" ]]; then
        echo "Error: Config directory not found: ${config_dir}" >&2
        echo "       (Determined from script name '${script_name}'. Expected env name: '${env_name}')" >&2
        exit 1
    fi

    # Determine paths to essential config files
    config_file="${config_dir}/env.conf"
    apt_config_file="${config_dir}/apt.conf" # apt.conf is needed by hsh/gear commands

    # Check for main config files
    if [[ ! -f "${config_file}" ]]; then
        echo "Error: Environment config file not found: ${config_file}" >&2
        exit 1
    fi
     if [[ ! -f "${apt_config_file}" ]]; then
        echo "Error: Apt config file not found: ${apt_config_file}" >&2
        exit 1
    fi

    info "Environment detected: '${env_name}' (config: ${config_dir})"
}

# Load configuration from env.conf
load_config() {
    # Default values (can be overridden in env.conf)
    maintainerName="Local Host"
    maintainerMail="localhost@altlinux.org"
    optSuffix="" # Optional suffix for hasher sandbox directory name
    # Default sisyphus check args - override in env.conf if needed
    argNoCheck="--no-sisyphus-check=gpg,changelog" # Default: disable only GPG and changelog checks
    # Default mount points (can potentially be overridden in env.conf too if needed later)
    argMountPoints="/proc,/dev/pts"

    # Load variables from config file
    # shellcheck source=/dev/null
    source "${config_file}"

    # Check for mandatory variables from env.conf
    if [[ -z "${branch:-}" ]] || [[ -z "${archTarget:-}" ]]; then
        echo "Error: Variables 'branch' and 'archTarget' must be defined in ${config_file}" >&2
        exit 1
    fi
}

# --- Main Script Logic ---

script_name=$(basename -- "$0") # Get the name the script was called with

# Handle --verbose flag first if present
if [[ "${1:-}" == "-v" ]] || [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=1
    shift # Remove --verbose from args
fi

# Determine environment details from the symlink name
determine_environment # Sets $env_name, $config_dir, $config_file, $apt_config_file, $tmp_mode

# Handle help option (checked after verbose but before loading config)
# Need $env_name and $config_dir to be set for usage() to display them
if [[ "${#}" -gt 0 && ( "${1}" == "--help" || "${1}" == "-h" || "${1}" == "help" ) ]]; then
    # Attempt to load config just for showing potentially overridden defaults in usage
    # Ignoring errors here as user just wants help
    set +e
    load_config >/dev/null 2>&1
    set -e
    usage # Display help
    exit 0
# Handle case where no arguments are given *at all* (needs help)
elif [[ "${#}" -eq 0 ]]; then
    # Attempt to load config to show defaults in usage, even if no command given
    set +e
    load_config >/dev/null 2>&1
    set -e
    usage
    exit 1
fi

# Load environment configuration from env.conf
load_config

# Enable checking for undeclared variables after env.conf is sourced
set -u

# --- Derived Variables (after environment and config are loaded) ---
# Hasher sandbox directory name (uses variables from env.conf)
declare -r dirSandBox="${branch}-${archTarget}${optSuffix}"

# Determine base directory for hasher sandbox ($HOME or /tmp)
declare dirSandBoxTopHasher
if [[ "${tmp_mode}" -eq 1 ]]; then
    dirSandBoxTopHasher="/tmp/.private/$(whoami)/hasher"
else
    dirSandBoxTopHasher="${HOME}/hasher"
fi
# Full path to the specific hasher sandbox
declare -r dirSandBoxHasher="${dirSandBoxTopHasher}/${dirSandBox}"
# Ensure the hasher sandbox directory exists (needed by --workdir query below, and hsh commands)
mkdir -p "${dirSandBoxHasher}"

# Log file name (uses env_name)
declare log_prefix="log.${env_name}"
declare log_suffix=""
if [[ "${tmp_mode}" -eq 1 ]]; then
    log_suffix=".tmp"
fi
declare -r log="${log_prefix}${log_suffix}" # e.g., log.sisyphus-x86_64 or log.p10-aarch64.tmp

# Path to the repository inside the sandbox (used by --repo query and commands)
declare -r DirRepoHasher="${dirSandBoxHasher}/repo"

# --- Handle Query Arguments ---
# Check if the first remaining argument is a query for configuration details
case "${1:-}" in
    --target)
        echo "${archTarget}"
        exit 0
        ;;
    --workdir)
        echo "${dirSandBoxHasher}"
        exit 0
        ;;
    --apt-config)
        echo "${apt_config_file}"
        exit 0
        ;;
    --repo)
        echo "${DirRepoHasher}"
        exit 0
        ;;
    --mountpoints)
        echo "${argMountPoints}"
        exit 0
        ;;
    # If none of the above matched, proceed to normal command processing
esac

# --- Command Processing ---
declare command="${1:-}" # Get the command (will be empty if only query arg was given, but we already exited)
shift || true # Remove the command/query arg from the args list

# Determine nprocs for the build command
declare nprocs
if [[ "${command}" == "build" ]] || [[ "${command}" == "bu" ]]; then
    if [[ "${1:-}" =~ ^[0-9]+$ ]]; then # If the next arg is a number
        nprocs="${1}"
        shift # Remove nprocs from args
    else
        # Use nproc if available, otherwise default to 1
        nprocs=$(nproc 2>/dev/null || echo 1)
    fi
else
    # Default nprocs for other commands (if needed, currently not used elsewhere)
    nprocs=$(nproc 2>/dev/null || echo 1)
fi

# Execute command
info "Executing command '${command:-no command}' for environment '${env_name}' (target: ${branch}/${archTarget})"
info "Hasher sandbox: ${dirSandBoxHasher}"

if [[ "$VERBOSE" -eq 1 ]]; then
    set -x
fi

case "${command}" in
    init|ini)
        info "Initializing hasher (with cache). Log: ${log} ..."
        hsh -v --target="${archTarget}" \
            --apt-config="${apt_config_file}" \
            --initroot-only "${dirSandBoxHasher}" \
            2>&1 | tee "${log}"
        ;;
    init-no-cache|inin)
        info "Initializing hasher (no cache). Log: ${log} ..."
        hsh -v --target="${archTarget}" --no-cache \
            --apt-config="${apt_config_file}" \
            --initroot-only "${dirSandBoxHasher}" \
            2>&1 | tee "${log}"
        ;;

    shell|sh)
        info "Entering hasher shell..."
        hsh-shell --mountpoints="${argMountPoints}" "${dirSandBoxHasher}"
        ;;
    shell-net|shn)
        info "Entering hasher shell (with network)..."
        share_network=1 hsh-shell --mountpoints="${argMountPoints}" "${dirSandBoxHasher}"
        ;;
    shell-kvm|shk)
        info "Entering hasher shell (with /dev/kvm)..."
        hsh-shell --mountpoints="${argMountPoints},/dev/kvm" "${dirSandBoxHasher}"
        ;;
    shell-net-kvm|shnk)
        info "Entering hasher shell (with network, /dev/kvm)..."
        share_network=1 hsh-shell --mountpoints="${argMountPoints},/dev/kvm" "${dirSandBoxHasher}"
        ;;

    shroot|shr)
        info "Entering hasher shell as root..."
        hsh-shell --mountpoints="${argMountPoints}" "${dirSandBoxHasher}" --rooter
        ;;
    shroot-net|shrn)
        info "Entering hasher shell as root (with network)..."
        share_network=1 hsh-shell --mountpoints="${argMountPoints}" "${dirSandBoxHasher}" --rooter
        ;;
    shroot-kvm|shrk)
        info "Entering hasher shell as root (with /dev/kvm)..."
        hsh-shell --mountpoints="${argMountPoints},/dev/kvm" "${dirSandBoxHasher}" --rooter
        ;;
    shroot-net-kvm|shrnk)
        info "Entering hasher shell as root (with network, /dev/kvm)..."
        share_network=1 hsh-shell --mountpoints="${argMountPoints},/dev/kvm" "${dirSandBoxHasher}" --rooter
        ;;

    build|bu)
        info "Starting build (nprocs=${nprocs}). Log: ${log} ..."
        # Run gear/hsh for building. Log output using tee.
        gear \
            --verbose \
            --commit \
            --hasher \
            -- \
            hsh \
                --verbose \
                --nprocs="${nprocs}" \
                --packager="${maintainerName} <${maintainerMail}>" \
                ${argNoCheck} \
                --target="${archTarget}" \
                --lazy-cleanup \
                --apt-config="${apt_config_file}" \
                --mountpoints="${argMountPoints},/sys" \
                --repo="${DirRepoHasher}" \
                "${dirSandBoxHasher}" \
                2>&1 | tee "${log}"
        ;;

    rebuild|reb|rbu)
        info "Starting rebuild. Log: ${log} ..."
        # Run gear/hsh-rebuild.
        gear \
            --verbose \
            --commit \
            --hasher \
            -- \
            hsh-rebuild \
                --verbose \
                ${argNoCheck} \
                --target="${archTarget}" \
                --mountpoints="${argMountPoints},/sys" \
                --repo="${DirRepoHasher}" \
                "${dirSandBoxHasher}" \
                2>&1 | tee "${log}"
        ;;

    install|ins)
        if [[ $# -eq 0 ]]; then
            echo "Error: 'install' command requires at least one package name." >&2
            exit 1
        fi
        info "Installing packages: $*"
        # Use "${@}" to correctly pass package names with spaces
        hsh-install "${dirSandBoxHasher}" "${@}"
        ;;

    run)
        if [[ $# -eq 0 ]]; then
            echo "Error: 'run' command requires a command to execute." >&2
            exit 1
        fi
        info "Executing command: $*"
        # Use "${@}" to correctly pass command arguments with spaces
        hsh-run "${dirSandBoxHasher}" -- "${@}"
        ;;

    run-root)
        if [[ $# -eq 0 ]]; then
            echo "Error: 'run-root' command requires a command to execute." >&2
            exit 1
        fi
        info "Executing command: $*"
        # Use "${@}" to correctly pass command arguments with spaces
        hsh-run --rooter "${dirSandBoxHasher}" -- "${@}"
        ;;

    cleanup|clean|cl)
        info "Cleaning up environment..."
        hsh --cleanup-only "${dirSandBoxHasher}"
        ;;

    *)

        if [[ "$VERBOSE" -eq 1 ]]; then
            set +x
        fi

        # Handle no command case (command is empty string)
        # This condition should now correctly trigger if no command or query option was provided
        if [[ -z "${command}" ]]; then
            echo "Error: No command or query option specified." >&2
            # Ensure config is loaded enough for usage() defaults before exiting
            set +e
            load_config >/dev/null 2>&1
            set -e
            usage
            exit 1
        fi
        # Handle unknown command
        echo "Error: Unknown command or option '${command}'" >&2
        # Ensure config is loaded enough for usage() defaults before exiting
        set +e
        load_config >/dev/null 2>&1
        set -e
        usage # Show help
        exit 1
        ;;
esac

info "Command '${command}' completed successfully for environment '${env_name}'."
exit 0
