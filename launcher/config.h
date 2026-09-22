#pragma once

#include <filesystem>
#include <optional>
#include <string>

struct LauncherConfig {
    std::string updateUrl;
    std::string clientExecutable = "otclient";
    std::string clientArgs;
    std::string caCertPath;
    bool allowInsecureHttp = false; // local-testing escape hatch only, never set by the shipped template
};

// Reads a plain key=value file (see launcher.cfg). Returns std::nullopt and
// fills `error` if the file is missing, unreadable, or update_url is empty --
// on purpose, no default update_url is ever assumed.
std::optional<LauncherConfig> loadConfig(const std::filesystem::path& configPath, std::string& error);
