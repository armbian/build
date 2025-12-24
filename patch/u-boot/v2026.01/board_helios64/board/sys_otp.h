#ifndef __HELIOS64_SYS_OTP_H
#define __HELIOS64_SYS_OTP_H

int read_otp_data(void);
void set_board_info(void);
int get_revision(int *major, int *minor);
const char *get_variant(void);
int mac_read_from_otp(void);

#endif
