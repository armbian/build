#!/bin/bash
# EasePi IR diagnostic and configuration tool
# Manual diagnosis and reconfiguration of IR receiver
# Usage: sudo bash /usr/local/ir/fix_infrared.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="/usr/local/ir"
SERVICE_FILE="/etc/systemd/system/ir-keymap.service"
LOG_DIR="/var/log/ir"
LOG_FILE="${LOG_DIR}/ir.log"

mkdir -p "${LOG_DIR}"
touch "${LOG_FILE}"
chmod 644 "${LOG_FILE}"

log_info() {
	echo -e "${GREEN}[INFO]${NC} $1"
	echo "$(date +'%Y-%m-%d %H:%M:%S') - INFO - $1" >> ${LOG_FILE} 2>&1
}

log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $1"
	echo "$(date +'%Y-%m-%d %H:%M:%S') - WARN - $1" >> ${LOG_FILE} 2>&1
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1"
	echo "$(date +'%Y-%m-%d %H:%M:%S') - ERROR - $1" >> ${LOG_FILE} 2>&1
}

check_root() {
	if [ "$EUID" -ne 0 ]; then
		log_error "Please run this script with root privileges (sudo bash ${SCRIPT_DIR}/fix_infrared.sh)"
		exit 1
	fi
}

check_files() {
	log_info "Checking IR related files..."
	if [ ! -f "${SERVICE_FILE}" ]; then
		log_error "Service file missing: ${SERVICE_FILE}"
		exit 1
	fi
	if [ ! -f "/etc/modules-load.d/infrared.conf" ]; then
		log_error "Module config file missing: /etc/modules-load.d/infrared.conf"
		exit 1
	fi
	if [ ! -f "/etc/rc_keymaps/easepi_remote" ]; then
		log_error "Keymap file missing: /etc/rc_keymaps/easepi_remote"
		exit 1
	fi
	log_info "File check passed"
}

check_deps() {
	log_info "Checking system dependencies..."
	if ! command -v ir-keytable &> /dev/null; then
		log_warn "ir-keytable not installed"
		log_info "Installing..."
		apt-get update -y >> ${LOG_FILE} 2>&1
		apt-get install -y --no-install-recommends ir-keytable >> ${LOG_FILE} 2>&1
		if [ $? -eq 0 ]; then
			log_info "ir-keytable installed successfully"
		else
			log_error "Installation failed"
			exit 1
		fi
	else
		log_info "ir-keytable already installed"
	fi
}

check_modules() {
	log_info "Checking kernel modules (from /etc/modules-load.d/infrared.conf)..."
	local modules=()
	local line
	while IFS= read -r line; do
		line="${line%%#*}"
		line="${line// /}"
		if [ -n "$line" ]; then
			modules+=("$line")
		fi
	done < /etc/modules-load.d/infrared.conf

	if [ ${#modules[@]} -eq 0 ]; then
		log_warn "No module entries found in infrared.conf"
		return
	fi

	log_info "Found ${#modules[@]} module(s): ${modules[*]}"

	for mod in "${modules[@]}"; do
		if lsmod | grep -q "^${mod} "; then
			log_info "${mod} loaded"
		else
			log_warn "${mod} not loaded"
			log_info "Loading module..."
			modprobe ${mod} >> ${LOG_FILE} 2>&1
			if [ $? -eq 0 ]; then
				log_info "${mod} loaded successfully"
			else
				log_error "${mod} failed to load"
			fi
		fi
	done
}

check_device() {
	log_info "Checking IR device..."
	if [ -c "/dev/lirc0" ]; then
		log_info "/dev/lirc0 device node exists"
		return
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
	fi
}

check_protocol() {
	log_info "Checking IR protocol..."
	PROTOCOLS=$(ir-keytable 2>&1 | grep "Enabled kernel protocols" || true)
	if [ -n "$PROTOCOLS" ]; then
		log_info "Current protocol: $PROTOCOLS"
	fi
	if echo "$PROTOCOLS" | grep -q "nec"; then
		log_info "NEC protocol enabled"
	else
		log_warn "NEC protocol not enabled"
		log_info "Enabling NEC protocol..."
		ir-keytable -p nec >> ${LOG_FILE} 2>&1
		if [ $? -eq 0 ]; then
			log_info "NEC protocol enabled successfully"
		else
			log_error "NEC protocol enable failed"
		fi
	fi
}

check_keymap() {
	log_info "Checking keymap..."
	if ir-keytable -c -w /etc/rc_keymaps/easepi_remote >> ${LOG_FILE} 2>&1; then
		log_info "Keymap applied successfully"
	else
		log_warn "Keymap application failed"
	fi
}

check_service() {
	log_info "Checking IR service status..."
	if systemctl is-active --quiet ir-keymap.service; then
		log_info "ir-keymap.service is active"
	else
		log_warn "ir-keymap.service is inactive"
		log_info "Starting service..."
		systemctl start ir-keymap.service
		if [ $? -eq 0 ]; then
			log_info "Service started successfully"
		else
			log_warn "Service start failed"
		fi
	fi
	if systemctl is-enabled --quiet ir-keymap.service; then
		log_info "Service enabled for auto-start"
	else
		log_warn "Service not enabled for auto-start"
		log_info "Enabling auto-start..."
		systemctl enable ir-keymap.service
	fi
}

show_commands() {
	echo -e "\n${GREEN}=== IR Diagnostic and Configuration Tool ===${NC}"
	echo -e "\n${YELLOW}Common management commands:${NC}"
	echo -e "  View service status:  systemctl status ir-keymap.service"
	echo -e "  Restart service:    systemctl restart ir-keymap.service"
	echo -e "  Stop service:       systemctl stop ir-keymap.service"
	echo -e "  View logs:          tail -f /var/log/ir/ir.log"
	echo -e "  Test IR signals:    ir-keytable -t"
	echo -e "  View protocol cfg:  ir-keytable"
	echo -e "\n${YELLOW}Tool features:${NC}"
	echo -e "  Check file integrity"
	echo -e "  Check and install dependencies"
	echo -e "  Check kernel modules"
	echo -e "  Check device nodes"
	echo -e "  Check and configure protocol"
	echo -e "  Check service status"
	echo -e ""
}

main() {
	clear
	show_commands
	echo -e "${GREEN}Starting diagnostics...${NC}\n"

	check_root
	check_files
	check_deps
	check_modules
	check_device
	check_protocol
	check_keymap
	check_service

	echo -e "\n${GREEN}=== Diagnostics Complete ===${NC}"
	echo -e "${YELLOW}Test IR signal reception? (y/n)${NC}"
	echo -e "${YELLOW}(Press Ctrl+C to exit test)${NC}"
	read -r response
	if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
		echo -e "${GREEN}Press a remote control button...${NC}"
		ir-keytable -t
	fi
}

main