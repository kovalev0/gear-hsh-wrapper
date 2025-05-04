#!/usr/bin/env bash
# uninstall.sh
# Script to uninstall gear-hsh-wrapper configurations and symlinks.

# Exit immediately if a command exits with a non-zero status,
# but use rm -f to avoid errors if files/dirs are already gone.
set -e

# --- Configuration ---
# Target installation directory in the user's home.
TARGET_DIR="$HOME/hsh-sandboxes"

# Target directory for symbolic links in the user's home.
BIN_DIR="$HOME/bin"

# Prefix for symbolic links created by the installer.
LINK_PREFIX="gear-hsh-wrapper-"

# --- Functions ---

# Function to print informational messages.
info() {
    echo "INFO: $@"
}

# --- Script Start ---

info "Starting uninstallation script..."

# 1. Remove the target installation directory
if [ -d "$TARGET_DIR" ]; then
    info "Removing installation directory: '$TARGET_DIR'..."
    # Use rm -rf for forceful and recursive removal.
    # Add -f to avoid errors if files are read-only or directory is not empty.
    rm -rf "$TARGET_DIR"
    info "Directory '$TARGET_DIR' removed."
else
    info "Installation directory not found: '$TARGET_DIR'. Nothing to remove."
fi

# 2. Remove the symbolic links from the binary directory
info "Removing symbolic links from '$BIN_DIR'..."

# Use a glob to find all potential links created by the installer.
# rm -f is used to remove links and avoid errors if the glob matches nothing
# or if some links are already removed.
REMOVED=0
for link in "$BIN_DIR/${LINK_PREFIX}"*; do
    # Check if the file exists and is a symbolic link
    if [ -L "$link" ]; then
        info "Removing symlink: '$link'"
        rm "$link"
        REMOVED=$((REMOVED + 1))
    # The glob might match literal string if no files match. Check if it's not the literal glob.
    elif [ -e "$link" ]; then
        # It exists but is not a symlink created by us (or a broken link, rm -f handles broken).
        # This case is less likely for files starting with the prefix that are not symlinks,
        # but good practice would be to be more specific, e.g., check link target.
        # However, the requirement is just to remove links matching the pattern.
        # The find command approach from the install script could be adapted, but simple glob + rm -f is sufficient here.
        # If it's not a symlink but exists, rm -f would remove it. Let's just remove symlinks explicitly.
        true # Do nothing, not a symlink we created
    fi
done

if [ "$REMOVED" -gt 0 ]; then
    info "Removed $REMOVED symbolic link(s) from '$BIN_DIR'."
else
    info "No '$LINK_PREFIX*' symbolic links found in '$BIN_DIR'."
fi

info "Uninstallation finished."

exit 0
