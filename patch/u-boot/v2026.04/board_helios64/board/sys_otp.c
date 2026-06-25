#include <linux/types.h>
#include <dm.h>
#include <spi.h>
#include <log.h>
#include <env.h>
#include <net.h>
#include <string.h>
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

/*
 * Ensure OTP data is cached and valid. If a previous read failed (for example
 * on a transient SPI error during board_early_init_r()), retry here so
 * consumers don't silently skip using OTP-provided values for the whole boot.
 */
static int ensure_otp_data_ready(void)
{
	if (is_data_valid())
		return 0;

	return read_otp_data();
}

/*
 * Decode the 6-byte serial number into a u64. Doing a casted *(uint64_t *)
 * read on otp.serial_num would over-read into otp.mfg_year and is unaligned
 * inside the packed struct (UB per the C standard).
 */
static inline u64 otp_serial(void)
{
	return  ((u64)otp.serial_num[0])       |
		((u64)otp.serial_num[1] << 8)  |
		((u64)otp.serial_num[2] << 16) |
		((u64)otp.serial_num[3] << 24) |
		((u64)otp.serial_num[4] << 32) |
		((u64)otp.serial_num[5] << 40);
}

static inline u16 otp_mfg_year(void)
{
	return otp.mfg_year[0] | ((u16)otp.mfg_year[1] << 8);
}

static inline int is_valid_header(void)
{
	static const u8 expected_magic[8] = { 'H', '6', '4', 'N', 'P', 'V', '1', 0 };

	return memcmp(otp.magic, expected_magic, sizeof(expected_magic)) == 0;
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

	printf("Part Number: %.*s\n",
		(int)strnlen((const char *)otp.part_num, sizeof(otp.part_num)),
		otp.part_num);
	printf("Variant: %s\n",
		(otp.variant < BOARD_VARIANT_MAX) ? var_str[otp.variant]
						  : var_str[BOARD_VARIANT_INVALID]);
	printf("Revision: %x.%x\n", (otp.revision & 0xf0) >> 4, otp.revision & 0x0f);
	printf("Serial Number: %012llx\n", otp_serial());
	printf("Manufacturing Date: %02X-%02X-%04X (DD-MM-YYYY)\n", otp.mfg_day,
		otp.mfg_month, otp_mfg_year());

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

	if (ret) {
		debug("SPI: Failed to read OTP: %d\n", ret);
		/* Leave has_been_read = 0 so a later call can retry. */
		return ret;
	}
	has_been_read = 1;

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
	if (ensure_otp_data_ready())
		return -1;

	*major = (otp.revision & 0xf0) >> 4;
	*minor = otp.revision & 0x0f;

	return 0;
}

const char *get_variant(void)
{
	static const char * const var_str[BOARD_VARIANT_MAX] = {
		"Unknown",
		"Engineering Sample",
		"4GB non ECC"
	};

	if (ensure_otp_data_ready())
		return var_str[BOARD_VARIANT_INVALID];

	if ((otp.variant < BOARD_VARIANT_ENG_SAMPLE) ||
		(otp.variant >= BOARD_VARIANT_MAX))
		return var_str[BOARD_VARIANT_INVALID];

	return var_str[otp.variant];
}

void set_board_info(void)
{
	char env_str[13];

	if (ensure_otp_data_ready())
		return;

	snprintf(env_str, sizeof(env_str), "%i.%i", (otp.revision & 0xf0) >> 4, otp.revision & 0x0f);
	env_set("board_rev", env_str);

	snprintf(env_str, sizeof(env_str), "%012llx", otp_serial());

	env_set("serial#", env_str);
}

int mac_read_from_otp(void)
{
	unsigned int i;

	if (ensure_otp_data_ready())
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
