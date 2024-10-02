#include <cstdlib>
#include <iostream>

#include "jethub_get_efuse_raw_key.h"

void showUsage(const char *selfName) {
  std::cerr << "Utility to get raw efuse key value.\n"
            << '\n'
            << "Usage: " << selfName << " <key>\n"
            << '\n'
            << "  example 1:\n"
            << selfName << " usid | hexdump -C\n"
            << "  output:\n"
            << "00000000  73 36 30 35 5f 5f 30 35  30 34 31 39 30 39 67 63  |s605__05041909gc|\n"
            << "00000010  30 30 30 30 39 30 30 34  33 35 34 66 00 00 00 00  |00009004354f....|\n"
            << "00000020\n"
            << '\n'
            << "  example 2:\n"
            << selfName << " mac | hexdump -C\n"
            << "  output:\n"
            << "00000000  10 27 be 15 1a 24                                 |.'...$|\n"
            << "00000006"
            << std::endl;
}

int main (int argc, char *argv[]) {

  const uint8_t argumentsExpected = 1;
  const uint8_t noArgumentsArgc = 1;
  int returnCode = EXIT_SUCCESS;

  if (argc == noArgumentsArgc + argumentsExpected) {
    const std::string requestedKeyname (argv[1]);
    if (requestedKeyname.size() > 0) {
      std::cout << getKey(requestedKeyname);
    } else {
      std::cerr << "Empty keyname in argument" << std::endl;
      returnCode = EXIT_FAILURE;
    }
  } else {
    showUsage(argv[0]);
    returnCode = EXIT_FAILURE;
  }

  return returnCode;
}
