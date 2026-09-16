<div align="center">
  <h1>Mole (Linux)</h1>
  <p><em>🧹 Clean, uninstall, analyze, optimize, and monitor your Linux system.</em></p>
  <p><strong>A fast, terminal-first cleanup toolkit ported for Linux (Arch, Ubuntu/Debian, WSL2, Omarchy).</strong></p>
</div>

<p align="center">
  <a href="https://github.com/itzmail/mole_linux/releases"><img src="https://img.shields.io/github/v/tag/itzmail/mole_linux?label=version&style=flat-square" alt="Version"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL_v3-blue.svg?style=flat-square" alt="License"></a>
  <a href="https://github.com/itzmail/mole_linux/commits"><img src="https://img.shields.io/github/commit-activity/m/itzmail/mole_linux?style=flat-square" alt="Commits"></a>
</p>

## Overview

Mole is an all-in-one terminal maintenance and cleanup tool for Linux. It helps you reclaim disk space, safely uninstall desktop and CLI applications along with their config/cache leftovers, explore disk usage visually, and monitor system health.

## Features

- **Package & Cache Cleaner (`mo clean`)**:
  - Package manager caches: `pacman` (with `paccache`), AUR helpers (`yay`, `paru`), and `apt-get clean`.
  - Developer caches: `npm`, `pnpm`, `yarn`, `pip`.
  - Browser caches: Chrome, Chromium, Firefox runtime caches.
  - Systemd journal: automatic vacuum (`journalctl --vacuum-time=7d`).
  - XDG Trash cleanup.
- **Smart Application Uninstaller (`mo uninstall`)**:
  - Categorized tagging:
    - `[Desktop]`: System GUI applications (`.desktop`)
    - `[Webapp]`: Desktop web applications (e.g. Omarchy webapps in `~/.local/share/applications/`)
    - `[CLI]`: Command-line tools and utilities
  - Interactive multi-select paginated TUI menu with live search/filtering.
  - Automatic XDG leftover removal (`~/.config/<app>`, `~/.cache/<app>`, `~/.local/share/<app>`).
  - System safety filters: protects critical core packages (`base`, `linux*`, `systemd*`, `*keyring*`, `glibc`).
- **Visual Disk Explorer (`mo analyze`)**:
  - Interactive TUI disk explorer written in Go.
  - Fast directory traversal, size sorting, and safe deletion via XDG Trash.
- **Live System Status (`mo status`)**:
  - Real-time CPU, memory, disk, network, and battery statistics.
  - Automation-ready JSON/NDJSON output.
- **Project Artifact Purge (`mo purge`)**:
  - Finds and cleans heavy build artifacts: `node_modules`, `target/`, `.next/`, `dist/`, `build/`.
- **Audit Logging (`mo history`)**:
  - Operation logs recorded in `~/.local/state/mole/operations.log` (or `~/.cache/mole/`).

---

## Quick Start

### Installation

Install via one-line curl script:

```bash
curl -fsSL https://raw.githubusercontent.com/itzmail/mole_linux/main/install.sh | bash
```

To install directly to user path (`~/.local/bin`) without requiring root:

```bash
mkdir -p "$HOME/.local/bin"
curl -fsSL https://raw.githubusercontent.com/itzmail/mole_linux/main/install.sh | bash -s -- --prefix "$HOME/.local/bin"
```

*Make sure `~/.local/bin` is in your `$PATH`.*

### Manual Build from Source

Requires `bash`, `go` (1.21+), and `make`:

```bash
git clone https://github.com/itzmail/mole_linux.git
cd mole_linux
make build
./install.sh --prefix "$HOME/.local/bin"
```

---

## Usage

```bash
mo                           # Interactive main menu
mo clean                     # Clean caches, package archives, and logs
mo uninstall                 # Interactive application & package uninstaller
mo analyze                   # Visual disk explorer (interactive TUI)
mo status                    # System status and resource dashboard
mo purge                     # Clean developer build artifacts across projects
mo history                   # View cleanup operation history
mo update                    # Self-update to latest release
mo update --nightly          # Update to latest git main branch
mo --help                    # Show help and available options
```

### Uninstaller Examples

```bash
mo uninstall                 # Open interactive TUI selection menu
mo uninstall --desktop       # Interactive menu filtered to Desktop apps
mo uninstall --webapp        # Interactive menu filtered to Webapps
mo uninstall --cli           # Interactive menu filtered to CLI tools
mo uninstall --list          # Print candidate list table
mo uninstall --json          # Output candidates as JSON

mo uninstall Discord         # Uninstall specific webapp or package
mo uninstall chromium        # Uninstall specific desktop package
mo uninstall --dry-run bat   # Preview package removal without deleting
```

### Safe Preview & Whitelisting

```bash
mo clean --dry-run           # Preview cleanable items without deleting
mo uninstall --dry-run       # Preview uninstaller plan
mo purge --dry-run           # Preview purgeable project directories
mo clean --whitelist         # Manage protected caches
```

---

## Supported Environments

- **Arch Linux & Derivatives**: native `pacman` and AUR cache support (`yay`, `paru`).
- **Debian & Ubuntu**: native `apt` cache cleaning and `dpkg-query` package uninstall.
- **WSL2 (Windows Subsystem for Linux)**: full support for Ubuntu/Debian/Arch under WSL2.
- **Omarchy Linux**: full support for Omarchy Hyprland environment and desktop webapps.
- **macOS**: Mole requires macOS 12 or newer and supports both Intel and Apple Silicon Macs.

---

## License

GNU General Public License v3.0 ([GPL-3.0](LICENSE)). Original Mole toolkit by [@tw93](https://github.com/tw93/mole).
