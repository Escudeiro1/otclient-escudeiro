# Imported targets from find_package() are directory-scoped: src/CMakeLists.txt's
# calls do not propagate to this sibling directory, so re-resolve them here
# (cheap -- vcpkg has already installed everything via the src/ build).
find_package(OpenSSL REQUIRED)
find_package(nlohmann_json REQUIRED)
find_package(httplib CONFIG REQUIRED)
find_package(SDL2 REQUIRED)
find_package(SDL2_image CONFIG REQUIRED)
find_package(SDL2_ttf CONFIG REQUIRED)
find_package(ZLIB REQUIRED)

add_executable(otclient-launcher
    main.cpp
    config.h config.cpp
    sha256.h sha256.cpp
    httpclient.h httpclient.cpp
    manifest.h manifest.cpp
    updateflow.h updateflow.cpp
    selfupdate.h selfupdate.cpp
    processspawn.h processspawn.cpp
    archive.h archive.cpp
    ui.h
    consoleui.h consoleui.cpp
    guiui.h guiui.cpp
    window.h window.cpp
    ../src/framework/core/minizip/unzip.c
    ../src/framework/core/minizip/unzip.h
    ../src/framework/core/minizip/ioapi.c
    ../src/framework/core/minizip/ioapi.h
    ../src/framework/core/minizip/crypt.c
    ../src/framework/core/minizip/crypt.h
)

# Reusing the client's own vendored minizip sources directly (not copying
# them) for zip extraction -- plain C, no PhysFS/framework dependency, so
# safe to compile standalone into the launcher. unzip.h does `#include
# "ioapi.h"` (same-directory relative include), so that directory needs to
# be on the include path.
target_include_directories(otclient-launcher PRIVATE ../src/framework/core/minizip)

# CMAKE_CXX_STANDARD set by src/CMakeLists.txt does not propagate to this
# sibling directory (no PARENT_SCOPE), so mirror its logic here directly.
if(MSVC)
    set(OTCLIENT_LAUNCHER_CXX_STANDARD 20)
else()
    set(OTCLIENT_LAUNCHER_CXX_STANDARD 23)
endif()

set_target_properties(otclient-launcher PROPERTIES
    CXX_STANDARD ${OTCLIENT_LAUNCHER_CXX_STANDARD}
    CXX_STANDARD_REQUIRED ON)

# vcpkg's SDL2-family ports publish either a shared or a `-static` suffixed
# target depending on the triplet (this repo's Windows preset uses a static
# triplet); these generator expressions pick whichever actually exists,
# matching the exact usage vcpkg itself prints for these three ports.
target_link_libraries(otclient-launcher PRIVATE
    OpenSSL::SSL
    OpenSSL::Crypto
    nlohmann_json::nlohmann_json
    httplib::httplib
    $<TARGET_NAME_IF_EXISTS:SDL2::SDL2main>
    $<IF:$<TARGET_EXISTS:SDL2::SDL2>,SDL2::SDL2,SDL2::SDL2-static>
    $<IF:$<TARGET_EXISTS:SDL2_image::SDL2_image>,SDL2_image::SDL2_image,SDL2_image::SDL2_image-static>
    $<IF:$<TARGET_EXISTS:SDL2_ttf::SDL2_ttf>,SDL2_ttf::SDL2_ttf,SDL2_ttf::SDL2_ttf-static>
    ZLIB::ZLIB)

if(WIN32 AND EXISTS "${CMAKE_SOURCE_DIR}/cmake/icon/otcicon.rc")
    target_sources(otclient-launcher PRIVATE ${CMAKE_SOURCE_DIR}/cmake/icon/otcicon.rc)
endif()

if(NOT OTCLIENT_BUILD_LAUNCHER)
    set_target_properties(otclient-launcher PROPERTIES EXCLUDE_FROM_ALL ON)
endif()

# Mirror TOGGLE_BIN_FOLDER so the launcher always lands next to the client
# binary (see src/CMakeLists.txt's own handling of this option).
if(TOGGLE_BIN_FOLDER)
    set_target_properties(otclient-launcher PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
else()
    set_target_properties(otclient-launcher PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/")
endif()

# Copy the launcher's own UI assets (background image, font) next to the
# built binary, wherever it actually lands (mirrors how launcher.cfg is
# resolved at runtime via the executable's own directory).
add_custom_command(TARGET otclient-launcher POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
        "${CMAKE_CURRENT_SOURCE_DIR}/assets"
        "$<TARGET_FILE_DIR:otclient-launcher>/assets"
)
