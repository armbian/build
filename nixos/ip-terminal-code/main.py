#!/usr/bin/env python3
"""
IP Terminal Configurator

Two operating modes, selected at launch:
  (default)  Hardware mode – rotary encoder + I2C LCD (Raspberry Pi)
  --tui      TUI mode      – dialog-based interface for SSH / serial console

Usage:
  python3 main.py          # hardware mode
  python3 main.py --tui    # TUI mode
"""

import argparse
import ipaddress
import os
import subprocess
import sys
import time


# ---------------------------------------------------------------------------
# Shared state  (module-level so both modes can read/write it)
# ---------------------------------------------------------------------------

ip_octets      = [192, 168, 1, 1]
subnet_prefix  = 16                 # CIDR prefix length (0-32)
gateway_octets = [192, 168, 1, 1]
dns_octets     = [1,   1,   1, 1]
use_dhcp       = False              # True = ipv4.method auto

MENU_OPTIONS    = ["IP address", "Subnet prefix", "Gateway", "DNS"]
MENU_COUNT      = len(MENU_OPTIONS)
CONNECTION_NAME = "end0"


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

def octets_str(octs):
    return ".".join(str(o) for o in octs)


def field_octets(field):
    """Return the mutable octet list for a field index (0=IP, 2=GW, 3=DNS)."""
    if field == 0:
        return ip_octets
    elif field == 2:
        return gateway_octets
    else:
        return dns_octets


def field_value_str(field):
    """Human-readable current value for a field index."""
    if field == 0:
        return "DHCP" if use_dhcp else octets_str(ip_octets)
    if field == 1:
        return "DHCP" if use_dhcp else f"/{subnet_prefix}"
    if field == 2:
        return "DHCP" if use_dhcp else octets_str(gateway_octets)
    return octets_str(dns_octets)  # field 3: DNS


def auto_gateway_from_ip():
    """Set gateway_octets to the first host address (network + 1) of the current subnet."""
    try:
        network = ipaddress.IPv4Network(
            f"{octets_str(ip_octets)}/{subnet_prefix}", strict=False
        )
        gw = network.network_address + 1
        gateway_octets[:] = list(gw.packed)
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Network helpers (shared)
# ---------------------------------------------------------------------------

def get_network_settings():
    """Populate shared state from nmcli / systemd-resolved."""
    global subnet_prefix, use_dhcp

    try:
        result = subprocess.run(
            ["nmcli", "-g", "IP4.ADDRESS", "connection", "show", CONNECTION_NAME],
            capture_output=True, text=True, check=True,
        )
        addr = result.stdout.strip().split("\n")[0]
        if addr and "/" in addr:
            ip_part, prefix_part = addr.split("/")
            ip_octets[:]  = [int(x) for x in ip_part.split(".")]
            subnet_prefix = int(prefix_part)
    except Exception as e:
        sys.stderr.write(f"Error in get_network_settings (IP4.ADDRESS): {e}\n")

    try:
        result = subprocess.run(
            ["nmcli", "-g", "IP4.GATEWAY", "connection", "show", CONNECTION_NAME],
            capture_output=True, text=True, check=True,
        )
        gw = result.stdout.strip()
        if gw and gw != "--":
            gateway_octets[:] = [int(x) for x in gw.split(".")]
    except Exception as e:
        sys.stderr.write(f"Error in get_network_settings (IP4.GATEWAY): {e}\n")

    try:
        # First try to get the configured static DNS
        result = subprocess.run(
            ["nmcli", "-g", "ipv4.dns", "connection", "show", CONNECTION_NAME],
            capture_output=True, text=True, check=True,
        )
        dns_output = result.stdout.strip()

        # If no static DNS, try the active runtime DNS (from DHCP)
        if not dns_output or dns_output == "--":
            result = subprocess.run(
                ["nmcli", "-g", "IP4.DNS", "connection", "show", CONNECTION_NAME],
                capture_output=True, text=True, check=True,
            )
            dns_output = result.stdout.strip()

        if dns_output and dns_output != "--":
            # nmcli may return multiple DNS servers separated by commas or spaces
            dns_str = dns_output.replace(",", " ").split()[0]
            if dns_str and "." in dns_str:
                dns_octets[:] = [int(x) for x in dns_str.split(".")]
    except Exception as e:
        sys.stderr.write(f"Error in get_network_settings (DNS recovery): {e}\n")

    try:
        result = subprocess.run(
            ["nmcli", "-g", "ipv4.method", "connection", "show", CONNECTION_NAME],
            capture_output=True, text=True, check=True,
        )
        use_dhcp = result.stdout.strip() == "auto"
    except Exception as e:
        sys.stderr.write(f"Error in get_network_settings (ipv4.method): {e}\n")


