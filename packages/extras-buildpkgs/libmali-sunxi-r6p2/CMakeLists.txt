cmake_minimum_required(VERSION 2.6)
include(GNUInstallDirs)
project(libmali-sunxi)

if(${CMAKE_LIBRARY_ARCHITECTURE} STREQUAL "aarch64-linux-gnu")
        set(ARCH "arm64")
elseif(${CMAKE_LIBRARY_ARCHITECTURE} STREQUAL "arm-linux-gnueabihf")
        set(ARCH "arm")
else()
        message(SEND_ERROR "Unsupported architecture")
endif(${CMAKE_LIBRARY_ARCHITECTURE} STREQUAL "aarch64-linux-gnu")

INSTALL(DIRECTORY
"${CMAKE_CURRENT_SOURCE_DIR}/r6p2/${ARCH}/"
DESTINATION "${CMAKE_INSTALL_LIBDIR}/${CMAKE_LIBRARY_ARCHITECTURE}")
