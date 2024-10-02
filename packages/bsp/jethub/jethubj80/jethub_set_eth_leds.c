/*
 * This test application is to read/write data directly from/to the device
 * from userspace.
 *
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mman.h>
#include <fcntl.h>

int main(int argc, char *argv[])
{
    int fd;
    unsigned long long reg_addr = 0;
    unsigned long long value = 0;

    unsigned long long page_addr, page_offset;
    void *ptr;
    unsigned long long page_size=sysconf(_SC_PAGESIZE);

    printf("REG access through /dev/mem. Page size %llu\n", page_size);

    reg_addr = 0xc8834558;

    /* Open /dev/mem file */
    fd = open ("/dev/mem", O_RDWR);
    if (fd < 1) {
        perror(argv[0]);
        return -1;
    }

    /* mmap the device into memory */
    page_addr = (reg_addr & (~(page_size-1)));
    page_offset = reg_addr - page_addr;
    ptr = mmap(NULL, page_size, PROT_READ|PROT_WRITE, MAP_SHARED, fd, page_addr);
    if(ptr < 0){
      printf("mmap failed. see errno for reason.\n");
      close(fd);
      return -1;
    }

    // read 0xC8834558 PREG_ETH1
    value = *((unsigned*)(ptr + page_offset));
    value = value ^ (1<<24);
    value = value ^ (1<<31);
    *((unsigned*)(ptr + page_offset)) = value;

    // read 0xC883455C PREG_ETH1 + 4
    value = *((unsigned*)(ptr + page_offset + 4));
    value = value | (1<<23);
    *((unsigned*)(ptr + page_offset + 4)) = value;

    munmap(ptr, page_size);
    close(fd);

    return 0;
}
