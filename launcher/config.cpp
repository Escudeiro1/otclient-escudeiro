#include "config.h"

#include <fstream>
#include <sstream>

namespace {

std::string trim(const std::string& s)
{
    const auto start = s.find_first_not_of(" \t\r\n");
    if (start == std::string::npos)
        return "";
    const auto end = s.find_last_not_of(" \t\r\n");
    return s.substr(start, end - start + 1);
}

} // namespace

std::optional<LauncherConfig> loadConfig(const std::filesystem::path& configPath, std::string& error)
{
    std::ifstream file(configPath);
    if (!file.is_open()) {
        error = "launcher.cfg not found (expected at " + configPath.string() + ")";
        return std::nullopt;
    }

    LauncherConfig config;
    std::string line;
    while (std::getline(file, line)) {
        const auto trimmed = trim(line);
        if (trimmed.empty() || trimmed.front() == '#')
            continue;

        const auto eq = trimmed.find('=');
        if (eq == std::string::npos)
            continue;

        const auto key = trim(trimmed.substr(0, eq));
        const auto value = trim(trimmed.substr(eq + 1));

        if (key == "update_url")
            config.updateUrl = value;
        else if (key == "client_executable" && !value.empty())
            config.clientExecutable = value;
        else if (key == "client_args")
            config.clientArgs = value;
        else if (key == "ca_cert_path")
            config.caCertPath = value;
        else if (key == "allow_insecure_http")
            config.allowInsecureHttp = (value == "1" || value == "true");
    }

    if (config.updateUrl.empty()) {
        error = "launcher.cfg is missing a value for update_url";
        return std::nullopt;
    }

    return config;
}
