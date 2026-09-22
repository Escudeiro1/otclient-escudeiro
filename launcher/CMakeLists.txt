# Imported targets from find_package() are directory-scoped: src/CMakeLists.txt's
# calls do not propagate to this sibling directory, so re-resolve them here
# (cheap -- vcpkg has already installed everything via the src/ build).
find_package(OpenSSL REQUIRED)
find_package(nlohmann_json REQUIRED)
find_package(httplib CONFIG REQUIRED)

add_executable(otclient-launcher
    main.cpp
    config.h config.cpp
    sha256.h sha256.cpp
    httpclient.h httpclient.cpp
    manifest.h manifest.cpp
    updateflow.h updateflow.cpp
    selfupdate.h selfupdate.cpp
    processspawn.h processspawn.cpp
    ui.h
    consoleui.h consoleui.cpp
)

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

target_link_libraries(otclient-launcher PRIVATE
    OpenSSL::SSL
    OpenSSL::Crypto
    nlohmann_json::nlohmann_json
    httplib::httplib)

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
