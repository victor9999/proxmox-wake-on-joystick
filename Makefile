.PHONY: check build install uninstall clean package-deb package-deb-docker help

# Variables
BINARY_NAME = proxmox-wake-on-joystick
INSTALL_DIR = /opt/$(BINARY_NAME)
SERVICE_FILE = $(BINARY_NAME).service
DEB_DIR = debian-package
VERSION ?= 0.1.0

# Colors for output
RED = \033[0;31m
GREEN = \033[0;32m
YELLOW = \033[1;33m
BLUE = \033[0;34m
NC = \033[0m

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

check: ## Run all quality checks (formatting, compilation, linting)
	@echo -e "$(BLUE)Running all code quality checks...$(NC)"
	@echo ""
	@echo -e "$(YELLOW)1. Checking code formatting...$(NC)"
	@if cargo fmt --check; then \
		echo -e "$(GREEN)✓ Code formatting is correct$(NC)"; \
	else \
		echo -e "$(RED)✗ Code formatting issues found. Run 'make format' to fix.$(NC)"; \
		exit 1; \
	fi
	@echo ""
	@echo -e "$(YELLOW)2. Checking compilation...$(NC)"
	@if cargo check; then \
		echo -e "$(GREEN)✓ Code compiles successfully$(NC)"; \
	else \
		echo -e "$(RED)✗ Compilation failed$(NC)"; \
		exit 1; \
	fi
	@echo ""
	@echo -e "$(YELLOW)3. Running linter (clippy)...$(NC)"
	@if cargo clippy -- -D warnings; then \
		echo -e "$(GREEN)✓ No linting issues found$(NC)"; \
	else \
		echo -e "$(RED)✗ Linting issues found$(NC)"; \
		exit 1; \
	fi
	@echo ""
	@echo -e "$(GREEN)🎉 All checks passed successfully!$(NC)"
	@echo -e "$(BLUE)Code is ready for build and deployment.$(NC)"

format: ## Format code automatically
	cargo fmt

build: ## Build release binary
	cargo build --release

install: ## Install as systemd service
	@echo -e "$(GREEN)Installing Proxmox Wake-on-Joystick Service$(NC)"
	
	# Check if running as root
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo -e "$(RED)This script must be run as root$(NC)"; \
		exit 1; \
	fi
	
	# Check if we're on a Proxmox system
	@if ! command -v qm >/dev/null 2>&1; then \
		echo -e "$(YELLOW)Warning: 'qm' command not found. Make sure this is running on a Proxmox host.$(NC)"; \
	fi
	
	# Check if binary already exists (pre-built) or needs to be built
	@if [ -f "$(BINARY_NAME)" ]; then \
		echo "Using pre-built binary..."; \
		mkdir -p target/release; \
		cp $(BINARY_NAME) target/release/$(BINARY_NAME); \
	elif [ -f "target/release/$(BINARY_NAME)" ]; then \
		echo "Using existing built binary..."; \
	else \
		echo "Building the project..."; \
		if ! cargo build --release; then \
			echo -e "$(RED)Failed to build the project$(NC)"; \
			exit 1; \
		fi; \
	fi
	
	# Create installation directory
	@echo "Creating installation directory $(INSTALL_DIR)..."
	mkdir -p $(INSTALL_DIR)
	
	# Copy binary to system location
	@echo "Installing binary to $(INSTALL_DIR)/$(BINARY_NAME)..."
	cp target/release/$(BINARY_NAME) $(INSTALL_DIR)/$(BINARY_NAME)
	
	# Set restrictive permissions (root only)
	chown root:root $(INSTALL_DIR)/$(BINARY_NAME)
	chmod 700 $(INSTALL_DIR)/$(BINARY_NAME)
	
	# Prompt for VM ID
	@read -p "Enter the VM ID to monitor (default: 100): " VM_ID; \
	VM_ID=$${VM_ID:-100}; \
	echo "Creating systemd service..."; \
	sed -e "s|{{BINARY_PATH}}|$(INSTALL_DIR)/$(BINARY_NAME)|g" \
	    -e "s|{{VM_ID}}|$$VM_ID|g" \
	    $(SERVICE_FILE) > /etc/systemd/system/$(SERVICE_FILE)
	
	# Set service file permissions
	chown root:root /etc/systemd/system/$(SERVICE_FILE)
	chmod 644 /etc/systemd/system/$(SERVICE_FILE)
	
	# Reload systemd and enable service
	@echo "Enabling and starting service..."
	systemctl daemon-reload
	systemctl enable $(BINARY_NAME)
	systemctl start $(BINARY_NAME)
	
	# Check service status
	@if systemctl is-active --quiet $(BINARY_NAME); then \
		echo -e "$(GREEN)Service installed and started successfully!$(NC)"; \
		echo "Service status:"; \
		systemctl status $(BINARY_NAME) --no-pager -l; \
		echo ""; \
		echo "Installation details:"; \
		echo "  Binary: $(INSTALL_DIR)/$(BINARY_NAME) (root:root 700)"; \
		echo "  Service: /etc/systemd/system/$(SERVICE_FILE)"; \
		echo "  VM ID: $$VM_ID"; \
		echo ""; \
		echo "To view logs: journalctl -u $(BINARY_NAME) -f"; \
		echo "To stop service: systemctl stop $(BINARY_NAME)"; \
		echo "To uninstall: make uninstall"; \
	else \
		echo -e "$(RED)Service failed to start. Check logs with: journalctl -u $(BINARY_NAME)$(NC)"; \
		exit 1; \
	fi

uninstall: ## Uninstall service and remove files
	@echo -e "$(YELLOW)Uninstalling Proxmox Wake-on-Joystick Service$(NC)"
	
	# Check if running as root
	@if [ "$$(id -u)" -ne 0 ]; then \
		echo -e "$(RED)This script must be run as root$(NC)"; \
		exit 1; \
	fi
	
	# Stop and disable service
	@if systemctl is-active --quiet $(BINARY_NAME); then \
		echo "Stopping service..."; \
		systemctl stop $(BINARY_NAME); \
	fi
	
	@if systemctl is-enabled --quiet $(BINARY_NAME); then \
		echo "Disabling service..."; \
		systemctl disable $(BINARY_NAME); \
	fi
	
	# Remove service file
	@if [ -f "/etc/systemd/system/$(SERVICE_FILE)" ]; then \
		echo "Removing service file..."; \
		rm -f /etc/systemd/system/$(SERVICE_FILE); \
	fi
	
	# Remove installation directory
	@if [ -d "$(INSTALL_DIR)" ]; then \
		echo "Removing installation directory..."; \
		rm -rf $(INSTALL_DIR); \
	fi
	
	# Reload systemd
	@echo "Reloading systemd..."
	systemctl daemon-reload
	
	@echo -e "$(GREEN)Service uninstalled successfully!$(NC)"
	@echo "All files have been removed from:"
	@echo "  - $(INSTALL_DIR)"
	@echo "  - /etc/systemd/system/$(SERVICE_FILE)"

package-deb: build ## Create Debian package
	@echo "Creating Debian package..."
	
	# Create directory structure
	mkdir -p $(DEB_DIR)/DEBIAN
	mkdir -p $(DEB_DIR)/opt/$(BINARY_NAME)
	mkdir -p $(DEB_DIR)/etc/systemd/system
	mkdir -p $(DEB_DIR)/usr/share/doc/$(BINARY_NAME)
	
	# Copy binary
	cp target/release/$(BINARY_NAME) $(DEB_DIR)/opt/$(BINARY_NAME)/
	chmod 700 $(DEB_DIR)/opt/$(BINARY_NAME)/$(BINARY_NAME)
	
	# Copy service file
	sed -e "s|{{BINARY_PATH}}|/opt/$(BINARY_NAME)/$(BINARY_NAME)|g" \
	    -e "s|{{VM_ID}}|100|g" \
	    $(SERVICE_FILE) > $(DEB_DIR)/etc/systemd/system/$(SERVICE_FILE)
	
	# Copy documentation
	cp CLAUDE.md $(DEB_DIR)/usr/share/doc/$(BINARY_NAME)/README.md
	
	# Create control file
	@echo "Package: $(BINARY_NAME)" > $(DEB_DIR)/DEBIAN/control
	@echo "Version: $(VERSION)" >> $(DEB_DIR)/DEBIAN/control
	@echo "Section: utils" >> $(DEB_DIR)/DEBIAN/control
	@echo "Priority: optional" >> $(DEB_DIR)/DEBIAN/control
	@echo "Architecture: amd64" >> $(DEB_DIR)/DEBIAN/control
	@echo "Depends: libc6, systemd" >> $(DEB_DIR)/DEBIAN/control
	@echo "Maintainer: Proxmox Wake-on-Joystick Project" >> $(DEB_DIR)/DEBIAN/control
	@echo "Description: Wake Proxmox VMs using joystick input" >> $(DEB_DIR)/DEBIAN/control
	@echo " A service that monitors joystick input and wakes up Proxmox virtual machines" >> $(DEB_DIR)/DEBIAN/control
	@echo " when the right trigger (RT) button is pressed. Designed to run directly on" >> $(DEB_DIR)/DEBIAN/control
	@echo " Proxmox hosts with USB passthrough support." >> $(DEB_DIR)/DEBIAN/control
	
	# Create postinst script
	@echo "#!/bin/bash" > $(DEB_DIR)/DEBIAN/postinst
	@echo "set -e" >> $(DEB_DIR)/DEBIAN/postinst
	@echo "" >> $(DEB_DIR)/DEBIAN/postinst
	@echo "# Set correct ownership and permissions" >> $(DEB_DIR)/DEBIAN/postinst
	@echo "chown root:root /opt/$(BINARY_NAME)/$(BINARY_NAME)" >> $(DEB_DIR)/DEBIAN/postinst
	@echo "chmod 700 /opt/$(BINARY_NAME)/$(BINARY_NAME)" >> $(DEB_DIR)/DEBIAN/postinst
	@echo "" >> $(DEB_DIR)/DEBIAN/postinst
	@echo "# Reload systemd" >> $(DEB_DIR)/DEBIAN/postinst
	@echo "systemctl daemon-reload" >> $(DEB_DIR)/DEBIAN/postinst
	@echo "" >> $(DEB_DIR)/DEBIAN/postinst
	@echo 'echo "Proxmox Wake-on-Joystick installed successfully!"' >> $(DEB_DIR)/DEBIAN/postinst
	@echo 'echo "To configure and start the service:"' >> $(DEB_DIR)/DEBIAN/postinst
	@echo 'echo "1. Edit /etc/systemd/system/$(SERVICE_FILE)"' >> $(DEB_DIR)/DEBIAN/postinst
	@echo 'echo "2. Change PROXMOX_VM_ID=100 to your desired VM ID"' >> $(DEB_DIR)/DEBIAN/postinst
	@echo 'echo "3. Run: systemctl enable $(BINARY_NAME)"' >> $(DEB_DIR)/DEBIAN/postinst
	@echo 'echo "4. Run: systemctl start $(BINARY_NAME)"' >> $(DEB_DIR)/DEBIAN/postinst
	chmod 755 $(DEB_DIR)/DEBIAN/postinst
	
	# Create prerm script
	@echo "#!/bin/bash" > $(DEB_DIR)/DEBIAN/prerm
	@echo "set -e" >> $(DEB_DIR)/DEBIAN/prerm
	@echo "" >> $(DEB_DIR)/DEBIAN/prerm
	@echo "# Stop and disable service if running" >> $(DEB_DIR)/DEBIAN/prerm
	@echo "if systemctl is-active --quiet $(BINARY_NAME); then" >> $(DEB_DIR)/DEBIAN/prerm
	@echo "    systemctl stop $(BINARY_NAME)" >> $(DEB_DIR)/DEBIAN/prerm
	@echo "fi" >> $(DEB_DIR)/DEBIAN/prerm
	@echo "" >> $(DEB_DIR)/DEBIAN/prerm
	@echo "if systemctl is-enabled --quiet $(BINARY_NAME); then" >> $(DEB_DIR)/DEBIAN/prerm
	@echo "    systemctl disable $(BINARY_NAME)" >> $(DEB_DIR)/DEBIAN/prerm
	@echo "fi" >> $(DEB_DIR)/DEBIAN/prerm
	chmod 755 $(DEB_DIR)/DEBIAN/prerm
	
	# Create postrm script
	@echo "#!/bin/bash" > $(DEB_DIR)/DEBIAN/postrm
	@echo "set -e" >> $(DEB_DIR)/DEBIAN/postrm
	@echo "" >> $(DEB_DIR)/DEBIAN/postrm
	@echo "# Reload systemd after removal" >> $(DEB_DIR)/DEBIAN/postrm
	@echo "systemctl daemon-reload" >> $(DEB_DIR)/DEBIAN/postrm
	chmod 755 $(DEB_DIR)/DEBIAN/postrm
	
	# Build the package
	dpkg-deb --build $(DEB_DIR) $(BINARY_NAME)_$(VERSION)_amd64.deb
	
	@echo -e "$(GREEN)Debian package created: $(BINARY_NAME)_$(VERSION)_amd64.deb$(NC)"

package-deb-docker: ## Create Debian package using Docker
	@echo "Building Debian package in Docker..."
	
	# Create output directory
	mkdir -p output
	
	# Create Dockerfile
	@echo "FROM ubuntu:22.04" > Dockerfile
	@echo "" >> Dockerfile
	@echo "# Install build dependencies" >> Dockerfile
	@echo "RUN apt-get update && apt-get install -y \\" >> Dockerfile
	@echo "    curl \\" >> Dockerfile
	@echo "    build-essential \\" >> Dockerfile
	@echo "    libudev-dev \\" >> Dockerfile
	@echo "    pkg-config \\" >> Dockerfile
	@echo "    dpkg-dev \\" >> Dockerfile
	@echo "    && rm -rf /var/lib/apt/lists/*" >> Dockerfile
	@echo "" >> Dockerfile
	@echo "# Install Rust" >> Dockerfile
	@echo "RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y" >> Dockerfile
	@echo "ENV PATH=\"/root/.cargo/bin:\$${PATH}\"" >> Dockerfile
	@echo "" >> Dockerfile
	@echo "# Set working directory" >> Dockerfile
	@echo "WORKDIR /app" >> Dockerfile
	@echo "" >> Dockerfile
	@echo "# Copy project files" >> Dockerfile
	@echo "COPY . ." >> Dockerfile
	@echo "" >> Dockerfile
	@echo "# Build and package" >> Dockerfile
	@echo "RUN make check build package-deb VERSION=$(VERSION)" >> Dockerfile
	@echo "" >> Dockerfile
	@echo "# List built packages" >> Dockerfile
	@echo "RUN ls -la *.deb" >> Dockerfile
	
	# Build Docker image
	docker build -t $(BINARY_NAME)-builder .
	
	# Run container to build package and copy output
	docker run --rm \
		-v "$$(pwd)/output:/output" \
		$(BINARY_NAME)-builder \
		sh -c "cp *.deb /output/"
	
	# Clean up
	rm -f Dockerfile
	
	@echo -e "$(GREEN)Debian package built successfully in Docker!$(NC)"
	@ls -la output/

clean: ## Clean build artifacts and temporary files
	cargo clean
	rm -rf $(DEB_DIR)
	rm -f $(BINARY_NAME)_*.deb
	rm -f $(BINARY_NAME)
	rm -rf output
	rm -f Dockerfile

deps: ## Install system dependencies for building
	@echo "Installing system dependencies..."
	sudo apt-get update
	sudo apt-get install -y libudev-dev pkg-config build-essential

all: check build ## Run checks and build

release: check build package-deb ## Create a full release (check, build, package)
	@echo -e "$(GREEN)Release package created successfully!$(NC)"