def get_live_ip():
    """Return the currently active IPv4 v4 address (DHCP lease or configured static)."""
    try:
        result = subprocess.run(
            ["nmcli", "-g", "IP4.ADDRESS", "connection", "show", CONNECTION_NAME],
            capture_output=True, text=True, check=True,
        )
        addr = result.stdout.strip().split("\n")[0]
        if addr and "/" in addr:
            return addr.split("/")[0]
        return addr or "No IP assigned"
    except Exception as e:
        sys.stderr.write(f"Error in get_live_ip: {e}\n")
        return "Unknown"


def apply_all_settings():
    """Apply IP/prefix, gateway and DNS all at once."""
    if use_dhcp:
        # In DHCP mode, we clear addresses/gateway.
        # For DNS, we respect the current dns_octets if we want a static override.
        # If we want pure DHCP, we'd clear ipv4.dns and set ignore-auto-dns no.
        # But our UI always has a DNS value. We'll set it as an override if ignore-auto-dns is yes.
        dns_str = octets_str(dns_octets)
        subprocess.run(
            ["nmcli", "connection", "modify", CONNECTION_NAME,
             "ipv4.method", "auto",
             "ipv4.addresses", "",
             "ipv4.gateway", "",
             "ipv4.dns", dns_str,
             "ipv4.ignore-auto-dns", "yes"],
            check=True, capture_output=True,
        )
    else:
        cidr = f"{octets_str(ip_octets)}/{subnet_prefix}"
        dns_str = octets_str(dns_octets)
        subprocess.run(
            ["nmcli", "connection", "modify", CONNECTION_NAME,
             "ipv4.method", "manual",
             "ipv4.addresses", cidr,
             "ipv4.gateway", octets_str(gateway_octets),
             "ipv4.dns", dns_str,
             "ipv4.ignore-auto-dns", "yes"],
            check=True, capture_output=True,
        )
    subprocess.run(["nmcli", "con", "up", CONNECTION_NAME], check=True, capture_output=True)


def apply_settings(field):
    """Apply the current value of *field* via nmcli."""
    if field in (0, 1):
        if use_dhcp:
            subprocess.run(
                ["nmcli", "connection", "modify", CONNECTION_NAME,
                 "ipv4.method", "auto", "ipv4.addresses", "", "ipv4.gateway", "", "ipv4.dns", "", "ipv4.ignore-auto-dns", "no"],
                check=True, capture_output=True,
            )
        else:
            cidr = f"{octets_str(ip_octets)}/{subnet_prefix}"
            subprocess.run(
                ["nmcli", "connection", "modify", CONNECTION_NAME,
                 "ipv4.method", "manual", "ipv4.addresses", cidr],
                check=True, capture_output=True,
            )
        subprocess.run(["nmcli", "con", "up", CONNECTION_NAME], check=True, capture_output=True)

    elif field == 2:  # Gateway (static only – no-op in DHCP mode)
        if not use_dhcp:
            subprocess.run(
                ["nmcli", "connection", "modify", CONNECTION_NAME,
                 "ipv4.gateway", octets_str(gateway_octets)],
                check=True, capture_output=True,
            )
            subprocess.run(["nmcli", "con", "up", CONNECTION_NAME], check=True, capture_output=True)

    else:  # DNS (field 3)
        dns_str = octets_str(dns_octets)
        subprocess.run(
            ["nmcli", "connection", "modify", CONNECTION_NAME,
             "ipv4.dns", dns_str, "ipv4.ignore-auto-dns", "yes"],
            check=True, capture_output=True,
        )
        subprocess.run(["nmcli", "con", "up", CONNECTION_NAME], check=True, capture_output=True)


