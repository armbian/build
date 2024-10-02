#include <cstdlib>

#include "jethub_get_efuse_raw_key.h"

int main (/*int argc, char *argv[]*/) {
  const std::string serial = getKey("serial").c_str(); // right trim extra '\0' bytes
  if (serial.size() > 0) {
    std::cout << serial << std::endl; 
  }
  return EXIT_SUCCESS;
}
