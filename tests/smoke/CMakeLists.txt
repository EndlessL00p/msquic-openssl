# Built standalone against an unpacked release archive:
#   cmake -B build -DCMAKE_PREFIX_PATH=<unpacked artifact root>
cmake_minimum_required(VERSION 3.16)
project(msquic_openssl_smoke C)

find_package(msquic-openssl CONFIG REQUIRED)

add_executable(smoke smoke.c)
target_link_libraries(smoke PRIVATE msquic::msquic msquic::crypto)