# ---------------------------------------------------------------------------
# Hardware mode  –  rotary encoder + I2C LCD
# ---------------------------------------------------------------------------
# ABCD
def run_hardware():
    """Main loop for the physical rotary-encoder + I2C-LCD interface."""
    global subnet_prefix, use_dhcp

    import RPi.GPIO as GPIO
    from PIL import Image, ImageDraw, ImageFont
    from lcd_driver import ST7735

    # Pin assignments (Waveshare 1.44inch LCD HAT)
    UP_PIN    = 6
    DOWN_PIN  = 19
    LEFT_PIN  = 5
    RIGHT_PIN = 26
    PRESS_PIN = 13
    KEY1_PIN  = 21
    KEY2_PIN  = 20
    KEY3_PIN  = 16

    lcd = ST7735()

    # Load fonts (try environment variable first, then standard paths)
    font_paths = []
    env_font = os.environ.get("FONT_PATH")
    if env_font:
        font_paths.append(env_font)

    font_paths.extend([
        "/run/current-system/sw/share/fonts/truetype/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ])

    font = ImageFont.load_default()
    title_font = font
    header_font = font

    for path in font_paths:
        try:
            # Main font for menu items (increased from default ~8 to 13)
            font = ImageFont.truetype(path, 13)
            # Bold/Larger font for titles (15)
            title_font = ImageFont.truetype(path, 15)
            # Smaller header/footer if needed
            header_font = ImageFont.truetype(path, 11)
            print(f"DEBUG: Successfully loaded font: {path}")
            break
        except Exception as e:
            continue
    else:
        print("DEBUG: Could not load any TTF font, falling back to default.")

    HW_MENU       = ["IP address", "Subnet prefix", "Gateway", "DNS", "Apply"]
    HW_MENU_COUNT = len(HW_MENU)
    IP_SUBMENU    = ["Enable DHCP", "View IP", "Set static IP", "<- Back"]

    # Local UI state
    mode             = "menu"   # "menu" | "ip_mode" | "view_ip" | "edit"
    menu_index       = 0
    edit_field       = 0        # field index into MENU_OPTIONS (0-3)
    state_index      = 0        # octet being edited (0-3)
    ip_mode_index    = 0
    live_ip          = ["Initializing..."]
    edit_return_mode = "menu"

    # Color palette
    COLOR_BG      = (0, 0, 0)
    COLOR_TEXT    = (255, 255, 255)
    COLOR_HIGHLIGHT = (0, 0, 255) # Blue
    COLOR_ACCENT  = (0, 255, 255) # Cyan

    # ---- LCD helpers ----

    def update_display():
        image = Image.new("RGB", (128, 128), COLOR_BG)
        draw = ImageDraw.Draw(image)

        if mode == "menu":
            draw.text((5, 5), "Main Menu", font=title_font, fill=COLOR_ACCENT)
            draw.line((5, 23, 123, 23), fill=COLOR_ACCENT)
            for i, item in enumerate(HW_MENU):
                y = 28 + i * 20
                prefix = "> " if i == menu_index else "  "
                color = COLOR_HIGHLIGHT if i == menu_index else COLOR_TEXT
                draw.text((5, y), f"{prefix}{item}", font=font, fill=color)

        elif mode == "ip_mode":
            draw.text((5, 5), "IP Config", font=title_font, fill=COLOR_ACCENT)
            draw.line((5, 23, 123, 23), fill=COLOR_ACCENT)
            for i, item in enumerate(IP_SUBMENU):
                y = 28 + i * 20
                prefix = "> " if i == ip_mode_index else "  "
                color = COLOR_HIGHLIGHT if i == ip_mode_index else COLOR_TEXT
                draw.text((5, y), f"{prefix}{item}", font=font, fill=color)

        elif mode == "view_ip":
            draw.text((5, 5), "Current IP", font=title_font, fill=COLOR_ACCENT)
            draw.line((5, 23, 123, 23), fill=COLOR_ACCENT)
            draw.text((5, 50), live_ip[0], font=font, fill=COLOR_TEXT)
            draw.text((5, 105), "Press any key", font=header_font, fill=COLOR_HIGHLIGHT)

        elif mode == "edit":
            labels = {0: "Edit IP", 1: "Edit prefix", 2: "Edit GW", 3: "Edit DNS"}
            draw.text((5, 5), labels[edit_field], font=title_font, fill=COLOR_ACCENT)
            draw.line((5, 23, 123, 23), fill=COLOR_ACCENT)

            if edit_field == 1:
                draw.text((5, 50), f"Value: /{subnet_prefix}", font=font, fill=COLOR_TEXT)
            else:
                octs = field_octets(edit_field)
                val_str = ""
                for i, o in enumerate(octs):
                    if i == state_index:
                        val_str += f"[{o}] "
                    else:
                        val_str += f"{o} "
                draw.text((5, 50), val_str.strip(), font=font, fill=COLOR_TEXT)

            draw.text((5, 105), "Press JS to confirm", font=header_font, fill=COLOR_HIGHLIGHT)

        print(f"DEBUG: update_display (mode={mode}, menu={menu_index}, edit={edit_field})")
        lcd.display(image)

    def do_apply_all():
        image = Image.new("RGB", (128, 128), COLOR_BG)
        draw = ImageDraw.Draw(image)
        draw.text((5, 50), "Applying...", font=font, fill=COLOR_ACCENT)
        lcd.display(image)

        try:
            apply_all_settings()
            draw.text((5, 80), "Done!", font=font, fill=(0, 255, 0))
            lcd.display(image)
            time.sleep(2)
        except Exception as exc:
            print(f"apply error: {exc}")
            draw.text((5, 75), "Error!", font=font, fill=(255, 0, 0))
            err_msg = str(exc)[:22]
            draw.text((5, 95), err_msg, font=header_font, fill=(255, 0, 0))
            lcd.display(image)
            time.sleep(3)

    # ---- GPIO setup ----
    GPIO.setmode(GPIO.BCM)
    for pin in [UP_PIN, DOWN_PIN, LEFT_PIN, RIGHT_PIN, PRESS_PIN, KEY1_PIN, KEY2_PIN, KEY3_PIN]:
        GPIO.setup(pin, GPIO.IN, pull_up_down=GPIO.PUD_UP)

    get_network_settings()
    update_display()
    print("IP configurator ready. Joystick to navigate, KEY1/Press to select.")

    display_dirty    = False

    def get_input_state():
        return {
            "up": GPIO.input(UP_PIN) == 0,
            "down": GPIO.input(DOWN_PIN) == 0,
            "left": GPIO.input(LEFT_PIN) == 0,
            "right": GPIO.input(RIGHT_PIN) == 0,
            "press": GPIO.input(PRESS_PIN) == 0,
            "key1": GPIO.input(KEY1_PIN) == 0,
            "key2": GPIO.input(KEY2_PIN) == 0,
            "key3": GPIO.input(KEY3_PIN) == 0,
        }

    last_input = get_input_state()

    up_hold_start = 0
    up_last_repeat = 0
    down_hold_start = 0
    down_last_repeat = 0

    REPEAT_DELAY = 0.4

    try:
        while True:
            current_input = get_input_state()
            now = time.time()

            # Detect edge (button press)
            press_detected = False
            direction = 0
            back_detected = False
            left_detected = False
            right_detected = False

            # UP with repeat and acceleration
            if current_input["up"]:
                if not last_input["up"]:
                    direction = -1
                    up_hold_start = now
                    up_last_repeat = now
                    print("DEBUG: Joystick UP (press)")
                elif now - up_hold_start > REPEAT_DELAY:
                    hold_duration = now - up_hold_start
                    # Accelerate interval and step
                    if hold_duration > 0.5:
                        current_interval = 0.05
                        direction = -20
                    elif hold_duration > 0.2:
                        current_interval = 0.04
                        direction = -5
                    else:
                        current_interval = 0.1
                        direction = -1

                    if now - up_last_repeat > current_interval:
                        up_last_repeat = now
                        # direction is already set
                    else:
                        direction = 0 # Don't act if interval not reached
            else:
                up_hold_start = 0

            # DOWN with repeat and acceleration
            if current_input["down"]:
                if not last_input["down"]:
                    direction = 1
                    down_hold_start = now
                    down_last_repeat = now
                    print("DEBUG: Joystick DOWN (press)")
                elif now - down_hold_start > REPEAT_DELAY:
                    hold_duration = now - down_hold_start
                    # Accelerate interval and step
                    if hold_duration > 3:
                        current_interval = 0.05
                        direction = 10
                    elif hold_duration > 1.5:
                        current_interval = 0.04
                        direction = 5
                    else:
                        current_interval = 0.1
                        direction = 1

                    if now - down_last_repeat > current_interval:
                        down_last_repeat = now
                        # direction is already set
                    else:
                        direction = 0 # Don't act if interval not reached
            else:
                down_hold_start = 0

            if current_input["left"] and not last_input["left"]:
                left_detected = True
                print("DEBUG: Joystick LEFT")
            if current_input["right"] and not last_input["right"]:
                right_detected = True
                print("DEBUG: Joystick RIGHT")

            if (current_input["press"] and not last_input["press"]) or \
               (current_input["key1"] and not last_input["key1"]):
                press_detected = True
                print("DEBUG: Joystick PRESS / KEY1")
            if current_input["key2"] and not last_input["key2"]:
                back_detected = True
                print("DEBUG: KEY2 (Back)")

            # Action logic
            if direction != 0:
                if mode == "menu":
                    menu_index = (menu_index + direction) % HW_MENU_COUNT
                elif mode == "ip_mode":
                    ip_mode_index = (ip_mode_index + direction) % len(IP_SUBMENU)
                elif mode == "edit":
                    if edit_field == 1:
                        subnet_prefix = max(0, min(32, subnet_prefix - direction))
                    else:
                        octs = field_octets(edit_field)
                        octs[state_index] = (octs[state_index] - direction) % 256
                display_dirty = True

            if left_detected:
                if mode == "edit" and edit_field != 1:
                    if state_index > 0:
                        state_index -= 1
                        display_dirty = True
                elif mode in ("edit", "ip_mode", "view_ip"):
                    back_detected = True

            if right_detected:
                if mode == "edit" and edit_field != 1:
                    if state_index < 3:
                        state_index += 1
                        display_dirty = True
                elif mode == "menu":
                    press_detected = True

            if press_detected:
                if mode == "menu":
                    print(f"DEBUG: Menu Select index={menu_index}")
                    if menu_index == HW_MENU_COUNT - 1: # Apply
                        do_apply_all()
                    else:
                        edit_field = menu_index
                        get_network_settings()
                        if edit_field == 0:
                            ip_mode_index = 0 if use_dhcp else 1
                            mode = "ip_mode"
                            print("DEBUG: Submenu entering...")
                        elif edit_field in (1, 2) and use_dhcp:
                            print("DEBUG: Action blocked (DHCP mode)")
                            image = Image.new("RGB", (128, 128), COLOR_BG)
                            draw = ImageDraw.Draw(image)
                            draw.text((5, 50), "Disabled in", font=font, fill=(255, 0, 0))
                            draw.text((5, 75), "DHCP mode", font=font, fill=(255, 0, 0))
                            lcd.display(image)
                            time.sleep(1.5)
                        else:
                            state_index = 0
                            edit_return_mode = "menu"
                            mode = "edit"
                elif mode == "ip_mode":
                    print(f"DEBUG: IP Submenu index={ip_mode_index}")
                    if ip_mode_index == 0: # Enable DHCP
                        use_dhcp = True
                        # When switching to DHCP, we also want to transition back to DHCP DNS
                        # unless the user specifically overrides it again.
                        # For now, we'll keep the current DNS in the UI but apply_all_settings
                        # should probably have a way to 'unset' it.
                        # But for this task, the goal is to make sure EDITING works.
                        mode = "menu"
                    elif ip_mode_index == 1: # View IP
                        live_ip[0] = get_live_ip()
                        mode = "view_ip"
                    elif ip_mode_index == 2: # Set static IP
                        get_network_settings()
                        use_dhcp = False
                        state_index = 0
                        edit_return_mode = "ip_mode"
                        mode = "edit"
                    else: # Back
                        mode = "menu"
                elif mode == "view_ip":
                    mode = "ip_mode"
                elif mode == "edit":
                    if edit_field == 1 or state_index == 3:
                        if edit_field in (0, 1):
                            auto_gateway_from_ip()
                        mode = edit_return_mode
                    else:
                        state_index += 1
                display_dirty = True

            if back_detected:
                if mode == "ip_mode":
                    mode = "menu"
                elif mode == "view_ip":
                    mode = "ip_mode"
                elif mode == "edit":
                    if state_index > 0:
                        state_index -= 1
                    else:
                        mode = edit_return_mode
                display_dirty = True

            if display_dirty:
                print("DEBUG: Display dirty, updating...")
                update_display()
                display_dirty = False

            last_input = current_input
            time.sleep(0.01)

    except BaseException as e:
        import traceback
        if isinstance(e, KeyboardInterrupt):
            print("\nExiting via KeyboardInterrupt.")
        else:
            print(f"\nHARDWARE LOOP ERROR ({type(e).__name__}): {e}")
            traceback.print_exc()
        raise e
    finally:
        print("DEBUG: Performing LCD cleanup...")
        lcd.cleanup()


# ---------------------------------------------------------------------------
# TUI mode  –  ncurses interface for SSH / serial console
# ---------------------------------------------------------------------------

def run_tui():
    """Launch a dialog-based TUI for configuring network settings over SSH."""

    def dialog(*args):
        """Run dialog and return (returncode, output).  UI is drawn on the
        terminal; the selected value / typed text is captured from stderr."""
        result = subprocess.run(
            ["dialog"] + list(args),
            stderr=subprocess.PIPE, text=True,
        )
        return result.returncode, result.stderr.strip()

    def msgbox(title, text):
        content_lines = text.splitlines()
        height = min(len(content_lines) + 6, 40)
        width  = max(min(max((len(l) for l in content_lines), default=0) + 6, 78), 50)
        subprocess.run(["dialog", "--title", title, "--msgbox", text, str(height), str(width)])

    def run_ip_settings():
        subprocess.run(["nmtui", "edit", CONNECTION_NAME])
        subprocess.run(["nmcli", "con", "down", CONNECTION_NAME])
        subprocess.run(["nmtui", "connect", CONNECTION_NAME])

    def view_ips():
        lines = []
        for family, field in (("IPv4", "IP4.ADDRESS"), ("IPv6", "IP6.ADDRESS")):
            try:
                result = subprocess.run(
                    ["nmcli", "-g", field, "connection", "show", CONNECTION_NAME],
                    capture_output=True, text=True, check=True,
                )
                addrs = [
                    a.strip().replace("\\:", ":")
                    for raw in result.stdout.strip().splitlines()
                    for a in raw.split(" | ")
                    if a.strip() and a.strip() != "--"
                ]
                lines.append(f"{family}:")
                lines.extend(f"  {a}" for a in addrs) if addrs else lines.append("  (none)")
            except Exception as exc:
                lines.append(f"{family}: error ({exc})")
        msgbox("IP Addresses", "\n".join(lines))

    def run_dns_settings():
        current = octets_str(dns_octets)
        while True:
            rc, text = dialog(
                "--title", "Edit DNS settings",
                "--inputbox", "DNS server:", "8", "40", current,
            )
            if rc != 0:
                return
            try:
                parts = text.split(".")
                if len(parts) != 4:
                    raise ValueError
                values = [int(p) for p in parts]
                if not all(0 <= v <= 255 for v in values):
                    raise ValueError
                dns_octets[:] = values
                subprocess.run(
                    ["nmcli", "connection", "modify", CONNECTION_NAME,
                     "ipv4.dns", text, "ipv4.ignore-auto-dns", "yes"],
                    check=True, capture_output=True,
                )
                subprocess.run(["nmcli", "con", "up", CONNECTION_NAME], check=True, capture_output=True)
                msgbox("DNS", f"DNS set to {text}")
                return
            except ValueError:
                msgbox("Error", f"Invalid address '{text}'\nUse X.X.X.X (0-255)")
                current = text
            except subprocess.CalledProcessError as exc:
                msgbox("Error", f"Error applying DNS:\n{exc}")
                return

    while True:
        get_network_settings()
        rc, choice = dialog(
            "--title", "IP Terminal Configurator",
            "--menu", "Select an option:", "15", "50", "4",
            "1", "Edit IP settings",
            "2", "Edit DNS settings",
            "3", "View IPs",
            "4", "Quit",
        )
        if rc != 0 or choice == "4":
            break
        if choice == "1":
            run_ip_settings()
        elif choice == "2":
            run_dns_settings()
        elif choice == "3":
            view_ips()
    subprocess.run(["clear"])


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="IP Terminal Configurator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Modes:\n"
            "  (default)  Hardware – rotary encoder + I2C LCD (Raspberry Pi GPIO)\n"
            "  --tui      TUI      – dialog-based interface for SSH / serial console\n"
        ),
    )
    parser.add_argument(
        "--tui",
        action="store_true",
        help="Run in TUI (dialog) mode instead of hardware mode.",
    )
    args = parser.parse_args()

    if args.tui:
        run_tui()
    else:
        run_hardware()
