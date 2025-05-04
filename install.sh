#!/usr/bin/env bash
# install.sh
# Script to install gear-hsh-wrapper configuration,
# modify config files, and create symlinks.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# Source directory where the script resides.
# We determine this dynamically to allow execution from anywhere.
# readlink -f is used to get the absolute path, resolving symlinks.
SCRIPT_PATH="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
SOURCE_DIR_NAME="gear-hsh-wrapper"

# Target installation directory in the user's home.
TARGET_DIR="$HOME/hsh-sandboxes"

# Target directory for symbolic links in the user's home.
BIN_DIR="$HOME/bin"

# The control script name within the source/target directory.
CONTROL_SCRIPT="gear-hsh-wrapper-ctl.sh"

# The directory with configs
CONFIG_DIR_NAME="configs"

# Prefix for symbolic links.
LINK_PREFIX="gear-hsh-wrapper-"

# Get the current username
CURRENT_USERNAME="$(whoami)"

# --- Functions ---

# Function to print error messages to stderr.
error() {
    echo "Error: $@" >&2
    exit 1
}

# Function to print informational messages.
info() {
    echo "INFO: $@"
}

# --- Script Start ---

info "Starting installation script..."

# 1. Verify script location
# Ensure the script is run from within the expected source directory.
if [[ "$(basename "$SCRIPT_DIR")" != "$SOURCE_DIR_NAME" ]]; then
    error "Script must be run from within the '$SOURCE_DIR_NAME' directory. Current directory is '$SCRIPT_DIR'."
fi
info "Verified script location: '$SCRIPT_DIR'"

# 2. Backup existing target directory if it exists
if [ -d "$TARGET_DIR" ]; then
    info "Existing target directory found: '$TARGET_DIR'."
    BACKUP_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_DIR="${TARGET_DIR}_backup_${BACKUP_TIMESTAMP}"

    info "Backing up '$TARGET_DIR' to '$BACKUP_DIR'..."

    # Check if the target backup path already exists. If so, remove it.
    if [ -e "$BACKUP_DIR" ]; then
        info "Removing existing backup destination path: '$BACKUP_DIR'..."
        rm -rf "$BACKUP_DIR" || error "Failed to remove existing backup path '$BACKUP_DIR'."
    fi

    mv "$TARGET_DIR" "$BACKUP_DIR" || error "Failed to backup '$TARGET_DIR' to '$BACKUP_DIR'."
    info "Backup complete."
fi

# 3. Create the new target directory
info "Creating new target directory: '$TARGET_DIR'..."
mkdir -p "$TARGET_DIR" || error "Failed to create target directory '$TARGET_DIR'."
info "Target directory created."

# 4. Copy contents from source to target
info "Copying contents from '$SCRIPT_DIR' to '$TARGET_DIR'..."
cp    "$CONTROL_SCRIPT"    "$TARGET_DIR/"
cp -r "$CONFIG_DIR_NAME/." "$TARGET_DIR/"
info "Content copy complete."

# 5. Modify apt.conf files to replace '/home/user/' with the actual user's home path
info "Modifying apt.conf files to reflect current user's home path..."

# Find all apt.conf files in the subdirectories of the target directory
find "$TARGET_DIR" -type f -name "apt.conf" | while read -r apt_conf_file; do
    info "Processing file: '$apt_conf_file'"
    # Use sed to replace '/home/user/' with '/home/$CURRENT_USERNAME/'
    # Using '#' as a delimiter for sed's 's' command because the paths contain '/'.
    # The '$CURRENT_USERNAME' variable is expanded by the shell before sed is run.
    sed -i "s#/home/user/#/home/$CURRENT_USERNAME/#g" "$apt_conf_file" || error "Failed to modify '$apt_conf_file'."
done

info "apt.conf modification complete."

# 6. Ensure the binary directory exists
info "Ensuring binary directory exists: '$BIN_DIR'..."
mkdir -p "$BIN_DIR" || error "Failed to create binary directory '$BIN_DIR'."
info "Binary directory ensured."

# 7. Create symbolic links in the binary directory
# The target of the links is the control script in the newly created target directory.
LINK_TARGET="$TARGET_DIR/$CONTROL_SCRIPT"

info "Creating symbolic links in '$BIN_DIR'..."

# Find all subdirectories in the *target* directory (the newly copied ones)
# Use find to get absolute paths, then extract the basename (directory name)
find "$TARGET_DIR" -mindepth 1 -maxdepth 1 -type d | while read -r sub_dir_path; do
    # Extract just the directory name (e.g., p10-x86_64)
    dir_name=$(basename "$sub_dir_path")

    # Construct the link names
    LINK_NAME_BASE="${LINK_PREFIX}${dir_name}"
    LINK_PATH_1="$BIN_DIR/$LINK_NAME_BASE"
    LINK_PATH_2="$BIN_DIR/$LINK_NAME_BASE.tmp"

    info "Processing directory for links: '$dir_name'"

    # Remove existing links if they exist, without error if they don't.
    rm -f "$LINK_PATH_1" "$LINK_PATH_2"

    # Create the new symbolic links
    ln -s "$LINK_TARGET" "$LINK_PATH_1" || error "Failed to create symlink '$LINK_PATH_1'."
    ln -s "$LINK_TARGET" "$LINK_PATH_2" || error "Failed to create symlink '$LINK_PATH_2'."

    info "Created links: '$LINK_PATH_1' and '$LINK_PATH_2' pointing to '$LINK_TARGET'."

done

info "Symbolic link creation complete."
info "Installation finished successfully."

exit 0
