# Built standalone against an unpacked release archive:
#   cmake -B build -DCMAKE_PREFIX_PATH=<unpacked artifact root>
cmake_minimum_required(VERSION 3.16)
project(msquic_openssl_smoke C)

# Cross builds (ios/android) restrict find_package to the target sysroot;
# the unpacked artifact lives outside it (consumers need this too)
if(CMAKE_CROSSCOMPILING)
    set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)
endif()

find_package(msquic-openssl CONFIG REQUIRED)

add_executable(smoke smoke.c)
target_link_libraries(smoke PRIVATE msquic::msquic msquic::crypto)
