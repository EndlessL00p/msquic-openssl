# Artifact assembly: `cmake --install <build> --prefix <stage>` produces the
# release layout. On Windows, install both configs into the same prefix
# (lib/debug + lib/release). scripts/build.ps1 drives this.

set(MSQUIC_BUILD_DIR ${CMAKE_BINARY_DIR}/_deps/msquic-build)
set(QUICTLS_DIR ${CMAKE_BINARY_DIR}/_deps/opensslquic-build/quictls)

# MsQuic public headers at include/ root; quictls headers under include/openssl
install(DIRECTORY ${msquic_SOURCE_DIR}/src/inc/ DESTINATION include
        FILES_MATCHING PATTERN "*.h" PATTERN "*.hpp")

if(WIN32)
    install(DIRECTORY ${QUICTLS_DIR}/release/include/openssl DESTINATION include)
    # Both CRT flavors: static libs bake in /MD vs /MDd, so Debug consumers
    # need a Debug library
    install(FILES ${MSQUIC_BUILD_DIR}/bin/$<CONFIG>/msquic.lib
            DESTINATION lib/$<IF:$<CONFIG:Debug>,debug,release>)
else()
    install(DIRECTORY ${QUICTLS_DIR}/include/openssl DESTINATION include)
    install(FILES ${MSQUIC_BUILD_DIR}/bin/$<CONFIG>/${CMAKE_STATIC_LIBRARY_PREFIX}msquic${CMAKE_STATIC_LIBRARY_SUFFIX}
            DESTINATION lib)
endif()

install(FILES ${CMAKE_CURRENT_SOURCE_DIR}/cmake/msquic-openssl-config.cmake
        DESTINATION lib/cmake/msquic-openssl)
install(FILES ${msquic_SOURCE_DIR}/LICENSE
        DESTINATION LICENSES RENAME msquic-LICENSE)
install(FILES ${msquic_SOURCE_DIR}/submodules/quictls/LICENSE.txt
        DESTINATION LICENSES RENAME quictls-LICENSE)

# MsQuic's own install() rules run too and leave a share/msquic config that
# doesn't apply to this layout; drop it (this rule runs after MsQuic's)
install(CODE "file(REMOVE_RECURSE \"\${CMAKE_INSTALL_PREFIX}/share\")")
