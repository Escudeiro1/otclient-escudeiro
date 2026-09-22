#include "httpclient.h"

// Without this define, the vcpkg cpp-httplib port on this project installs
// without SSL support compiled in (verified: its exported CMake target's
// CPPHTTPLIB_OPENSSL_SUPPORT compile definition evaluates to false), which
// would silently make httplib::SSLClient unavailable. src/framework/net/
// httplogin.cpp works around the exact same gap the same way.
#ifndef CPPHTTPLIB_OPENSSL_SUPPORT
#    define CPPHTTPLIB_OPENSSL_SUPPORT
#endif
#include <httplib.h>

#include <fstream>
#include <regex>

namespace {

struct ParsedUrl {
    std::string scheme;
    std::string host;
    int port = 0;
    std::string path;
};

bool parseUrl(const std::string& url, ParsedUrl& out)
{
    static const std::regex re(R"(^(https?)://([^/:]+)(?::(\d+))?(/.*)?$)");
    std::smatch m;
    if (!std::regex_match(url, m, re))
        return false;

    out.scheme = m[1].str();
    out.host = m[2].str();
    out.port = m[3].matched ? std::stoi(m[3].str()) : (out.scheme == "https" ? 443 : 80);
    out.path = m[4].matched ? m[4].str() : "/";
    return true;
}

} // namespace

HttpClient::HttpClient(std::string caCertPath)
    : m_caCertPath(std::move(caCertPath))
{
}

HttpResult HttpClient::postJson(const std::string& url, const nlohmann::json& body, bool allowInsecureHttp)
{
    HttpResult result;

    ParsedUrl parsed;
    if (!parseUrl(url, parsed)) {
        result.error = "Malformed URL: " + url;
        return result;
    }
    if (parsed.scheme != "https" && !allowInsecureHttp) {
        result.error = "Refusing non-HTTPS update URL: " + url;
        return result;
    }

    const httplib::Headers headers = { {"Content-Type", "application/json"} };
    httplib::Result response;

    if (parsed.scheme == "https") {
        httplib::SSLClient client(parsed.host, parsed.port);
        if (!m_caCertPath.empty())
            client.set_ca_cert_path(m_caCertPath.c_str());
        client.set_connection_timeout(10);
        client.set_read_timeout(30);
        response = client.Post(parsed.path, headers, body.dump(), "application/json");
    } else {
        httplib::Client client(parsed.host, parsed.port);
        client.set_connection_timeout(10);
        client.set_read_timeout(30);
        response = client.Post(parsed.path, headers, body.dump(), "application/json");
    }

    if (!response) {
        result.error = "Failed to connect: " + httplib::to_string(response.error());
        return result;
    }
    if (response->status != 200) {
        result.error = "HTTP " + std::to_string(response->status);
        return result;
    }

    result.success = true;
    result.body = response->body;
    return result;
}

HttpResult HttpClient::downloadToFile(const std::string& url, const std::filesystem::path& destPath,
                                       const ProgressCallback& onProgress, bool allowInsecureHttp)
{
    HttpResult result;

    ParsedUrl parsed;
    if (!parseUrl(url, parsed)) {
        result.error = "Malformed URL: " + url;
        return result;
    }
    if (parsed.scheme != "https" && !allowInsecureHttp) {
        result.error = "Refusing non-HTTPS download URL: " + url;
        return result;
    }

    std::ofstream out(destPath, std::ios::binary | std::ios::trunc);
    if (!out.is_open()) {
        result.error = "Cannot open " + destPath.string() + " for writing";
        return result;
    }

    const httplib::ContentReceiver contentReceiver = [&out](const char* data, size_t len) {
        out.write(data, static_cast<std::streamsize>(len));
        return static_cast<bool>(out);
    };

    const httplib::DownloadProgress progressReceiver = [&onProgress](size_t current, size_t total) {
        if (onProgress)
            onProgress(total > 0 ? static_cast<int>((current * 100) / total) : -1);
        return true;
    };

    httplib::Result response;
    if (parsed.scheme == "https") {
        httplib::SSLClient client(parsed.host, parsed.port);
        if (!m_caCertPath.empty())
            client.set_ca_cert_path(m_caCertPath.c_str());
        client.set_connection_timeout(10);
        client.set_read_timeout(120);
        response = client.Get(parsed.path, contentReceiver, progressReceiver);
    } else {
        httplib::Client client(parsed.host, parsed.port);
        client.set_connection_timeout(10);
        client.set_read_timeout(120);
        response = client.Get(parsed.path, contentReceiver, progressReceiver);
    }

    out.close();

    if (!response) {
        result.error = "Failed to connect: " + httplib::to_string(response.error());
        return result;
    }
    if (response->status != 200) {
        result.error = "HTTP " + std::to_string(response->status);
        return result;
    }

    result.success = true;
    return result;
}
