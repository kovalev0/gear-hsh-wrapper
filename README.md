# gear-hsh-wrapper

Wrappers for the [gear](https://en.altlinux.org/Gear) and [hasher](https://en.altlinux.org/Hasher) utilities in ALT Linux distributions, designed to facilitate building and debugging RPM packages within isolated `hasher` environments.

This project provides configuration files and a control script to simplify launching build or shell sessions using `hasher` utilities for specific architectures and repository branches configured within the wrapper. It acts as a frontend to the `hasher` utilities, making it easier to manage different build environments.

## Features

* Provides standard configuration files (`apt.conf`, `env.conf`, `priorities`, `sources.list`) for various ALT Linux architectures and branches.
* Includes a central control script (`gear-hsh-wrapper-ctl.sh`) that acts as a frontend to `hasher` utilities.
* Creates symbolic links in `~/bin` for each configured environment (e.g., `gear-hsh-wrapper-sisyphus-x86_64`, `gear-hsh-wrapper-sisyphus-aarch64.tmp`), allowing easy invocation from the command line.
* Determines target environment (`branch`, `arch`) from the symlink name.
* Supports temporary build mode using `/tmp` via `.tmp` suffix in symlink name.
* Provides standard commands (`build`, `rebuild`, `shell`, `init`, `install`, `run`, `cleanup`).
* Allows querying environment configuration (`--target`, `--workdir`, `--apt-config`, `--repo`, `--mountpoints`) for use with hasher utilities.
* Logs build/initialization output to `log.<env_name>[.tmp]`.

## Usage

The script `gear-hsh-wrapper-ctl.sh` is designed to be invoked via symbolic links created during the installation process. Each symlink corresponds to a specific hasher environment configuration located in `~/hsh-sandboxes/`.

The symlink name determines the environment and operational mode. The expected naming pattern is:

* `gear-hsh-wrapper-<env_name>`: Uses the configuration from `~/hsh-sandboxes/<env_name>` and typically creates/uses the hasher sandbox in `~/hasher/`.
* `gear-hsh-wrapper-<env_name>.tmp`: Uses the configuration from `~/hsh-sandboxes/<env_name>` and typically creates/uses the hasher sandbox in `/tmp/.private/<user>/hasher/` for temporary, potentially RAM-backed environments.

* **General Syntax**:

    ```bash
    <symlink_name> [-v | --verbose] [command | query_option] [options/arguments]
    ```
    * `<symlink_name>`: The name of the symbolic link you execute (e.g., `gear-hsh-wrapper-sisyphus-x86_64`, `gear-hsh-wrapper-p10-aarch64.tmp`).
    * `-v, --verbose`: Optional flag to enable verbose output. Must be the first argument if used.
    * `[command]`: The action you want to perform within the determined hasher environment (see below).
    * `[query_option]`: An option to retrieve configuration information (see below). Only one command or query option can be used per invocation..
    * `[options/arguments]`: Additional arguments specific to the command (e.g., package names, a command to run, number of processes for build).

* **Available Commands**

    The following commands are available:
    * `init`, `ini`: Initialize the hasher environment (*uses cache*).
    * `init-no-cache`, `inin`: Initialize the hasher environment (*without cache*).
    * `shell`, `sh`: Enter a builder shell within the hasher environment.
    * `shell-net`, `shn`: Enter a builder shell with network access.
    * `shell-kvm`, `shk`: Enter a builder shell with */dev/kvm* mounted (useful for nested virtualization if available).
    * `shell-net-kvm`, `shnk`: Enter a builder shell with network access and */dev/kvm* mounted.
    * `shroot`, `shr`: Enter a builder shell as root.
    * `shroot-net`, `shrn`: Enter a builder shell as root with network access.
    * `shroot-kvm`, `shrk`: Enter a builder shell as root with */dev/kvm* mounted.
    * `shroot-net-kvm`, `shrnk`: Enter a builder shell as root with network access and */dev/kvm* mounted.
    * `build`, `bu` *[nprocs]*: Build the package in the current directory. [nprocs] is the optional number of CPU cores to use (defaults to all available). Performs environment initialization if needed.
    * `rebuild`, `reb`, `rbu`: Rebuild the package in the current directory (does not perform environment initialization).
    * `install`, `ins` *PKG...*: Install one or more packages (PKG...) into the hasher environment.
    * `run` *CMD [ARG...]*: Execute an arbitrary command (CMD) with optional arguments (ARG...) inside the hasher environment as builder.
    * `run-root` *CMD [ARG...]*: Execute an arbitrary command (CMD) with optional arguments (ARG...) inside the hasher environment as rooter.
    * `cleanup`, `clean`, `cl`: Clean up the hasher environment.
    * `help`, `-h`, `--help`: Show the usage help message.

* **Querying Configuration**

    Instead of a command, you can use one of the following options to print a specific configuration value and exit. This is useful for querying environment settings needed by backend hasher utilities or other scripts:
    * `--target`: Print the target architecture (e.g., `x86_64`).
    * `--workdir`: Print the full path to the hasher sandbox workdir.
    * `--apt-config`: Print the full path to the `apt.conf` file used for this environment.
    * `--repo`: Print the path to the local repository *inside* the hasher sandbox (e.g., */home/user/hasher/sisyphus-x86_64/repo*).
    * `--mountpoints`: Print the default base mount points used for `shell` commands (e.g., */proc,/dev/pts*).


* **Logging**

    Output from `ini`(`init`), `inin`(`init-no-cache`), `build`, and `rebuild` commands is logged to a file named `log.<env_name>[.tmp]` in the directory where the command was executed. This file is useful for reviewing the process output and debugging issues.

* **Examples**

    ```bash
    # Build package for sisyphus/x86_64 using default settings
    gear-hsh-wrapper-sisyphus-x86_64 build
    
    # Enter shell for p10/aarch64 using /tmp for the sandbox
    gear-hsh-wrapper-p10-aarch64.tmp shell
    
    # Get the workdir for the temporary p10/aarch64 environment
    echo $(gear-hsh-wrapper-p10-aarch64.tmp --workdir)
    # Example Output: /tmp/.private/your_user/hasher/p10-aarch64
    
    # Build with verbose output
    gear-hsh-wrapper-sisyphus-x86_64 -v bu
    ```
    See the **Quick Start Example** section below for more practical demonstrations.

## Configuration
The wrapper's behavior for each environment is defined by configuration files located in `~/hsh-sandboxes/<env_name>/`.
The `install.sh` script populates this directory with default configurations from the `configs/` subdirectory.

Each environment directory (`<env_name>`) is expected to contain:
* `env.conf`: Defines key variables for the environment.
* `apt.conf`: Defines APT configuration for the chroot.
* Other optional files like `sources.list`, `priorities`, etc., depending on the specific APT setup required for the branch/architecture.

The `env.conf` file is sourced by the wrapper script and must define at least the following variables:
* `branch`: The name of the ALT Linux branch (e.g., *sisyphus*, *p10*).
* `archTarget`: The target architecture for the environment (e.g., *x86_64*, *aarch64*, *riscv64*).

Additionally, `env.conf` can define:
* `maintainerName`, `maintainerMail`: Used to set the packager information for build commands. Defaults to *"Local Host localhost@altlinux.org"* if not set.
* `optSuffix`: An optional suffix appended to the hasher sandbox directory name (`<branch>-<archTarget><optSuffix>`). Useful for distinguishing multiple sandboxes for the same *branch*/*arch*.
* `argNoCheck`: Arguments passed to hasher's *--no-sisyphus-check* option. The script defaults this to *--no-sisyphus-check=gpg,changelog*. You can override this variable in `env.conf` to disable other checks.

Users can add their own environment configurations by creating new subdirectories within `~/hsh-sandboxes/` containing the necessary `env.conf`,`apt.conf`,`sources.list` and `priorities` files. After adding a new configuration, re-running `install.sh` will create the corresponding symlinks in `~/bin/`.

## Supported Architectures and Branches
The wrapper includes configurations for building packages for various architectures, including `x86_64`, `i586`, `aarch64`, `riscv64`, `loongarch64`, and `mipsel`. These configurations utilize package bases from different branches like `sisyphus`, `p11`, `p10`, and `c10f2` from the [Sisyphus](https://en.altlinux.org/Sisyphus) repository.

## Prerequisites
* An ALT Linux distribution.
* `gear` and `hasher` packages installed.
* `git` for cloning repositories.
* **For cross-architecture builds** (e.g., *aarch64* on *x86_64* host):
    * Install the `qemu-user-binfmt_misc` (*qemu-user-static-binfmt*) package. This package registers QEMU user-mode emulators with the kernel's `binfmt_misc` facility, allowing the kernel to automatically execute binaries compiled for other architectures.
    * Ensure your kernel supports `binfmt_misc` (check */proc/filesystems* for `binfmt_misc` or kernel configuration `CONFIG_BINFMT_MISC=m`).

