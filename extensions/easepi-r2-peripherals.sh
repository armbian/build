# EasePi R2 Peripherals Extension (IR + Bluetooth)
# 注意：此扩展仅适用于 EasePi-R2 (RK3588)
# EasePi-R2 硬件特性：
#   - 红外接收器
#   - AP6255 蓝牙模块 (ttyS9)
#   - 无 OLED 显示屏
#
# 此扩展已整合 bluetooth-hciattach 功能，无需单独启用
# EasePi-A2 有 OLED 显示屏，请使用 easepi-a2-peripherals.sh

function extension_prepare_config__easepi-r2-peripherals() {
	display_alert "Extension: EasePi R2 Peripherals" "Preparing IR + Bluetooth support" "info"

	if [[ -z "${BLUETOOTH_HCIATTACH_PARAMS}" ]]; then
		exit_with_error "EasePi-R2 Peripherals: BLUETOOTH_HCIATTACH_PARAMS is not set - please set in the board file."
	fi
	if [[ -z "${BLUETOOTH_HCIATTACH_RKFILL_NUM}" ]]; then
		declare -g BLUETOOTH_HCIATTACH_RKFILL_NUM=0
	fi
}

function post_family_config__easepi_r2_add_bluetooth_packages() {
	display_alert "EasePi-R2" "Adding bluetooth packages to image" "info"
	add_packages_to_image rfkill bluetooth bluez bluez-tools
}

function post_family_config__easepi_r2_add_ir_packages() {
	display_alert "EasePi-R2" "Adding IR packages to image" "info"
	add_packages_to_image i2c-tools ir-keytable
}

function post_family_tweaks_bsp__easepi_r2_bluetooth_hciattach_service() {
	display_alert "EasePi-R2" "Adding bluetooth hciattach service to BSP" "info"
	: "${destination:?destination is not set}"

	declare script_dir="/usr/local/sbin"
	run_host_command_logged mkdir -pv "${destination}${script_dir}"
	declare script_path="${script_dir}/bluetooth-hciattach.sh"

	cat <<- BT_HCIATTACH_SCRIPT > "${destination}${script_path}"
		#!/bin/bash
		rfkill unblock ${BLUETOOTH_HCIATTACH_RKFILL_NUM}
		if hciconfig hci0 up 2>/dev/null; then
			echo "Bluetooth hci0 already initialized by kernel driver"
			exit 0
		fi
		sleep 1
		hciattach -n ${BLUETOOTH_HCIATTACH_PARAMS}
	BT_HCIATTACH_SCRIPT
	run_host_command_logged chmod -v +x "${destination}${script_path}"

	cat <<- BT_HCIATTACH_SYSTEMD_SERVICE > "$destination"/lib/systemd/system/bluetooth-hciattach.service
		[Unit]
		Description=${BOARD} Bluetooth HCIAttach fix
		After=network.target
		StartLimitIntervalSec=0
		[Service]
		Type=simple
		ExecStart=${script_path}

		[Install]
		WantedBy=multi-user.target
	BT_HCIATTACH_SYSTEMD_SERVICE

	return 0
}

