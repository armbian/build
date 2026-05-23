# EasePi A2 Peripherals Extension (OLED + IR + Bluetooth)
# 注意：此扩展仅适用于 EasePi-A2 (RK3568)
# EasePi-A2 硬件特性：
#   - SSD1306 OLED 显示屏
#   - 红外接收器
#   - AP6255 蓝牙模块 (uart8/serial@fe6c0000, alias serial0->ttyS0)
#
# 分支适配说明：
#   - vendor:  内核使用 bluetooth-platdata 驱动，需用户态 hciattach 初始化蓝牙
#   - current/edge: 主线内核 serdev 自动初始化蓝牙，无需 hciattach
#   - OLED/IR: 所有分支通用（Go 程序通过 /dev/i2c-3 直接操作硬件）
#
# 此扩展已整合 bluetooth-hciattach 功能，无需单独启用


function extension_prepare_config__easepi-a2-peripherals() {
	display_alert "Extension: EasePi A2 Peripherals" "Preparing OLED + IR + Bluetooth support (BRANCH=${BRANCH})" "info"

	# vendor 分支需要 hciattach；主线内核 serdev 自动处理，仅做软校验
	if [[ "${BRANCH}" == "vendor" ]]; then
		display_alert "EasePi-A2" "Vendor kernel: hciattach bluetooth init will be configured" "info"
		if [[ -z "${BLUETOOTH_HCIATTACH_PARAMS}" ]]; then
			exit_with_error "EasePi-A2 Peripherals (vendor): BLUETOOTH_HCIATTACH_PARAMS is not set"
		fi
	else
		display_alert "EasePi-A2" "Mainline kernel: Bluetooth will be handled by kernel serdev, skipping hciattach" "info"
	fi

	if [[ -z "${BLUETOOTH_HCIATTACH_RKFILL_NUM}" ]]; then
		declare -g BLUETOOTH_HCIATTACH_RKFILL_NUM=0
	fi
}

function post_family_config__easepi_a2_add_bluetooth_packages() {
	display_alert "EasePi-A2" "Adding bluetooth packages to image" "info"
	add_packages_to_image rfkill bluetooth bluez bluez-tools
}

function post_family_config__easepi_a2_add_oled_packages() {
	display_alert "EasePi-A2" "Adding OLED + IR packages to image" "info"
	add_packages_to_image i2c-tools ir-keytable fonts-dejavu-core
}

function add_host_dependencies__easepi_a2_add_golang() {
	display_alert "EasePi-A2" "Adding golang host dependency for OLED build" "info"
	declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} golang-go"
}

