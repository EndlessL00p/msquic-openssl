# 3.21: CMakePresets.json schema version 3 (toolchainFile field)
cmake_minimum_required(VERSION 3.21)

# The MsQuic release this project wraps. Artifact tags are <MSQUIC_TAG>-<rev>.
set(MSQUIC_TAG "v2.6.1" CACHE STRING "MsQuic release tag to build")

project(msquic-openssl LANGUAGES C CXX)

get_property(_multi_config GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(NOT _multi_config AND NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)
endif()

# MsQuic build configuration: static, OpenSSL TLS stack (the real thing, built
# from MsQuic's submodules/openssl pin via OpenSSL 3.5's native QUIC TLS API),
# nothing else. The flag set itself (the no-* list) is MsQuic's own, in its
# submodules/CMakeLists.txt - not restated here, so it cannot drift.
set(QUIC_TLS_LIB "openssl" CACHE STRING "" FORCE)
set(QUIC_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(QUIC_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(QUIC_BUILD_TEST OFF CACHE BOOL "" FORCE)
set(QUIC_BUILD_PERF OFF CACHE BOOL "" FORCE)

include(FetchContent)
FetchContent_Declare(msquic
    GIT_REPOSITORY https://github.com/microsoft/msquic.git
    GIT_TAG ${MSQUIC_TAG}
    GIT_SHALLOW TRUE)
FetchContent_MakeAvailable(msquic)

# MsQuic's src/core/CMakeLists.txt turns on /analyze (PREfast) for the `core`
# target on MSVC, paired with its own blanket /WX. We only consume the
# compiled output, not MsQuic's dev-time static analysis, so a newer MSVC
# toolset flagging a fresh PREfast false positive there (the toolset version
# isn't pinned by this project) shouldn't be able to break our build.
# /analyze- after /analyze on the command line turns analysis back off for
# this target.
if(MSVC AND TARGET core)
    target_compile_options(core PRIVATE /analyze-)
endif()

#----------------------------------------------------------------------------------
# Exported interface - identical target names in source mode (this file) and
# artifact mode (cmake/msquic-openssl-config.cmake in release archives), so
# consumers write one consumption path.
#
#   msquic::msquic - the QUIC library (TLS stack included) + msquic headers +
#                    platform link requirements
#   msquic::crypto - the bundled OpenSSL libcrypto + openssl headers, for
#                    consumers doing their own certificate work
#----------------------------------------------------------------------------------

add_library(msquic::msquic INTERFACE IMPORTED GLOBAL)
target_link_libraries(msquic::msquic INTERFACE msquic)
target_include_directories(msquic::msquic INTERFACE ${msquic_SOURCE_DIR}/src/inc)
if(WIN32)
    # The combined static msquic.lib needs the system import libraries MsQuic
    # links internally (base_link in MsQuic's src/inc/CMakeLists.txt)
    target_link_libraries(msquic::msquic INTERFACE
        ws2_32 schannel ntdll bcrypt ncrypt crypt32 iphlpapi advapi32)
elseif(NOT APPLE)
    find_package(Threads REQUIRED)
    target_link_libraries(msquic::msquic INTERFACE Threads::Threads ${CMAKE_DL_LIBS} m)
endif()

# The combined library already contains every libssl/libcrypto object, so
# crypto is headers + the same library
add_library(msquic::crypto INTERFACE IMPORTED GLOBAL)
target_link_libraries(msquic::crypto INTERFACE OpenSSLQuic msquic::msquic)

# Packaging (standalone builds only): `cmake --install` assembles the
# artifact layout; scripts/build.ps1 drives it and produces the archive
if(CMAKE_SOURCE_DIR STREQUAL CMAKE_CURRENT_SOURCE_DIR)
    include(cmake/package.cmake)
endif()
