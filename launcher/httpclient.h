#pragma once

#include <filesystem>
#include <functional>
#include <string>

#include <nlohmann/json.hpp>

struct HttpResult {
    bool success = false;
    std::string error;
    std::string body; // populated by postJson only
};

// Thin wrapper over httplib. Deliberately does not expose anything that
// could disable certificate/hostname verification -- non-https URLs are
// rejected outright unless allowInsecureHttp is explicitly set (local
// smoke-testing only, never set by the shipped launcher.cfg template).
class HttpClient {
public:
    explicit HttpClient(std::string caCertPath = "");

    HttpResult postJson(const std::string& url, const nlohmann::json& body, bool allowInsecureHttp);

    using ProgressCallback = std::function<void(int percent)>; // -1 = indeterminate
    HttpResult downloadToFile(const std::string& url, const std::filesystem::path& destPath,
                               const ProgressCallback& onProgress, bool allowInsecureHttp);

private:
    std::string m_caCertPath;
};
