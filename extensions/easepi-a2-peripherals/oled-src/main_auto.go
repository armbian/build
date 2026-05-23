package main

import (
	"flag"
	"fmt"
	"image"
	"image/color"
	"io"
	"log"
	"os"
	"os/exec"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"

	"golang.org/x/image/font"
	"golang.org/x/image/font/opentype"
	"golang.org/x/image/math/fixed"
)

const (
	I2C_BUS         = 3
	DEVICE_ADDR     = 0x3c
	WIDTH           = 128
	HEIGHT          = 32
	SSD1306_COMMAND = 0x00
	SSD1306_DATA    = 0x40
	I2C_SLAVE       = 0x0703
	I2C_RETRY       = 3
	SPEED_EMA_ALPHA = 0.3
	LOG_DIR         = "/var/log/oled"

	MODE_1_LINE  = 0
	MODE_2_CPU   = 1
	MODE_2_NET   = 2
	MODE_3_LINE  = 3

	CPU_HIGH_THRESHOLD  = 30.0
	TEMP_HIGH_THRESHOLD = 60
	NET_HIGH_THRESHOLD  = 100.0

	FONT_14 = 14.0
	FONT_12 = 12.0
	FONT_11 = 11.0

	LINE_SPACING_2H = 16
	LINE_SPACING_3H = 10

	HYSTERESIS = 3
)

var logger *log.Logger

type SSD1306 struct {
	fd *os.File
}

func newSSD1306() (*SSD1306, error) {
	path := fmt.Sprintf("/dev/i2c-%d", I2C_BUS)
	fd, err := os.OpenFile(path, os.O_RDWR, 0600)
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", path, err)
	}
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd.Fd(), I2C_SLAVE, uintptr(DEVICE_ADDR))
	if errno != 0 {
		fd.Close()
		return nil, fmt.Errorf("ioctl I2C_SLAVE: %v", errno)
	}
	return &SSD1306{fd: fd}, nil
}

func (o *SSD1306) Close() error {
	return o.fd.Close()
}

func (o *SSD1306) writeCmd(cmd byte) error {
	_, err := o.fd.Write([]byte{SSD1306_COMMAND, cmd})
	return err
}

func (o *SSD1306) writeCmds(cmds []byte) error {
	for _, c := range cmds {
		if err := o.writeCmd(c); err != nil {
			return err
		}
		time.Sleep(time.Microsecond)
	}
	return nil
}

func (o *SSD1306) writeData(data []byte) error {
	buf := make([]byte, 1+len(data))
	buf[0] = SSD1306_DATA
	copy(buf[1:], data)
	_, err := o.fd.Write(buf)
	return err
}

func retryI2C(fn func() error) error {
	var lastErr error
	for i := 0; i < I2C_RETRY; i++ {
		err := fn()
		if err == nil {
			return nil
		}
		lastErr = err
		if i < I2C_RETRY-1 {
			time.Sleep(100 * time.Millisecond)
		}
	}
	return fmt.Errorf("I2C operation failed after %d retries: %w", I2C_RETRY, lastErr)
}

func (o *SSD1306) Init() error {
	initCmds := []byte{
		0xAE, 0x20, 0x00, 0x00, 0x10, 0xB0,
		0xA1, 0xC8, 0xA6, 0xA8, 0x1F, 0xD3,
		0x00, 0xD5, 0x80, 0xD9, 0xF1, 0xDA,
		0x02, 0xDB, 0x40, 0x8D, 0x14, 0x40,
		0xA4, 0xAF,
	}
	return o.writeCmds(initCmds)
}

func (o *SSD1306) Clear() error {
	return retryI2C(func() error {
		for page := 0; page < 4; page++ {
			o.writeCmd(0xB0 + byte(page))
			o.writeCmd(0x00)
			o.writeCmd(0x10)
			for i := 0; i < 128; i += 32 {
				data := make([]byte, 32)
				if err := o.writeData(data); err != nil {
					return err
				}
			}
		}
		return nil
	})
}