function pre_customize_image__copy_easepi_r2_files() {
	display_alert "EasePi-R2" "Writing R2 peripheral files" "info"

	mkdir -p "${SDCARD}"/usr/local/ir
	mkdir -p "${SDCARD}"/usr/local/sbin
	mkdir -p "${SDCARD}"/etc/systemd/system
	mkdir -p "${SDCARD}"/etc/modules-load.d
	mkdir -p "${SDCARD}"/etc/rc_keymaps

	# =============================================
	# IR Keymap Service (systemd unit) — R2 specific
	# =============================================
	cat <<'EOF' > "${SDCARD}"/etc/systemd/system/ir-keymap.service
[Unit]
Description=Apply IR keymap configuration
After=sysinit.target
ConditionPathExists=/dev/lirc0

[Service]
Type=oneshot
ExecStart=/bin/bash -c "/usr/bin/ir-keytable -c -w /etc/rc_keymaps/easepi_remote && /usr/bin/ir-keytable -p nec"
# 异常自动重启
Restart=on-failure
# 重启间隔3秒
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

	# =============================================
	# IR Keymap service (R2 uses inline exec, no separate setup script)
	# =============================================

	# =============================================
	# Infrared module config — R2 specific (includes lirc_dev, lirc_i2c)
	# =============================================
	cat <<'EOF' > "${SDCARD}"/etc/modules-load.d/infrared.conf
gpio_ir_recv
ir_nec_decoder
lirc_dev
lirc_i2c
EOF

	# =============================================
	# IR Remote Keymap
	# =============================================
	cat <<'EOF' > "${SDCARD}"/etc/rc_keymaps/easepi_remote
# table easepi_remote, type: nec
0x22dc KEY_POWER
0x2282 KEY_MENU
0x22ca KEY_UP
0x22d2 KEY_DOWN
0x2299 KEY_LEFT
0x22c1 KEY_RIGHT
0x22ce KEY_ENTER
0x2295 KEY_BACK
0x2288 KEY_HOME
0x2280 KEY_VOLUMEUP
0x2281 KEY_VOLUMEDOWN
0x2287 KEY_0
0x2292 KEY_1
0x2293 KEY_2
0x22cc KEY_3
0x228e KEY_4
0x228f KEY_5
0x22c8 KEY_6
0x228a KEY_7
0x228b KEY_8
0x22c4 KEY_9
0x228d KEY_SETUP
0x2285 KEY_PAGEUP
0x2286 KEY_PAGEDOWN
EOF

	# =============================================
	# IR Diagnostic Tool (fix_infrared.sh)
	# =============================================
	cat <<'FIXIRSCRIPT' > "${SDCARD}"/usr/local/ir/fix_infrared.sh
#!/bin/bash
# EasePi A2 红外功能诊断和配置工具
# 用于手动诊断和重新配置红外接收功能
# 使用方法：sudo bash /usr/local/ir/fix_infrared.sh

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
        log_error "请以root权限运行此脚本（sudo bash ${SCRIPT_DIR}/fix_infrared.sh）"
        exit 1
    fi
}

check_files() {
    log_info "检查红外相关文件..."
    if [ ! -f "${SERVICE_FILE}" ]; then
        log_error "服务文件缺失：${SERVICE_FILE}"
        exit 1
    fi
    if [ ! -f "/etc/modules-load.d/infrared.conf" ]; then
        log_error "模块配置文件缺失：/etc/modules-load.d/infrared.conf"
        exit 1
    fi
    if [ ! -f "/etc/rc_keymaps/easepi_remote" ]; then
        log_error "按键映射文件缺失：/etc/rc_keymaps/easepi_remote"
        exit 1
    fi
    log_info "✓ 文件检查通过"
}

check_deps() {
    log_info "检查系统依赖..."
    if ! command -v ir-keytable &> /dev/null; then
        log_warn "ir-keytable 未安装"
        log_info "正在安装..."
        apt-get update -y >> ${LOG_FILE} 2>&1
        apt-get install -y --no-install-recommends ir-keytable >> ${LOG_FILE} 2>&1
        if [ $? -eq 0 ]; then
            log_info "✓ ir-keytable 安装成功"
        else
            log_error "✗ 安装失败"
            exit 1
        fi
    else
        log_info "✓ ir-keytable 已安装"
    fi
}

check_modules() {
    log_info "检查内核模块..."
    modules=("gpio_ir_recv" "ir_nec_decoder")
    for mod in "${modules[@]}"; do
        if lsmod | grep -q "^${mod} "; then
            log_info "✓ ${mod} 已加载"
        else
            log_warn "⚠ ${mod} 未加载"
            log_info "正在加载模块..."
            modprobe ${mod} >> ${LOG_FILE} 2>&1
            if [ $? -eq 0 ]; then
                log_info "✓ ${mod} 加载成功"
            else
                log_error "✗ ${mod} 加载失败"
            fi
        fi
    done
}

check_device() {
    log_info "检查红外设备..."
    if [ -c "/dev/lirc0" ]; then
        log_info "✓ /dev/lirc0 设备节点存在"
    else
        log_error "✗ /dev/lirc0 设备节点不存在"
        log_warn "请检查硬件连接或设备树配置"
    fi
}

