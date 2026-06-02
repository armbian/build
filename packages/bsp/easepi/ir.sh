#!/bin/bash
# EasePi IR Management Script
# Combined and optimized IR setup and diagnostic tool
#
# Usage:
#   bash ir.sh              # Interactive diagnostic mode
#   bash ir.sh --quick      # Quick setup mode (for service)
#   bash ir.sh --help         # Show help

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="/usr/local/ir"
SERVICE_FILE="/etc/systemd/system/ir.service"
LOG_DIR="/var/log/ir"
LOG_FILE="${LOG_DIR}/ir.log"
KEYMAP_FILE="/etc/rc_keymaps/ir_remote"
MODULES_CONF="/etc/modules-load.d/ir.conf"

QUICK_MODE=false
INTERACTIVE=true

log_info() {
	if [ "$INTERACTIVE" = true ]; then
		echo -e "${GREEN}[INFO]${NC} $1"
	fi
	if [ -d "${LOG_DIR}" ]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') - INFO - $1" >> ${LOG_FILE} 2>/dev/null || true
	fi
}

log_warn() {
	if [ "$INTERACTIVE" = true ]; then
		echo -e "${YELLOW}[WARN]${NC} $1"
	fi
	if [ -d "${LOG_DIR}" ]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') - WARN - $1" >> ${LOG_FILE} 2>/dev/null || true
	fi
}

log_error() {
	if [ "$INTERACTIVE" = true ]; then
		echo -e "${RED}[ERROR]${NC} $1"
	fi
	if [ -d "${LOG_DIR}" ]; then
		echo "$(date +'%Y-%m-%d %H:%M:%S') - ERROR - $1" >> ${LOG_FILE} 2>/dev/null || true
	fi
}

check_root() {
	if [ "$EUID" -ne 0 ] && [ "$INTERACTIVE" = true ]; then
		log_error "Please run this script with root privileges (sudo bash ${SCRIPT_DIR}/ir.sh)"
		exit 1
	fi
}

