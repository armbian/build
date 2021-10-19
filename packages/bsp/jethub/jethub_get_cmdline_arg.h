#include <algorithm>
#include <iostream>
#include <fstream>
#include <vector>
#include <tuple>

std::string loadFileAsLine(const std::string& path) {
  std::string result;
  std::ifstream file(path);
  if (file) {
    std::getline(file, result, '\n');
  } else {
    std::cerr << "Unable to read file " << path << std::endl;
    exit(EXIT_FAILURE);
  }
  return result;
}

void split (const std::string& str, std::vector<std::string>& result, const std::string& delimiters)
{
  // from http://oopweb.com/CPP/Documents/CPPHOWTO/Volume/C++Programming-HOWTO-7.html
  // Skip delimiters at beginning.
  std::string::size_type lastPos = str.find_first_not_of (delimiters, 0);
  // Find first "non-delimiter".
  std::string::size_type pos     = str.find_first_of (delimiters, lastPos);
  while (std::string::npos != pos || std::string::npos != lastPos) {
    // Found a token, add it to the vector.
    result.push_back (str.substr (lastPos, pos - lastPos));
    // Skip delimiters.  Note the "not_of"
    lastPos = str.find_first_not_of (delimiters, pos);
    // Find next "non-delimiter"
    pos = str.find_first_of (delimiters, lastPos);
  }
}

// get value of key-value kernel command line argument
// examples: 
// 1)      f('mac') --> {true, '10:27:be:08:00:37'} if 'mac=10:27:be:08:00:37' is passed to kernel command line
// 2) f('bullshit') --> {false, ''}                 if 'bullshit' is not passed to kernel command line
std::tuple<bool, std::string> getCmdlineArgValue(const std::string &argKey) {
  bool isSuccess = false;
  std::string argValue;

  const auto cmdline = loadFileAsLine("/proc/cmdline");
  std::vector<std::string> cmdArgs;
  split(cmdline, cmdArgs, " ");

  std::find_if(
    std::cbegin(cmdArgs),
    std::cend(cmdArgs),
    [&isSuccess, &argValue, &argKey](const auto &arg) {
      bool result = false;

      std::vector<std::string> tokens;
      split(arg, tokens, "=");
      if (tokens.size() == 2 && tokens[0] == argKey) {
        result = true;
        isSuccess = result;
        argValue = tokens[1];
      }

      return result;
    }
  );

  return {isSuccess, argValue};
}

int displayCmdlineArg(const std::string &arg) {
  auto result = EXIT_FAILURE;

  const auto [isExist, value] = getCmdlineArgValue(arg);
  if (isExist) {
    result = EXIT_SUCCESS;
    std::cout << value << std::endl;
  } else {
    std::cerr << "Unable to find '" << arg << "=<value>' in kernel command line" << std::endl;
  }

  return result;
}