check_protocol() {
    log_info "检查红外协议..."
    PROTOCOLS=$(ir-keytable 2>&1 | grep "Enabled kernel protocols" || true)
    if [ -n "$PROTOCOLS" ]; then
        log_info "当前协议: $PROTOCOLS"
    fi
    if echo "$PROTOCOLS" | grep -q "nec"; then
        log_info "✓ NEC 协议已启用"
    else
        log_warn "⚠ NEC 协议未启用"
        log_info "正在启用 NEC 协议..."
        ir-keytable -p nec >> ${LOG_FILE} 2>&1
        if [ $? -eq 0 ]; then
            log_info "✓ NEC 协议启用成功"
        else
            log_error "✗ NEC 协议启用失败"
        fi
    fi
}

check_keymap() {
    log_info "检查按键映射..."
    if ir-keytable -c -w /etc/rc_keymaps/easepi_remote >> ${LOG_FILE} 2>&1; then
        log_info "✓ 按键映射应用成功"
    else
        log_warn "⚠ 按键映射应用失败"
    fi
}

check_service() {
    log_info "检查红外服务状态..."
    if systemctl is-active --quiet ir-keymap.service; then
        log_info "✓ ir-keymap.service 已执行"
    else
        log_warn "⚠ ir-keymap.service 未执行"
        log_info "正在执行服务..."
        systemctl start ir-keymap.service
        if [ $? -eq 0 ]; then
            log_info "✓ 服务执行成功"
        else
            log_warn "⚠ 服务执行失败"
        fi
    fi
    if systemctl is-enabled --quiet ir-keymap.service; then
        log_info "✓ 服务已设置开机自启"
    else
        log_warn "⚠ 服务未设置开机自启"
        log_info "正在设置开机自启..."
        systemctl enable ir-keymap.service
    fi
}

show_commands() {
    echo -e "\n${GREEN}=== 红外功能诊断和配置工具 ===${NC}"
    echo -e "\n${YELLOW}📌 常用管理命令：${NC}"
    echo -e "  • 查看服务状态：  systemctl status ir-keymap.service"
    echo -e "  • 重启服务：      systemctl restart ir-keymap.service"
    echo -e "  • 停止服务：      systemctl stop ir-keymap.service"
    echo -e "  • 查看日志：      tail -f /var/log/ir/ir.log"
    echo -e "  • 测试红外信号：  ir-keytable -t"
    echo -e "  • 查看协议配置：  ir-keytable"
    echo -e "\n${YELLOW}🔧 此工具功能：${NC}"
    echo -e "  • 检查文件完整性"
    echo -e "  • 检查并安装依赖"
    echo -e "  • 检查内核模块"
    echo -e "  • 检查设备节点"
    echo -e "  • 检查并配置协议"
    echo -e "  • 检查服务状态"
    echo -e ""
}

main() {
    clear
    show_commands
    echo -e "${GREEN}开始诊断...${NC}\n"
    
    check_root
    check_files
    check_deps
    check_modules
    check_device
    check_protocol
    check_keymap
    check_service
    
    echo -e "\n${GREEN}=== 诊断完成 ===${NC}"
    echo -e "${YELLOW}是否要测试红外信号接收？(y/n)${NC}"
    echo -e "${YELLOW}(按 Ctrl+C 退出测试)${NC}"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo -e "${GREEN}请按下遥控器按键...${NC}"
        ir-keytable -t
    fi
}

main
FIXIRSCRIPT

	# =============================================
	# 设置脚本权限
	# =============================================
	chmod +x "${SDCARD}"/usr/local/ir/fix_infrared.sh 2>/dev/null || true
}

function post_customize_image__enable_easepi_r2_services() {
	display_alert "EasePi-R2" "Enabling R2 peripheral services" "info"

	# Enable IR service
	chroot_sdcard systemctl enable ir-keymap.service || true

	# Enable Bluetooth service
	chroot_sdcard systemctl enable bluetooth-hciattach.service || true
	chroot_sdcard systemctl enable bluetooth.service || true
}