func (o *SSD1306) SendImage(img *image.Gray) error {
	if img.Bounds().Dx() != WIDTH || img.Bounds().Dy() != HEIGHT {
		return fmt.Errorf("image size must be %dx%d", WIDTH, HEIGHT)
	}
	return retryI2C(func() error {
		for page := 0; page < 4; page++ {
			o.writeCmd(0xB0 + byte(page))
			o.writeCmd(0x00)
			o.writeCmd(0x10)
			pageData := make([]byte, 128)
			for x := 0; x < WIDTH; x++ {
				var b byte
				for bit := 0; bit < 8; bit++ {
					y := page<<3 + bit
					if y < HEIGHT && img.GrayAt(x, y).Y > 128 {
						b |= 1 << bit
					}
				}
				pageData[x] = b
			}
			for i := 0; i < 128; i += 32 {
				if err := o.writeData(pageData[i : i+32]); err != nil {
					return err
				}
			}
		}
		return nil
	})
}

type NetMon struct {
	prevRx         uint64
	prevTx         uint64
	prevTime       time.Time
	emaRx          float64
	emaTx          float64
	cachedIface    string
	ifaceCheckTime time.Time
}

func newNetMon() *NetMon {
	return &NetMon{prevTime: time.Now()}
}

func (n *NetMon) readBytes(iface string) (uint64, uint64) {
	data, err := os.ReadFile("/proc/net/dev")
	if err != nil {
		return 0, 0
	}
	lines := strings.Split(string(data), "\n")
	for _, line := range lines {
		if !strings.Contains(line, iface) {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 10 {
			continue
		}
		rx, _ := strconv.ParseUint(fields[1], 10, 64)
		tx, _ := strconv.ParseUint(fields[9], 10, 64)
		return rx, tx
	}
	return 0, 0
}

func (n *NetMon) detectIface() string {
	now := time.Now()
	if n.cachedIface != "" && now.Sub(n.ifaceCheckTime) < 30*time.Second {
		data, err := os.ReadFile("/proc/net/dev")
		if err == nil && strings.Contains(string(data), n.cachedIface) {
			return n.cachedIface
		}
	}
	n.cachedIface = ""
	n.ifaceCheckTime = now
	data, err := os.ReadFile("/proc/net/dev")
	if err != nil {
		return ""
	}
	lines := strings.Split(string(data), "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "Inter-") || strings.HasPrefix(line, "face") || strings.HasPrefix(line, "lo:") {
			continue
		}
		idx := strings.Index(line, ":")
		if idx < 0 {
			continue
		}
		iface := line[:idx+1]
		fields := strings.Fields(line[idx+1:])
		if len(fields) < 10 {
			continue
		}
		rx, _ := strconv.ParseUint(fields[0], 10, 64)
		if rx > 0 {
			n.cachedIface = iface
			return iface
		}
	}
	return ""
}

func (n *NetMon) GetSpeed() (string, string) {
	iface := n.detectIface()
	if iface == "" {
		return "\u21930B", "\u21910B"
	}
	rx, tx := n.readBytes(iface)
	now := time.Now()
	interval := now.Sub(n.prevTime).Seconds()
	if n.prevTime.IsZero() || interval < 0.05 || rx < n.prevRx || tx < n.prevTx {
		n.prevRx, n.prevTx, n.prevTime = rx, tx, now
		if n.prevTime.IsZero() {
			n.prevTime = now
		}
		return formatSpeed(max(n.emaRx, 0), '\u2193'), formatSpeed(max(n.emaTx, 0), '\u2191')
	}
	rxSpeed := float64(rx-n.prevRx) / interval / 1024.0
	txSpeed := float64(tx-n.prevTx) / interval / 1024.0
	if n.emaRx == 0.0 {
		n.emaRx, n.emaTx = rxSpeed, txSpeed
	} else {
		n.emaRx = SPEED_EMA_ALPHA*rxSpeed + (1-SPEED_EMA_ALPHA)*n.emaRx
		n.emaTx = SPEED_EMA_ALPHA*txSpeed + (1-SPEED_EMA_ALPHA)*n.emaTx
	}
	n.prevRx, n.prevTx, n.prevTime = rx, tx, now
	return formatSpeed(max(n.emaRx, 0), '\u2193'), formatSpeed(max(n.emaTx, 0), '\u2191')
}

func formatSpeed(kbs float64, prefix rune) string {
	if kbs < 0.95 {
		bps := kbs * 1024
		if bps < 99.5 {
			return fmt.Sprintf("%c%dB", prefix, int(bps))
		}
		return fmt.Sprintf("%c%.1fK", prefix, bps/1024)
	}
	if kbs < 999.5 {
		return fmt.Sprintf("%c%dK", prefix, int(kbs))
	}
	if kbs < 999500 {
		return fmt.Sprintf("%c%.1fM", prefix, kbs/1024)
	}
	return fmt.Sprintf("%c%.1fG", prefix, kbs/1048576)
}