quick_setup() {
	for dev in /dev/lirc* /sys/class/rc/*; do
		if [ -e "$dev" ]; then
			log_info "Found IR device: $dev"
			/usr/bin/ir-keytable -c -w "$KEYMAP_FILE" 2>/dev/null
			/usr/bin/ir-keytable -p nec 2>/dev/null
			exit 0
		fi
	done
	log_warn "No IR device found"
	exit 0
}

check_files() {
	log_info "Checking IR related files..."
	if [ ! -f "${SERVICE_FILE}" ]; then
		log_error "Service file missing: ${SERVICE_FILE}"
		return 1
	fi
	if [ ! -f "${MODULES_CONF}" ]; then
		log_error "Module config file missing: ${MODULES_CONF}"
		return 1
	fi
	if [ ! -f "${KEYMAP_FILE}" ]; then
		log_error "Keymap file missing: ${KEYMAP_FILE}"
		return 1
	fi
	log_info "File check passed"
	return 0
}

check_deps() {
	log_info "Checking system dependencies..."
	if ! command -v ir-keytable &> /dev/null; then
		log_warn "ir-keytable not installed"
		if [ "$INTERACTIVE" = true ]; then
			log_info "Installing..."
			apt-get update -y >> ${LOG_FILE} 2>&1
			apt-get install -y --no-install-recommends ir-keytable >> ${LOG_FILE} 2>&1
			if [ $? -eq 0 ]; then
				log_info "ir-keytable installed successfully"
			else
				log_error "Installation failed"
				return 1
			fi
		fi
	else
		log_info "ir-keytable already installed"
	fi
	return 0
}

check_modules() {
	log_info "Checking kernel modules..."
	if [ ! -f "${MODULES_CONF}" ]; then
		return
	fi

	local modules=()
	local line
	while IFS= read -r line; do
		line="${line%%#*}"
		line="${line// /}"
		if [ -n "$line" ]; then
			modules+=("$line")
		fi
	done < "${MODULES_CONF}"

	if [ ${#modules[@]} -eq 0 ]; then
		log_warn "No module entries found"
		return
	fi

	log_info "Found ${#modules[@]} module(s): ${modules[*]}"

	for mod in "${modules[@]}"; do
		if lsmod | grep -q "^${mod} "; then
			log_info "${mod} loaded"
		else
			log_warn "${mod} not loaded"
			if [ "$INTERACTIVE" = true ]; then
				log_info "Loading module..."
				modprobe ${mod} >> ${LOG_FILE} 2>&1
				if [ $? -eq 0 ]; then
					log_info "${mod} loaded successfully"
				else
					log_error "${mod} failed to load"
				fi
			fi
		fi
	done
}

check_device() {
	log_info "Checking IR device..."
	if [ -c "/dev/lirc0" ]; then
		log_info "/dev/lirc0 device node exists"
		return 0
	fi

	local found=false
	local dev
	for dev in /dev/lirc*; do
		if [ -c "$dev" ]; then
			log_info "Found IR device: $dev"
			found=true
		fi
	done
	for dev in /sys/class/rc/*; do
		if [ -d "$dev" ]; then
			log_info "Found RC device: $dev ($(cat "$dev/name" 2>/dev/null || echo 'unknown'))"
			found=true
		fi
	done

	if [ "$found" = false ]; then
		log_error "No IR device found (check hardware connection or device tree configuration)"
		return 1
	fi
	return 0
}

apply_keymap() {
	log_info "Applying keymap and protocol..."
	if ir-keytable -c -w "${KEYMAP_FILE}" >> ${LOG_FILE} 2>&1; then
		log_info "Keymap applied successfully"
	else
		log_warn "Keymap application failed"
		return 1
	fi

	if ir-keytable -p nec >> ${LOG_FILE} 2>&1; then
		log_info "NEC protocol enabled"
	else
		log_warn "Failed to enable NEC protocol"
		return 1
	fi
	return 0
}

check_service() {
	log_info "Checking IR service status..."
	if systemctl is-active --quiet ir.service; then
		log_info "ir.service is active"
	else
		log_warn "ir.service is inactive"
		if [ "$INTERACTIVE" = true ]; then
			log_info "Starting service..."
			systemctl start ir.service
			if [ $? -eq 0 ]; then
				log_info "Service started successfully"
			else
				log_warn "Service start failed"
			fi
		fi
	fi

	if [ "$INTERACTIVE" = true ] && ! systemctl is-enabled --quiet ir.service; then
		log_warn "Service not enabled for auto-start"
		log_info "Enabling auto-start..."
		systemctl enable ir.service
	fi
}

show_commands() {
	echo -e "\n${GREEN}=== EasePi IR Management Tool ===${NC}"
	echo -e "\n${YELLOW}Common management commands:${NC}"
	echo -e "  Quick setup:         ${SCRIPT_DIR}/ir.sh --quick"
	echo -e "  View service status: systemctl status ir.service"
	echo -e "  Restart service:     systemctl restart ir.service"
	echo -e "  Stop service:        systemctl stop ir.service"
	echo -e "  View logs:           tail -f ${LOG_FILE}"
	echo -e "  Test IR signals:     ir-keytable -t"
	echo -e "  View protocol cfg:   ir-keytable"
}

show_help() {
	echo "EasePi IR Management Script"
	echo ""
	echo "Usage: $(basename "$0") [OPTIONS]"
	echo ""
	echo "Options:"
	echo "  --quick      Quick setup mode (for system service, non-interactive)"
	echo "  --help       Show this help message"
	echo "  (no option)  Interactive diagnostic mode"
	echo ""
}

diagnostic_mode() {
	mkdir -p "${LOG_DIR}" 2>/dev/null
	touch "${LOG_FILE}" 2>/dev/null
	chmod 644 "${LOG_FILE}" 2>/dev/null

	clear
	show_commands
	echo -e "\n${GREEN}Starting diagnostics...${NC}\n"

	check_root
	if ! check_files; then
		return
	fi
	check_deps
	check_modules
	check_device
	apply_keymap
	check_service

	echo -e "\n${GREEN}=== Diagnostics Complete ===${NC}"
	echo -e "${YELLOW}Test IR signal reception? (y/n)${NC}"
	read -r response
	if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
		echo -e "${GREEN}Press a remote control button...${NC}"
		echo -e "${YELLOW}(Press Ctrl+C to exit test)${NC}"
		ir-keytable -t
	fi
}

parse_args() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--quick)
				QUICK_MODE=true
				INTERACTIVE=false
				shift
				;;
			--help)
				show_help
				exit 0
				;;
			*)
				echo "Unknown option: $1"
				show_help
				exit 1
				;;
		esac
	done
}

main() {
	parse_args "$@"

	if [ "$QUICK_MODE" = true ]; then
		quick_setup
	else
		diagnostic_mode
	fi
}

main "$@"
