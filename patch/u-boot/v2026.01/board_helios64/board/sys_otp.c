#include <linux/types.h>
#include <dm.h>
#include <spi.h>
#include <log.h>
#include <env.h>
#include <net.h>
#include <u-boot/crc.h>

#include "sys_otp.h"

#define OTP_DEVICE_BUS  0
#define OTP_DEVICE_CS   0
#define MAX_NUM_PORTS	2

enum board_variant {
	BOARD_VARIANT_INVALID = 0,
	BOARD_VARIANT_ENG_SAMPLE,
	BOARD_VARIANT_4G_PROD_NO_ECC,
	BOARD_VARIANT_MAX
};

struct  __attribute__ ((__packed__)) otp_data_t {
	u8 magic[8];
	u8 part_num[16];
	u8 variant;
	u8 revision;
	u8 serial_num[6];
	u8 mfg_year[2];
	u8 mfg_month;
	u8 mfg_day;
	u8 mac_addr[MAX_NUM_PORTS][6];
	u8 reserved[204];
	u32 checksum;
} otp;

static struct spi_slave *slave;
static int has_been_read = 0;
static int data_valid = 0;

static inline int is_data_valid(void)
{
	return data_valid;
}

static inline int is_valid_header(void)
{
	if ((otp.magic[0] == 'H') || (otp.magic[1] == '6') ||
		(otp.magic[2] == '4') || (otp.magic[3] == 'N') ||
		(otp.magic[4] == 'P') || (otp.magic[5] == 'V') ||
		(otp.magic[6] == '1') || (otp.magic[7] == 0))

		return 1;

	return 0;
}

static int init_system_otp(int bus, int cs)
{
	int ret;
	char name[30], *str;
	struct udevice *dev;

	snprintf(name, sizeof(name), "generic_%d:%d", bus, cs);
	str = strdup(name);
	if (!str)
		return -ENOMEM;
	ret = _spi_get_bus_and_cs(bus, cs, 25000000, CONFIG_DEFAULT_SPI_MODE, "spi_generic_drv",
				 str, &dev, &slave);
	return ret;
}

#ifdef DEBUG
/**
 * show_otp_data - display the contents of the OTP register
 */
static void show_otp_data(void)
{
	u32 i;
	u32 crc;

	const char* var_str[BOARD_VARIANT_MAX] = {
			"Invalid variant",
			"Engineering Sample",
			"Production - 4GB non ECC"
	};

	printf("\n");
	printf("Register dump: (%lu bytes)\n", sizeof(otp));
	for (i = 0; i < sizeof(otp); i++) {
		if ((i % 16) == 0)
			printf("%02X: ", i);
		printf("%02X ", ((u8 *)&otp)[i]);
		if (((i % 16) == 15) || (i == sizeof(otp) - 1))
			printf("\n");
	}

	if (!is_valid_header())
		return;

	printf("Part Number: %s\n", otp.part_num);
	printf("Variant: %s\n", var_str[otp.variant]);
	printf("Revision: %x.%x\n", (otp.revision & 0xf0) >> 4, otp.revision & 0x0f);
	printf("Serial Number: %012llx\n", *((uint64_t*) otp.serial_num) &
		0xFFFFFFFFFFFF);
	printf("Manufacturing Date: %02X-%02X-%04X (DD-MM-YYYY)\n", otp.mfg_day,
		otp.mfg_month, *(u16*) otp.mfg_year);

	printf("1GbE MAC Address:   %02X:%02X:%02X:%02X:%02X:%02X\n",
		otp.mac_addr[0][0], otp.mac_addr[0][1], otp.mac_addr[0][2],
		otp.mac_addr[0][3], otp.mac_addr[0][4], otp.mac_addr[0][5]);

	printf("2.5GbE MAC Address: %02X:%02X:%02X:%02X:%02X:%02X\n",
		otp.mac_addr[1][0], otp.mac_addr[1][1], otp.mac_addr[1][2],
		otp.mac_addr[1][3], otp.mac_addr[1][4], otp.mac_addr[1][5]);

	crc = crc32(0, (void *)&otp, sizeof(otp) - 4);

	if (crc == le32_to_cpu(otp.checksum))
		printf("CRC: %08x\n\n", le32_to_cpu(otp.checksum));
	else
		printf("CRC: %08x (should be %08x)\n\n",
			   le32_to_cpu(otp.checksum), crc);

}
#endif

int read_otp_data(void)
{
	int ret;
	u8 dout[5];

	if (has_been_read) {
		if (is_data_valid())
			return 0;
		else
			goto data_invalid;
	}

	ret = init_system_otp(OTP_DEVICE_BUS, OTP_DEVICE_CS);
	if (ret)
		return ret;

	ret = spi_claim_bus(slave);
	if (ret) {
		debug("SPI: Failed to claim SPI bus: %d\n", ret);
		return ret;
	}

	dout[0] = 0x48;
	dout[1] = 0x00;
	dout[2] = 0x10; /* Security Register #1 */
	dout[3] = 0x00;
	dout[4] = 0x00; /* Dummy Byte */

	ret = spi_write_then_read(slave, dout, sizeof(dout), NULL, (u8 *)&otp,
			sizeof(otp));

	spi_release_bus(slave);
#ifdef DEBUG
	show_otp_data();
#endif

	has_been_read = (ret == 0) ? 1 : 0;
	if (!is_valid_header())
		goto data_invalid;

	if (crc32(0, (void *)&otp, sizeof(otp) - 4) ==
		le32_to_cpu(otp.checksum))
		data_valid = 1;

	if (!is_data_valid())
		goto data_invalid;

	return 0;

data_invalid:
	printf("Invalid board ID data!\n");
	return -1;
}

int get_revision(int *major, int *minor)
{
	if (!is_data_valid())
		return -1;

	*major = (otp.revision & 0xf0) >> 4;
	*minor = otp.revision & 0x0f;

	return 0;
}

const char *get_variant(void)
{
	const char* var_str[BOARD_VARIANT_MAX] = {
		"Unknown",
		"Engineering Sample",
		"4GB non ECC"
	};

	if ((otp.variant < BOARD_VARIANT_ENG_SAMPLE) ||
		(otp.variant >= BOARD_VARIANT_MAX))
		return var_str[0];

	return var_str[otp.variant];
}

void set_board_info(void)
{
	char env_str[13];

	if (!is_data_valid())
		return;

	snprintf(env_str, sizeof(env_str), "%i.%i", (otp.revision & 0xf0) >> 4, otp.revision & 0x0f);
	env_set("board_rev", env_str);

	sprintf(env_str, "%012llx", *((uint64_t*) otp.serial_num) &
		0xFFFFFFFFFFFF);

	env_set("serial#", env_str);
}

int mac_read_from_otp(void)
{
	unsigned int i;

	if (!is_data_valid())
		return -1;

	for (i = 0; i < MAX_NUM_PORTS; i++) {
		char enetvar[9];

		sprintf(enetvar, i ? "eth%daddr" : "ethaddr", i);

		if (!is_valid_ethaddr(otp.mac_addr[i])) {
			debug("Not valid %s!\n", enetvar);
			continue;
		}

		/* Only initialize environment variables that are blank
		 * (i.e. have not yet been set)
		 */
		if (!env_get(enetvar))
			eth_env_set_enetaddr(enetvar, otp.mac_addr[i]);
	}

	return 0;
}