func getIP() string {
	out, err := exec.Command("sh", "-c", "ip addr show eth0 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1").Output()
	if err == nil && len(out) > 0 {
		ip := strings.TrimSpace(string(out))
		if ip != "" {
			return ip
		}
	}
	out, err = exec.Command("sh", "-c", "hostname -I | awk '{print $1}'").Output()
	if err == nil && len(out) > 0 {
		ip := strings.TrimSpace(string(out))
		if ip != "" {
			return ip
		}
	}
	return "No Network"
}

func getCPUUsageTemp() (string, string) {
	cpuUsage := "0%"
	cpuTemp := "N/A"
	data, err := os.ReadFile("/proc/stat")
	if err == nil {
		fields := strings.Fields(strings.SplitN(string(data), "\n", 2)[0])
		if len(fields) >= 8 {
			t1 := sumFields(fields[1:8])
			i1, _ := strconv.Atoi(fields[4])
			time.Sleep(50 * time.Millisecond)
			data2, err2 := os.ReadFile("/proc/stat")
			if err2 == nil {
				fields2 := strings.Fields(strings.SplitN(string(data2), "\n", 2)[0])
				if len(fields2) >= 8 {
					t2 := sumFields(fields2[1:8])
					i2, _ := strconv.Atoi(fields2[4])
					diffT := t2 - t1
					diffI := i2 - i1
					if diffT > 0 {
						cpuUsage = fmt.Sprintf("%d%%", 100-diffI*100/diffT)
					}
				}
			}
		}
	}
	tempData, err := os.ReadFile("/sys/class/thermal/thermal_zone0/temp")
	if err == nil {
		t := strings.TrimSpace(string(tempData))
		if val, err := strconv.Atoi(t); err == nil {
			cpuTemp = fmt.Sprintf("%d\u00b0C", val/1000)
		}
	}
	return cpuUsage, cpuTemp
}

func sumFields(fields []string) int {
	sum := 0
	for _, f := range fields {
		v, _ := strconv.Atoi(f)
		sum += v
	}
	return sum
}

func loadFontFace(timeSize float64) font.Face {
	paths := []string{
		"/usr/local/oled/DejaVuSansMono.ttf",
		"/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
	}
	for _, p := range paths {
		data, err := os.ReadFile(p)
		if err != nil {
			continue
		}
		f, err := opentype.Parse(data)
		if err != nil {
			continue
		}
		face, err := opentype.NewFace(f, &opentype.FaceOptions{
			Size:    timeSize,
			DPI:     72,
			Hinting: font.HintingFull,
		})
		if err != nil {
			continue
		}
		logger.Printf("using font: %s (%.0fpx)", p, timeSize)
		return face
	}
	return nil
}

func drawText(img *image.Gray, face font.Face, text string, x, y int) {
	if face == nil {
		return
	}
	drawer := &font.Drawer{
		Dst:  img,
		Src:  image.NewUniform(color.White),
		Face: face,
		Dot:  fixed.P(x, y),
	}
	drawer.DrawString(text)
}

func textWidth(face font.Face, text string) int {
	if face == nil {
		return 0
	}
	return font.MeasureString(face, text).Ceil()
}

func textDescent(face font.Face) int {
	return face.Metrics().Descent.Ceil()
}

func chooseMode(cpuUsagePct float64, cpuTempVal int, netRxKbps, netTxKbps float64) int {
	cpuHigh := cpuUsagePct > CPU_HIGH_THRESHOLD || cpuTempVal > TEMP_HIGH_THRESHOLD
	netHigh := netRxKbps > NET_HIGH_THRESHOLD || netTxKbps > NET_HIGH_THRESHOLD

	switch {
	case cpuHigh && netHigh:
		return MODE_3_LINE
	case cpuHigh && !netHigh:
		return MODE_2_CPU
	case !cpuHigh && netHigh:
		return MODE_2_NET
	default:
		return MODE_1_LINE
	}
}

