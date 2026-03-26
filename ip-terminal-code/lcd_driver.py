import time
import spidev
import RPi.GPIO as GPIO

# LCD Pins
LCD_RST_PIN = 27
LCD_DC_PIN = 25
LCD_BL_PIN = 24

class ST7735:
    def __init__(self):
        self.width = 128
        self.height = 128

        # GPIO Setup
        GPIO.setmode(GPIO.BCM)
        GPIO.setwarnings(False)
        GPIO.setup(LCD_RST_PIN, GPIO.OUT)
        GPIO.setup(LCD_DC_PIN, GPIO.OUT)
        GPIO.setup(LCD_BL_PIN, GPIO.OUT)

        # SPI Setup
        self.spi = spidev.SpiDev()
        self.spi.open(0, 0)
        self.spi.max_speed_hz = 9000000
        self.spi.mode = 0b00

        self.init_display()

    def command(self, cmd):
        GPIO.output(LCD_DC_PIN, GPIO.LOW)
        self.spi.writebytes([cmd])

    def data(self, data):
        GPIO.output(LCD_DC_PIN, GPIO.HIGH)
        self.spi.writebytes([data])

    def reset(self):
        GPIO.output(LCD_RST_PIN, GPIO.HIGH)
        time.sleep(0.01)
        GPIO.output(LCD_RST_PIN, GPIO.LOW)
        time.sleep(0.01)
        GPIO.output(LCD_RST_PIN, GPIO.HIGH)
        time.sleep(0.01)

    def init_display(self):
        self.reset()

        # Initialization sequence for ST7735S (1.44" 128x128)
        self.command(0x11) # Sleep out
        time.sleep(0.12)

        self.command(0xB1) # In normal mode (Full colors)
        self.data(0x01); self.data(0x2C); self.data(0x2D)

        self.command(0xB2) # In Idle mode (8-colors)
        self.data(0x01); self.data(0x2C); self.data(0x2D)

        self.command(0xB3) # In partial mode + Full colors
        self.data(0x01); self.data(0x2C); self.data(0x2D);
        self.data(0x01); self.data(0x2C); self.data(0x2D)

        self.command(0xB4) # Dot inversion control
        self.data(0x07)

        self.command(0xC0) # Power control
        self.data(0xA2); self.data(0x02); self.data(0x84)
        self.command(0xC1) # Power control
        self.data(0xC5)
        self.command(0xC2) # Power control
        self.data(0x0A); self.data(0x00)
        self.command(0xC3) # Power control
        self.data(0x8A); self.data(0x2A)
        self.command(0xC4) # Power control
        self.data(0x8A); self.data(0xEE)

        self.command(0xC5) # VCOM control
        self.data(0x0E)

        self.command(0x36) # Memory access control (Direction)
        self.data(0xC0) # Row address order, Column address order, BGR

        self.command(0xE0) # Gamma adjustment (+ polarity)
        self.data(0x0F); self.data(0x1A); self.data(0x0F); self.data(0x18)
        self.data(0x2F); self.data(0x28); self.data(0x20); self.data(0x22)
        self.data(0x1F); self.data(0x1B); self.data(0x23); self.data(0x37)
        self.data(0x00); self.data(0x07); self.data(0x02); self.data(0x10)

        self.command(0xE1) # Gamma adjustment (- polarity)
        self.data(0x0F); self.data(0x1B); self.data(0x0F); self.data(0x17)
        self.data(0x33); self.data(0x2C); self.data(0x29); self.data(0x2E)
        self.data(0x30); self.data(0x30); self.data(0x39); self.data(0x3F)
        self.data(0x00); self.data(0x07); self.data(0x03); self.data(0x10)

        self.command(0x2A) # Column address set
        self.data(0x00); self.data(0x00); self.data(0x00); self.data(0x7F)

        self.command(0x2B) # Row address set
        self.data(0x00); self.data(0x00); self.data(0x00); self.data(0x7F)

        self.command(0xF0) # Enable test command
        self.data(0x01)
        self.command(0xF6) # Disable ram power save mode
        self.data(0x00)

        self.command(0x3A) # Interface pixel format (16-bit)
        self.data(0x05)

        self.command(0x29) # Display on

        # Turn on backlight
        GPIO.output(LCD_BL_PIN, GPIO.HIGH)

    def set_window(self, x_start, y_start, x_end, y_end):
        self.command(0x2A)
        self.data(0x00); self.data(x_start & 0xFF)
        self.data(0x00); self.data(x_end & 0xFF)

        self.command(0x2B)
        self.data(0x00); self.data(y_start & 0xFF)
        self.data(0x00); self.data(y_end & 0xFF)

        self.command(0x2C) # Write to RAM

    def display(self, image):
        """Prepare image and send to LCD."""
        # The LCD is 128x128, 16-bit color (RGB565)
        # Pillow image should be RGB
        im_width, im_height = image.size
        if im_width != self.width or im_height != self.height:
            image = image.resize((self.width, self.height))

        data = image.getdata()

        # Convert RGB888 to RGB565 (16-bit)
        # Big-endian: High byte (RRRRRGGG), Low byte (GGGBBBBB)
        buf = []
        for r, g, b in data:
            color = ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3)
            buf.append((color >> 8) & 0xFF)
            buf.append(color & 0xFF)

        self.set_window(0, 0, self.width - 1, self.height - 1)
        GPIO.output(LCD_DC_PIN, GPIO.HIGH)
        # SPI send in chunks if necessary, spidev handles large transfers but speed might be an issue
        # max_speed_hz is set to 9MHz, which is safe for ST7735
        self.spi.writebytes2(buf)

    def clear(self, color=(0, 0, 0)):
        from PIL import Image
        image = Image.new("RGB", (self.width, self.height), color)
        self.display(image)

    def cleanup(self):
        self.spi.close()
        GPIO.output(LCD_BL_PIN, GPIO.LOW)
        GPIO.cleanup([LCD_RST_PIN, LCD_DC_PIN, LCD_BL_PIN])
