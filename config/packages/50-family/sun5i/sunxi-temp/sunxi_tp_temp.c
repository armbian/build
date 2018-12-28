#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#include <math.h>
#include "mod_mmio.h"

//#define _debug ;

const int SoCTempAdjustment = 1447 ;

int main(int argc, char *argv[])
{

  mmio_write(0x01c25000, 0x0027003f) ;
  mmio_write(0x01c25010, 0x00040000) ;
  mmio_write(0x01c25018, 0x00010fff) ;
  mmio_write(0x01c25004, 0x00000010) ;

  #ifdef _debug
    printf("w 0x01c25000: %08lx\n", mmio_read(0x01c25000)) ;
    printf("w 0x01c25010: %08lx\n", mmio_read(0x01c25010)) ;
    printf("w 0x01c25018: %08lx\n", mmio_read(0x01c25018)) ;
    printf("w 0x01c25004: %08lx\n", mmio_read(0x01c25004)) ;
    printf("r 0x01c25020: %08lx\n", mmio_read(0x01c25020)) ;
  #endif

  printf("%0.1f\n",(float)(mmio_read(0x01c25020)-SoCTempAdjustment)/10.0);

  return 0;

}
