#include <algorithm>
#include <cstddef>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <vector>

using Bytes = std::vector<std::byte>;

std::string loadFileAsLine(const std::string& path) {
  std::string result;
  std::ifstream file(path);
  if (file) {
    std::getline(file, result, '\0');
  } else {
    std::cerr << "Unable to read file " << path << std::endl;
    exit(EXIT_FAILURE);
  }
  return result;
}

Bytes readBlock(std::uint32_t offset, std::uint32_t length, std::string const &filename)
{
  Bytes result;

  std::ifstream is(filename, std::ios::binary);
  if (is) {
    is.seekg(offset);

    result.resize(length);
    is.read(reinterpret_cast<char*>(result.data()), length);

    result.resize(is.gcount());

  } else {
    std::cerr << "Unable to read file " << filename << std::endl;
    exit(EXIT_FAILURE);
  }

  return result;
}


Bytes loadBinaryFile(std::string const &path)
{
  std::ifstream ifs(path, std::ios::binary | std::ios::ate);

  if(ifs) {
    auto end = ifs.tellg();
    ifs.seekg(0, std::ios::beg);

    auto size = std::size_t(end - ifs.tellg());

    if(size > 0) { // avoid undefined behavior
      Bytes buffer(size);

      if(ifs.read((char*)buffer.data(), buffer.size())) {
        return buffer;
      }
    }
  } else {
    std::cerr << "Unable to read file " << path << std::endl;
    exit(EXIT_FAILURE);
  }

  return {};
}

uint32_t castBytesInFile(const std::string &path) {
  Bytes offset = loadBinaryFile(path);
  if (offset.size() == 4) {
    std::reverse(offset.begin(), offset.end());
    return *reinterpret_cast<uint32_t*>(offset.data());
  }

  return 0;
}

uint32_t castBytesInFile(const std::string &path, std::uint32_t offset) {
  Bytes data = readBlock(offset, sizeof(uint32_t), path);
  if (data.size()== 4) {
    std::reverse(data.begin(), data.end());
    return *reinterpret_cast<uint32_t*>(data.data());
  }
  return 0;
}

std::string getKey(const std::string &key)
{
  std::string result;

  const std::string efusekeyPathStr = "/sys/firmware/devicetree/base/efuse";
  const std::filesystem::path path { efusekeyPathStr };
  std::error_code ec;
  for (const auto& dirEntry : std::filesystem::directory_iterator(path, ec)) {
    if (ec) {
      std::cerr << "Error when iterate " << efusekeyPathStr << ": error code:" << ec.value() << " error message: " << ec.message() << std::endl;
      exit(EXIT_FAILURE);
      continue;
    }
    const auto filenameStr = dirEntry.path().filename().string();
    //std::cout << "Iterating " << filenameStr << " and flag: " << startsWithKeyUnderscore << std::endl;
    if (dirEntry.is_directory()) {
      const auto keynamePathStr = (efusekeyPathStr + "/" + filenameStr + "/name");
      const auto keyname = loadFileAsLine(keynamePathStr);
      //std::cout << keynamePathStr << " == '" << keyname << "'" << std::endl;
      if (keyname == key) {
        const uint32_t offset = castBytesInFile(efusekeyPathStr + "/" + filenameStr + "/reg", 0);
        const uint32_t size = castBytesInFile(efusekeyPathStr + "/" + filenameStr + "/reg", 4);
        //std::cout << "offset == " << offset << std::endl;
        //std::cout << "size == " << size << std::endl;
        if (!(offset == 0 && size == 0)) {
          Bytes keyValue = readBlock(offset, size, "/sys/devices/platform/efuse/efuse0/nvmem");
          if (keyValue.size() > 0) {
            result.resize(keyValue.size(), '\0');
            std::transform(
              keyValue.begin(), keyValue.end(), result.begin(),
              [] (std::byte b) {
                return std::to_integer<char>(b);
              }
            );
            result = result;
          }
        }
        break;
      }
    }
  }
  if (ec) {
    std::cerr << "Error when iterate " << efusekeyPathStr << ": error code:" << ec.value() << " error message: " << ec.message() << std::endl;
    exit(EXIT_FAILURE);
  }

  return result;
}