function post_family_tweaks_bsp__easepi_a2_bluetooth_hciattach_service() {
	: "${destination:?destination is not set}"

	# 仅 vendor 分支生成 hciattach 服务
	# 主线内核通过 serdev (compatible = "brcm,bcm4345c5") 自动初始化蓝牙
	if [[ "${BRANCH}" != "vendor" ]]; then
		display_alert "EasePi-A2" "Skipping hciattach service (mainline kernel serdev handles Bluetooth)" "info"
		return 0
	fi

	display_alert "EasePi-A2" "Generating bluetooth hciattach service (vendor kernel)" "info"

	declare script_dir="/usr/local/sbin"
	run_host_command_logged mkdir -pv "${destination}${script_dir}"
	declare script_path="${script_dir}/bluetooth-hciattach.sh"

	# vendor 内核使用 bluetooth-platdata rfkill 驱动控制 GPIO
	# 初始化顺序：1) rfkill unblock 触发驱动拉高 BT_EN/RESET
	#             2) 等待芯片上电稳定
	#             3) hciattach 建立 HCI 通道
	cat <<- BT_HCIATTACH_SCRIPT > "${destination}${script_path}"
		#!/bin/bash
		set -e

		echo "[BT] Initializing AP6255 Bluetooth (vendor kernel)"

		# 先尝试内核是否已通过 serdev 初始化（兼容未来可能的内核升级）
		if hciconfig hci0 up 2>/dev/null; then
			echo "[BT] hci0 already initialized by kernel serdev"
			exit 0
		fi

		# rfkill unblock 触发 bluetooth-platdata 驱动：
		#   - 拉高 BT_REG_ON (GPIO4_C4) 使能芯片
		#   - 配置 BT_WAKE (GPIO0_D5)
		#   - 注册 BT_HOST_WAKE (GPIO0_D4) 中断
		rfkill unblock ${BLUETOOTH_HCIATTACH_RKFILL_NUM}
		sleep 1

		# 确保 bt_default rfkill 已 unblock
		if [ -d /sys/class/rfkill/rfkill0 ]; then
			echo 1 > /sys/class/rfkill/rfkill0/state 2>/dev/null || true
		fi
		sleep 1

		echo "[BT] Attaching hciattach on ${BLUETOOTH_HCIATTACH_PARAMS}"
		exec hciattach -n ${BLUETOOTH_HCIATTACH_PARAMS}
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

function pre_customize_image__copy_easepi_a2_files() {
	display_alert "EasePi-A2" "Writing A2 peripheral files (BRANCH=${BRANCH})" "info"

	# 扩展自身目录（用于查找配套资源文件）
	local EXT_DIR="$(dirname "${BASH_SOURCE[0]}")"

	mkdir -p "${SDCARD}"/usr/local/oled
	mkdir -p "${SDCARD}"/usr/local/ir
	mkdir -p "${SDCARD}"/usr/local/sbin
	mkdir -p "${SDCARD}"/etc/systemd/system
	mkdir -p "${SDCARD}"/etc/modules-load.d
	mkdir -p "${SDCARD}"/etc/rc_keymaps

	# =============================================
	# OLED Service (systemd unit)
	# =============================================
	cat <<'EOF' > "${SDCARD}"/etc/systemd/system/oled.service
[Unit]
Description=EasePi A2 OLED Display (Go)
After=network.target
StartLimitIntervalSec=0
ConditionPathExists=/dev/i2c-3

[Service]
Type=simple
ExecStart=/usr/local/oled/oled --silent
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

	# =============================================
	# IR Keymap Service (systemd unit)
	# =============================================
	cat <<'EOF' > "${SDCARD}"/etc/systemd/system/ir-keymap.service
[Unit]
Description=Apply IR keymap configuration
After=sysinit.target

[Service]
Type=oneshot
ExecStart=/usr/local/ir/ir-setup.sh
# 异常自动重启
Restart=on-failure
# 重启间隔3秒
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

	# =============================================
	# Infrared module config
	# =============================================
	cat <<'EOF' > "${SDCARD}"/etc/modules-load.d/infrared.conf
gpio_ir_recv
ir_nec_decoder
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
	# IR Setup Script
	# =============================================
	cat <<'EOF' > "${SDCARD}"/usr/local/ir/ir-setup.sh
#!/bin/bash
# EasePi A2 红外设备设置脚本

echo "检测红外设备..."

for dev in /dev/lirc* /sys/class/rc/*; do
    if [ -e "$dev" ]; then
        echo "找到红外设备: $dev"
        /usr/bin/ir-keytable -c -w /etc/rc_keymaps/easepi_remote
        /usr/bin/ir-keytable -p nec
        exit 0
    fi
done

echo "未找到红外设备（可能需要检查设备树配置）"
exit 0  # 即使没有设备也不报错
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
	# OLED Init Script
	# =============================================
	cat <<'OLEDINIT' > "${SDCARD}"/usr/local/oled/oled_init.sh
#!/bin/bash
# EasePi A2 OLED 128x32 诊断和配置工具 (Go)
# 使用方法：sudo bash /usr/local/oled/oled_init.sh

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="/usr/local/oled"
OLED_BIN="${SCRIPT_DIR}/oled"
FONT_FILE="${SCRIPT_DIR}/DejaVuSansMono.ttf"
SERVICE_FILE="/etc/systemd/system/oled.service"

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} 请以 root 权限运行此脚本（sudo bash ${SCRIPT_DIR}/oled_init.sh）"
        exit 1
    fi
}

check_files() {
    echo -e "${GREEN}[INFO]${NC} 检查 OLED 相关文件..."
    if [ ! -f "${OLED_BIN}" ]; then
        echo -e "${RED}[ERROR]${NC} 程序缺失：${OLED_BIN}"
        exit 1
    fi
    if [ ! -x "${OLED_BIN}" ]; then
        echo -e "${GREEN}[INFO]${NC} 为 oled 添加执行权限"
        chmod +x "${OLED_BIN}"
    fi
    if [ ! -f "${FONT_FILE}" ]; then
        echo -e "${RED}[ERROR]${NC} 字体缺失：${FONT_FILE}"
        exit 1
    fi
    if [ ! -f "${SERVICE_FILE}" ]; then
        echo -e "${RED}[ERROR]${NC} 服务文件缺失：${SERVICE_FILE}"
        exit 1
    fi
    echo -e "${GREEN}[INFO]${NC} ✓ 文件检查通过"
}

check_deps() {
    echo -e "${GREEN}[INFO]${NC} 检查系统依赖..."
    if ! command -v i2cdetect &>/dev/null; then
        echo -e "${YELLOW}[WARN]${NC} 缺失 i2c-tools，正在安装..."
        apt-get update -y -qq
        apt-get install -y --no-install-recommends i2c-tools
    else
        echo -e "${GREEN}[INFO]${NC} ✓ i2c-tools 已安装"
    fi
}

check_i2c() {
    echo -e "${GREEN}[INFO]${NC} 检查 I2C 总线和 OLED 设备..."
    if ! lsmod | grep -q "i2c_dev"; then
        echo -e "${GREEN}[INFO]${NC} 加载 i2c-dev 模块"
        modprobe i2c-dev 2>/dev/null
    fi
    if [ -e "/dev/i2c-3" ]; then
        echo -e "${GREEN}[INFO]${NC} ✓ i2c-3 设备节点存在"
        chmod 666 /dev/i2c-3 2>/dev/null
    else
        echo -e "${RED}[ERROR]${NC} ✗ i2c-3 设备节点不存在"
        exit 1
    fi
    if i2cdetect -y 3 2>/dev/null | grep -q "3c\|3d"; then
        echo -e "${GREEN}[INFO]${NC} ✓ 在 i2c-3 上发现 OLED 设备"
    else
        echo -e "${YELLOW}[WARN]${NC} ⚠ 未检测到 OLED 设备，请检查硬件连接"
        i2cdetect -y 3
    fi
}

check_service() {
    echo -e "${GREEN}[INFO]${NC} 检查 OLED 服务状态..."
    if systemctl is-active --quiet oled.service; then
        echo -e "${GREEN}[INFO]${NC} ✓ oled.service 正在运行"
    else
        echo -e "${YELLOW}[WARN]${NC} ⚠ oled.service 未运行"
        echo -e "${GREEN}[INFO]${NC} 正在启动服务..."
        systemctl start oled.service
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}[INFO]${NC} ✓ 服务启动成功"
        else
            echo -e "${RED}[ERROR]${NC} ✗ 服务启动失败"
            journalctl -u oled.service -n 20 --no-pager
        fi
    fi
    if systemctl is-enabled --quiet oled.service 2>/dev/null; then
        echo -e "${GREEN}[INFO]${NC} ✓ oled.service 已设置开机自启"
    else
        echo -e "${YELLOW}[WARN]${NC} ⚠ oled.service 未设置开机自启"
        systemctl enable oled.service
    fi
}

restart_service() {
    echo -e "${GREEN}[INFO]${NC} 重启 OLED 服务..."
    systemctl restart oled.service
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[INFO]${NC} ✓ 服务重启成功"
        sleep 2
        if systemctl is-active --quiet oled.service; then
            echo -e "${GREEN}[INFO]${NC} ✓ 服务运行正常"
        else
            echo -e "${RED}[ERROR]${NC} ✗ 服务运行异常"
        fi
    else
        echo -e "${RED}[ERROR]${NC} ✗ 服务重启失败"
    fi
}

show_usage() {
    local cpu_usage cpu_temp rx tx
    cpu_usage=$(grep 'cpu ' /proc/stat 2>/dev/null | awk '{usage=($2+$4)*100/($2+$4+$5)} END {printf "%.0f", usage}' 2>/dev/null || echo "N/A")
    cpu_temp=$(awk '{printf "%.0f", $1/1000}' /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "N/A")
    local ip
    ip=$(ip -4 addr show scope global 2>/dev/null | grep -oP 'inet \K[\d.]+' | head -1 || echo "N/A")

    echo -e "\n${GREEN}=== EasePi A2 OLED 诊断工具 (Go) ===${NC}"
    echo -e "${YELLOW}📊 当前状态：${NC}"
    echo -e "  CPU: ${cpu_usage}%  温度: ${cpu_temp}°C   IP: ${ip}"
    echo -e "\n${YELLOW}📌 管理命令：${NC}"
    echo -e "  • 查看状态：  systemctl status oled.service"
    echo -e "  • 重启服务：  systemctl restart oled.service"
    echo -e "  • 停止服务：  systemctl stop oled.service"
    echo -e "  • 前台运行：  ${OLED_BIN}"
    echo -e "  • 检测设备：  i2cdetect -y 3"
    echo -e "\n${YELLOW}📋 显示模式：${NC}"
    echo -e "  • 空闲(1行)：仅 IP 地址，底部对齐"
    echo -e "  • CPU高(2行)：CPU+温度 在上，IP 在下"
    echo -e "  • NET高(2行)：网速 在上，IP 在下"
    echo -e "  • 高负载(3行)：CPU | NET | IP"
    echo -e "\n${YELLOW}⚙️ 阈值：${NC}"
    echo -e "  CPU > 30% 或 温度 > 60°C → CPU 模式"
    echo -e "  NET > 100KB/s → NET 模式"
    echo -e "  同时触发 → 3 行模式"
}

main() {
    clear
    show_usage
    echo -e "\n${GREEN}开始诊断...${NC}\n"

    check_root
    check_files
    check_deps
    check_i2c
    check_service

    echo -e "\n${GREEN}=== 诊断完成 ===${NC}"
    echo -e "${YELLOW}是否要重启 OLED 服务？(y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        restart_service
    fi
}

main
OLEDINIT

	# =============================================
	# OLED Go Binary: 主机交叉编译 (GOARCH=arm64)
	# =============================================
	local OLED_SRC_DIR="${EXT_DIR}/easepi-a2-peripherals/oled-src"
	if [[ -d "${OLED_SRC_DIR}" ]]; then
		display_alert "EasePi-A2" "Building OLED Go binary from source (host cross-compile)" "info"
		local OLED_BUILD_DIR="$(mktemp -d)"
		cp -r "${OLED_SRC_DIR}"/* "${OLED_BUILD_DIR}"/
		(
			cd "${OLED_BUILD_DIR}" || exit 1
			CGO_ENABLED=0 GOARCH=arm64 GOOS=linux go build -ldflags='-s -w' -o oled .
		) || {
			display_alert "EasePi-A2" "Failed to compile oled Go binary; OLED will be unavailable" "wrn"
			rm -rf "${OLED_BUILD_DIR}"
			return 0
		}
		cp "${OLED_BUILD_DIR}/oled" "${SDCARD}"/usr/local/oled/oled
		chmod +x "${SDCARD}"/usr/local/oled/oled
		rm -rf "${OLED_BUILD_DIR}"
	fi

	# =============================================
	# 字体文件：从系统包链接
	# =============================================
	ln -sf /usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf \
		"${SDCARD}"/usr/local/oled/DejaVuSansMono.ttf

	# =============================================
	# 设置脚本权限
	# =============================================
	chmod +x "${SDCARD}"/usr/local/ir/ir-setup.sh 2>/dev/null || true
	chmod +x "${SDCARD}"/usr/local/ir/fix_infrared.sh 2>/dev/null || true
	chmod +x "${SDCARD}"/usr/local/oled/oled_init.sh 2>/dev/null || true

	# =============================================
	# BCM4345C0 蓝牙固件符号链接
	# =============================================
	if [ -f "${SDCARD}"/lib/firmware/BCM4345C0.hcd ]; then
		ln -sf ../BCM4345C0.hcd "${SDCARD}"/lib/firmware/brcm/BCM4345C0.hcd 2>/dev/null || \
		ln -sf BCM4345C0.hcd "${SDCARD}"/lib/firmware/brcm/BCM4345C0.hcd 2>/dev/null || true
		ln -sf BCM4345C0.hcd "${SDCARD}"/lib/firmware/brcm/BCM4345C0.easepi,a2.hcd 2>/dev/null || true
	fi
}

function post_customize_image__enable_easepi_a2_services() {
	display_alert "EasePi-A2" "Enabling A2 peripheral services (BRANCH=${BRANCH})" "info"

	# OLED service（所有分支通用）
	chroot_sdcard systemctl enable oled.service || true

	# IR service
	chroot_sdcard systemctl enable ir-keymap.service || true

	# Bluetooth: vendor 分支需要 hciattach 服务，主线内核 serdev 自动处理
	if [[ "${BRANCH}" == "vendor" ]]; then
		display_alert "EasePi-A2" "Enabling bluetooth-hciattach.service (vendor kernel)" "info"
		chroot_sdcard systemctl enable bluetooth-hciattach.service || true
	else
		display_alert "EasePi-A2" "Skipping bluetooth-hciattach.service (mainline kernel serdev handles BT)" "info"
	fi
	chroot_sdcard systemctl enable bluetooth.service || true
}