# msquic-openssl: imported targets for the prebuilt static artifact.
# Same target names as the source build (top-level CMakeLists.txt), so
# consumers don't care which mode they got:
#
#   msquic::msquic - the QUIC library (TLS stack included) + msquic headers +
#                    platform link requirements
#   msquic::crypto - the bundled OpenSSL libcrypto + openssl headers
#
# The archive is per-platform, so platform checks here always match.

if(TARGET msquic::msquic)
    return()
endif()

get_filename_component(_mq_root "${CMAKE_CURRENT_LIST_DIR}/../../.." ABSOLUTE)

add_library(msquic::msquic STATIC IMPORTED)
set_target_properties(msquic::msquic PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${_mq_root}/include"
    INTERFACE_COMPILE_DEFINITIONS "QUIC_BUILD_STATIC")

if(WIN32)
    # Both CRT flavors ship; multi-config generators pick per build config
    set_target_properties(msquic::msquic PROPERTIES
        IMPORTED_CONFIGURATIONS "RELEASE;DEBUG"
        IMPORTED_LOCATION_RELEASE "${_mq_root}/lib/release/msquic.lib"
        IMPORTED_LOCATION_DEBUG "${_mq_root}/lib/debug/msquic.lib"
        MAP_IMPORTED_CONFIG_MINSIZEREL Release
        MAP_IMPORTED_CONFIG_RELWITHDEBINFO Release)
    # The system import libraries MsQuic links internally (base_link in
    # MsQuic's src/inc/CMakeLists.txt)
    set_property(TARGET msquic::msquic APPEND PROPERTY INTERFACE_LINK_LIBRARIES
        ws2_32 schannel ntdll bcrypt ncrypt crypt32 iphlpapi advapi32)
else()
    set_target_properties(msquic::msquic PROPERTIES
        IMPORTED_LOCATION "${_mq_root}/lib/libmsquic.a")
    if(APPLE)
        set_property(TARGET msquic::msquic APPEND PROPERTY INTERFACE_LINK_LIBRARIES
            "-framework CoreFoundation" "-framework Security")
    else()
        include(CMakeFindDependencyMacro)
        find_dependency(Threads)
        set_property(TARGET msquic::msquic APPEND PROPERTY INTERFACE_LINK_LIBRARIES
            Threads::Threads ${CMAKE_DL_LIBS} m)
    endif()
endif()

# The combined library already contains every libssl/libcrypto object, so
# crypto is headers + the same library
add_library(msquic::crypto INTERFACE IMPORTED)
set_target_properties(msquic::crypto PROPERTIES
    INTERFACE_INCLUDE_DIRECTORIES "${_mq_root}/include")
set_property(TARGET msquic::crypto APPEND PROPERTY INTERFACE_LINK_LIBRARIES msquic::msquic)
