# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Important:** When adding new code to the project, update this CLAUDE.md file with relevant information about new features, commands, or architectural changes.

## Project Description

Proxmox Wake-on-Joystick is a Rust service that monitors gamepad/joystick input and automatically wakes up Proxmox virtual machines when the right trigger (RT) button is pressed. Designed for gaming setups where VMs use USB passthrough for controllers.

Key features:
- Monitors joystick input only when VM is stopped (prevents USB conflicts)
- Automatically stops monitoring when VM starts (allows USB passthrough)
- Uses local `qm` commands for direct Proxmox control (no API authentication needed)
- Handles joystick connect/disconnect events gracefully
- Runs as a systemd service with configurable VM target
- Cross-platform build system with Docker support

## Common Commands

### Build and Run
- `cargo build` - Build the project
- `cargo run` - Build and run the project
- `cargo build --release` - Build optimized release version

### Development
- `make help` - Show all available make targets
- `make check` - Run all quality checks (formatting, compilation, linting)
- `make format` - Format code automatically
- `make build` - Build release binary
- `make deps` - Install system dependencies
- `make all` - Run checks and build
- `make package-deb-docker` - Build Debian package using Docker
- `make clean` - Clean build artifacts

## Architecture

The project follows standard Rust project structure:
- `Cargo.toml` - Project configuration and dependencies
- `src/main.rs` - Main entry point with async monitoring loop
- `Makefile` - Build automation and packaging
- `.github/workflows/release.yml` - CI/CD pipeline

## Dependencies

- `gilrs` - Cross-platform gamepad/joystick input handling
- `tokio` - Async runtime for concurrent operations

## Configuration

The application uses environment variables for configuration:
- `PROXMOX_VM_ID` - VM ID to wake up (default: 100)

## Installation

### Prerequisites
- Proxmox VE host
- Root access

### Option 1: Debian Package (Recommended)
```bash
# Download the .deb package from GitHub releases
wget https://github.com/victor9999/proxmox-wake-on-joystick/releases/latest/download/proxmox-wake-on-joystick_*_amd64.deb

# Install the package
sudo dpkg -i proxmox-wake-on-joystick_*_amd64.deb

# Configure VM ID (edit the service file)
sudo nano /etc/systemd/system/proxmox-wake-on-joystick.service
# Change: Environment=PROXMOX_VM_ID=100 to your VM ID

# Enable and start the service
sudo systemctl enable proxmox-wake-on-joystick
sudo systemctl start proxmox-wake-on-joystick
```

### Option 2: Build from Source
If you have Rust toolchain installed:
```bash
# Install dependencies
make deps

# Install the service
sudo make install
```

### Building and Packaging
```bash
# Run all checks
make check

# Build release binary
make build

# Create Debian package (requires dpkg-deb)
make package-deb

# Create Debian package using Docker (works anywhere)
make package-deb-docker

# Full release workflow
make release
```

### Uninstall
**Debian Package:**
```bash
sudo apt remove proxmox-wake-on-joystick
```

**Source Installation:**
```bash
sudo make uninstall
```

## Deployment

This application is designed to run directly on a Proxmox host as a service. It uses the local `qm` command which requires root privileges and bypasses API authentication since it's running locally on the Proxmox system.

## Behavior

The application runs as a continuous monitoring service with the following behavior:

1. **Startup**: Always starts VM status monitoring regardless of initial state
2. **If VM is running**: Monitors VM status every 10 seconds waiting for shutdown
3. **If VM is stopped**: Starts joystick listener for RT button detection
4. **During joystick listening**: Periodically monitors VM status every 10 seconds
5. **When VM starts**: Automatically stops joystick listener to free USB device for passthrough
6. **When VM stops**: Automatically restarts joystick listener
7. **RT button press**: Executes `qm start <vm_id>` and stops listening
8. **Continuous cycle**: Returns to VM monitoring after joystick listener stops

The application provides continuous operation, automatically switching between VM monitoring and joystick listening based on VM state to prevent USB passthrough conflicts.

## Development Guidelines

- Always run checks before commit