* Your user account must be added to *hasher* using `hasher-useradd <USER>`.
* `hasher-privd.service` must be configured to allow mounting necessary directories and devices. A typical configuration in `/etc/hasher-priv/system` includes:
    ```
    prefix=~:/tmp/.private
    allowed_mountpoints=/proc,/dev/pts,/sys,/dev/shm
    allowed_devices=/dev/kvm # Optional, for KVM acceleration if used
    allow_ttydev=yes         # Recommended for interactive sessions
    ```
    The wrapper script requires */proc*, */dev/pts*, and */sys* for `shell`/`build` commands. */dev/kvm* is needed for the `shk`/`shnk`/`shrk`/`shrnk` commands. `/dev/shm` is often useful.
    
* The wrapper utilities are installed into the `~/bin` directory in your home directory. You need to ensure that `~/bin` is included in your system's `PATH` environment variable so that you can execute the wrapper scripts directly by name. ALT Linux distributions typically configure this by default for user home directories.

## Installation
1. Clone the repository:
    ```bash
    git clone https://github.com/kovalev0/gear-hsh-wrapper.git
    ```
2. Navigate into the cloned directory:
    ```bash
    cd gear-hsh-wrapper
    ```
3. **As your regular user**, ensure the `~/.hasher` directory exists and configure hasher to install resolver configuration files into the chroot. This is crucial for network access within the sandbox.
    ```bash
    mkdir -p ~/.hasher
    echo "install_resolver_configuration_files=1" > ~/.hasher/config
    ```
