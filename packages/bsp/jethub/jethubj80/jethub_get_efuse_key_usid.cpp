#include <cstdlib>

#include "jethub_get_efuse_raw_key.h"

int main (/*int argc, char *argv[]*/) {
  const std::string usid = getKey("usid").c_str(); // right trim extra '\0' bytes
  if (usid.size() > 0) {
    std::cout << usid << std::endl; 
  }
  return EXIT_SUCCESS;
}