func main() {
	silent := flag.Bool("s", false, "silent mode")
	flag.BoolVar(silent, "silent", false, "silent mode")
	flag.Parse()

	os.MkdirAll(LOG_DIR, 0755)
	var writer io.Writer = os.Stdout
	logF, err := os.OpenFile(LOG_DIR+"/oled.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		log.Fatal(err)
	}
	if *silent {
		writer = logF
	} else {
		writer = io.MultiWriter(os.Stdout, logF)
	}
	logger = log.New(writer, "", log.LstdFlags)

	logger.Println("=== EasePi A2 OLED Go Auto Mode ===")

	if os.Geteuid() != 0 {
		logger.Fatal("must run as root")
	}

	if _, err := os.Stat(fmt.Sprintf("/dev/i2c-%d", I2C_BUS)); err != nil {
		exec.Command("modprobe", "i2c-dev").Run()
		if _, err := os.Stat(fmt.Sprintf("/dev/i2c-%d", I2C_BUS)); err != nil {
			logger.Fatalf("i2c-%d device not found", I2C_BUS)
		}
	}

	out, _ := exec.Command("i2cdetect", "-y", "3").Output()
	if !strings.Contains(string(out), "3c") && !strings.Contains(string(out), "3d") {
		logger.Fatal("OLED device not found on i2c-3")
	}

	oled, err := newSSD1306()
	if err != nil {
		logger.Fatal(err)
	}
	defer oled.Close()

	if err := oled.Init(); err != nil {
		logger.Fatalf("OLED init failed: %v", err)
	}
	if err := oled.Clear(); err != nil {
		logger.Fatalf("OLED clear failed: %v", err)
	}
	logger.Println("OLED initialized")

	face14 := loadFontFace(FONT_14)
	if face14 != nil {
		defer face14.Close()
	}
	face12 := loadFontFace(FONT_12)
	if face12 != nil {
		defer face12.Close()
	}
	face11 := loadFontFace(FONT_11)
	if face11 != nil {
		defer face11.Close()
	}

	testImg := image.NewGray(image.Rect(0, 0, WIDTH, HEIGHT))
	w := textWidth(face12, "EasePi A2 Auto")
	drawText(testImg, face12, "EasePi A2 Auto", (WIDTH-w)/2, 16)
	w = textWidth(face12, "Dynamic Switch")
	drawText(testImg, face12, "Dynamic Switch", (WIDTH-w)/2, 32)
	oled.SendImage(testImg)
	time.Sleep(2 * time.Second)
	oled.Clear()

	netmon := newNetMon()
	cachedIP := getIP()
	ipUpdateCount := 0

	currentMode := MODE_1_LINE
	modeChangeCounter := 0
	targetMode := MODE_1_LINE

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	ticker := time.NewTicker(950 * time.Millisecond)
	defer ticker.Stop()

	logger.Println("Main loop started")

	for {
		select {
		case <-sigCh:
			logger.Println("Received shutdown signal")
			oled.Clear()
			return
		case <-ticker.C:
		}

		ipUpdateCount++
		if ipUpdateCount%5 == 0 {
			cachedIP = getIP()
			ipUpdateCount = 0
		}

		cpuUsage, cpuTemp := getCPUUsageTemp()
		rxSpeed, txSpeed := netmon.GetSpeed()

		cpuPct := parseCPUPercent(cpuUsage)
		tempVal := parseTempValue(cpuTemp)
		rxKbps := parseSpeedKbps(rxSpeed)
		txKbps := parseSpeedKbps(txSpeed)

		newTarget := chooseMode(cpuPct, tempVal, rxKbps, txKbps)

		if newTarget != currentMode {
			if newTarget == targetMode {
				modeChangeCounter++
				if modeChangeCounter >= HYSTERESIS {
					currentMode = targetMode
					modeChangeCounter = 0
					logger.Printf("Mode changed to: %d (CPU:%.1f%% Temp:%d\u00b0C RX:%.1fK TX:%.1fK)",
						currentMode, cpuPct, tempVal, rxKbps, txKbps)
				}
			} else {
				targetMode = newTarget
				modeChangeCounter = 0
			}
		} else {
			targetMode = currentMode
			modeChangeCounter = 0
		}

		img := image.NewGray(image.Rect(0, 0, WIDTH, HEIGHT))

		switch currentMode {
		case MODE_1_LINE:
			render1Line(img, face14, cachedIP)
		case MODE_2_CPU:
			render2CPU(img, face12, cachedIP, cpuUsage, cpuTemp)
		case MODE_2_NET:
			render2Net(img, face12, cachedIP, rxSpeed, txSpeed)
		case MODE_3_LINE:
			render3Line(img, face11, cachedIP, cpuUsage, cpuTemp, rxSpeed, txSpeed)
		}

		oled.SendImage(img)
	}
}