4. Run the installation script from within this directory:
    ```bash
    ./install.sh
    ```
    This script will:
    * Backup any existing `~/hsh-sandboxes` directory (to `~/hsh-sandboxes.bak.<timestamp>`).
    * Create a new `~/hsh-sandboxes` directory.
    * Copy all configuration files from `configs/` directory and the control script (`gear-hsh-wrapper-ctl.sh`) into `~/hsh-sandboxes`.
    * Modify apt.conf files within `~/hsh-sandboxes` subdirectories to use your actual home directory path instead of a placeholder `/home/user/`.
    * Ensure `~/bin` exists.
    * Create symbolic links in `~/bin` for each configured environment, pointing to `~/hsh-sandboxes/gear-hsh-wrapper-ctl.sh`. Two links are created for each config directory `<config_name>`: `gear-hsh-wrapper-<config_name>` and `gear-hsh-wrapper-<config_name>.tmp`.
    
## Uninstallation
1. Navigate to the cloned repository directory (or ensure the `uninstall.sh` script is accessible).
2. Run the uninstallation script:
    ```bash
    ./uninstall.sh
    ```
    This script will:
    * Remove the `~/hsh-sandboxes` directory and all its contents.
    * Remove all symbolic links in `~/bin` starting with `gear-hsh-wrapper-`.
    
## Quick Start Example: Building and Running
This example demonstrates setting up the environment and building/running the `cmatrix` ([gear](https://git.altlinux.org/gears/c/cmatrix.git)/[upstream](https://github.com/abishekvashok/cmatrix)) package for different architectures.
1. **Initial System Setup (as root)**:

    ```bash
    su -
    apt-get update
    apt-get install -y hasher gear qemu-user-binfmt_misc git
    hasher-useradd $(logname) # Replace $(logname) with your actual username if needed    
    # Configure hasher-privd (add lines if not present)
    echo 'prefix=~:/tmp/.private' >> /etc/hasher-priv/system
    echo 'allowed_mountpoints=/proc,/dev/pts,/sys,/dev/shm' >> /etc/hasher-priv/system
    echo 'allowed_devices=/dev/kvm' >> /etc/hasher-priv/system
    echo 'allow_ttydev=yes' >> /etc/hasher-priv/system
    systemctl restart hasher-privd.service
    exit
    ```

2. **User Setup (as your regular user)**:

    ```bash
    # Ensure .hasher directory exists
    mkdir -p ~/.hasher
    # Configure hasher to install resolver config files (apt.conf, etc.) into the chroot
    echo "install_resolver_configuration_files=1" > ~/.hasher/config
    ```
3. **Install gear-hsh-wrapper's**:
    ```bash
    git clone https://github.com/kovalev0/gear-hsh-wrapper.git
    cd gear-hsh-wrapper
    ./install.sh
    # Go back to your home directory or wherever you manage packages
    cd ~
    ```
4. **Example with *cmatrix* package**:

    ```bash
    # Clone the cmatrix gear (package source)
    git clone https://git.altlinux.org/gears/c/cmatrix.git
    cd cmatrix
    
    ### x86_64 Build/Run (using temporary sandbox in /tmp)
    gear-hsh-wrapper-sisyphus-x86_64.tmp build
    gear-hsh-wrapper-sisyphus-x86_64.tmp install cmatrix
    gear-hsh-wrapper-sisyphus-x86_64.tmp shell
    # Inside hasher shell as builder:
    [builder@localhost .in]$ timeout 5 cmatrix; exit
    
    ### riscv64 Build/Run (using a persistent sandbox in ~)
    gear-hsh-wrapper-sisyphus-riscv64 bu # Use short 'bu' alias
    gear-hsh-wrapper-sisyphus-riscv64 ins cmatrix # Use short 'ins' alias
    # Query the workdir path for this env
    gear-hsh-wrapper-sisyphus-riscv64 --workdir
    # Enter shell using short 'shr' alias
    gear-hsh-wrapper-sisyphus-riscv64 shr
    # Inside hasher shell as rooter:
    [root@localhost .in]$ timeout 5 cmatrix; exit
    ```

    The wrapper script automatically uses the appropriate configuration (`apt.conf`, `sources.list`, `etc.`) located in `~/hsh-sandboxes/<config_name>` based on the symbolic link name used for invocation.

## License
This project is licensed under the GNU General Public License v3.0. See the LICENSE file for details.

## Acknowledgements
Inspired by a hasher build script concept by Alex Vesev (ALT Linux, 2012).
