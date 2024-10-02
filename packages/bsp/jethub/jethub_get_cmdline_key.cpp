#include "jethub_get_cmdline_arg.h"

void showUsage(const char *selfName) {
  std::cerr << "Utility to get key from kernel's command-line parameters.\n"
            << "Only key=value parameters are parsed\n"
            << '\n'
            << "Usage: " << selfName << " <key>\n"
            << '\n'
            << "  example 1:\n"
            << selfName << " cpuid\n"
            << "  output:\n"
            << "210da40001a64046fa79108b844fbb81\n"
            << '\n'
            << "  example 2:\n"
            << selfName << " mac\n"
            << "  output:\n"
            << "10:27:be:08:00:37\n"
            << std::endl;
}

int main(int argc, char* argv[]) {
  const uint8_t argumentsExpected = 1;
  const uint8_t noArgumentsArgc = 1;
  int returnCode = EXIT_SUCCESS;

  if (argc == noArgumentsArgc + argumentsExpected) {
    const std::string requestedKeyname(argv[1]);
    if (requestedKeyname.size() > 0) {
      returnCode = displayCmdlineArg(requestedKeyname);
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