func render1Line(img *image.Gray, face font.Face, ip string) {
	if face == nil {
		return
	}
	y := HEIGHT - textDescent(face) - 2
	w := textWidth(face, ip)
	drawText(img, face, ip, (WIDTH-w)/2, y)
}

func render2CPU(img *image.Gray, face font.Face, ip, cpuUsage, cpuTemp string) {
	if face == nil {
		return
	}
	descent := textDescent(face)
	startY := HEIGHT - descent - LINE_SPACING_2H - 2

	cpuLine := fmt.Sprintf("CPU: %s %s", cpuUsage, cpuTemp)
	w := textWidth(face, cpuLine)
	drawText(img, face, cpuLine, (WIDTH-w)/2, startY)

	w = textWidth(face, ip)
	drawText(img, face, ip, (WIDTH-w)/2, startY+LINE_SPACING_2H)
}

func render2Net(img *image.Gray, face font.Face, ip, rxSpeed, txSpeed string) {
	if face == nil {
		return
	}
	descent := textDescent(face)
	startY := HEIGHT - descent - LINE_SPACING_2H - 2

	netLabel := "NET:"
	labelW := textWidth(face, netLabel)

	rxValOnly := rxSpeed
	if len(rxSpeed) >= 3 {
		rxValOnly = rxSpeed[3:]
	}
	txValOnly := txSpeed
	if len(txSpeed) >= 3 {
		txValOnly = txSpeed[3:]
	}

	arrowW := textWidth(face, "\u2193")
	rxW := textWidth(face, rxValOnly)
	txW := textWidth(face, txValOnly)

	totalW := labelW + arrowW + rxW + 6 + arrowW + txW
	x := (WIDTH - totalW) / 2

	drawText(img, face, netLabel, x, startY)
	drawText(img, face, "\u2193"+rxValOnly, x+labelW, startY)
	drawText(img, face, "\u2191"+txValOnly, x+labelW+arrowW+rxW+6, startY)

	w := textWidth(face, ip)
	drawText(img, face, ip, (WIDTH-w)/2, startY+LINE_SPACING_2H)
}

func render3Line(img *image.Gray, face font.Face, ip, cpuUsage, cpuTemp, rxSpeed, txSpeed string) {
	if face == nil {
		return
	}
	lineSpacing := LINE_SPACING_3H
	startY := 0

	cpuLine := fmt.Sprintf("CPU: %s %s", cpuUsage, cpuTemp)
	w := textWidth(face, cpuLine)
	drawText(img, face, cpuLine, (WIDTH-w)/2, startY+8)

	netLabel := "NET:"
	labelW := textWidth(face, netLabel)

	rxValOnly := rxSpeed
	if len(rxSpeed) >= 3 {
		rxValOnly = rxSpeed[3:]
	}
	txValOnly := txSpeed
	if len(txSpeed) >= 3 {
		txValOnly = txSpeed[3:]
	}

	arrowW := textWidth(face, "\u2193")
	rxW := textWidth(face, rxValOnly)
	txW := textWidth(face, txValOnly)

	totalW := labelW + arrowW + rxW + 6 + arrowW + txW
	x := (WIDTH - totalW) / 2
	netY := startY + lineSpacing + 8

	drawText(img, face, netLabel, x, netY)
	drawText(img, face, "\u2193"+rxValOnly, x+labelW, netY)
	drawText(img, face, "\u2191"+txValOnly, x+labelW+arrowW+rxW+6, netY)

	w = textWidth(face, ip)
	drawText(img, face, ip, (WIDTH-w)/2, startY+2*lineSpacing+8)
}

func parseCPUPercent(s string) float64 {
	s = strings.TrimSuffix(s, "%")
	v, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0
	}
	return v
}

func parseTempValue(s string) int {
	s = strings.TrimSuffix(s, "\u00b0C")
	s = strings.TrimSuffix(s, "°C")
	if strings.TrimSpace(s) == "N/A" {
		return 0
	}
	v, err := strconv.Atoi(s)
	if err != nil {
		return 0
	}
	return v
}

func parseSpeedKbps(s string) float64 {
	if len(s) < 2 {
		return 0
	}
	s = s[3:]
	if len(s) == 0 {
		return 0
	}
	unit := s[len(s)-1]
	numStr := s[:len(s)-1]
	val, err := strconv.ParseFloat(numStr, 64)
	if err != nil {
		return 0
	}
	switch unit {
	case 'G':
		return val * 1048576
	case 'M':
		return val * 1024
	case 'K':
		return val
	case 'B':
		return val / 1024
	}
	return 0
}
