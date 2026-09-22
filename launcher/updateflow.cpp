#include "updateflow.h"

#include "httpclient.h"
#include "manifest.h"
#include "processspawn.h"
#include "selfupdate.h"
#include "sha256.h"

#include <nlohmann/json.hpp>

#include <set>
#include <sstream>
#include <vector>

namespace {

constexpr int kMaxRetries = 5;

#if defined(_WIN32)
constexpr const char* kOs = "windows";
#elif defined(__APPLE__)
constexpr const char* kOs = "macos";
#else
constexpr const char* kOs = "linux";
#endif
constexpr const char* kArch = "x86_64";

std::string joinUrl(const std::string& base, const std::string& relative)
{
    if (base.empty())
        return relative;
    const bool baseHasSlash = base.back() == '/';
    const bool relHasSlash = !relative.empty() && relative.front() == '/';
    if (baseHasSlash && relHasSlash)
        return base + relative.substr(1);
    if (!baseHasSlash && !relHasSlash)
        return base + "/" + relative;
    return base + relative;
}

std::vector<std::string> splitArgs(const std::string& args)
{
    std::vector<std::string> result;
    std::istringstream stream(args);
    std::string token;
    while (stream >> token)
        result.push_back(token);
    return result;
}

// Downloads to a `.part` sibling of `finalPath`, verifying the checksum
// before renaming it into place, retrying the whole download on any failure
// (a corrupt or truncated partial file is never left where launchCorrect()/
// the client would find it).
bool downloadAndVerify(HttpClient& http, const std::string& url, const std::filesystem::path& finalPath,
                        const std::string& expectedChecksum, IUi& ui, bool allowInsecureHttp)
{
    const auto tmpPath = std::filesystem::path(finalPath.string() + ".part");
    std::error_code ec;
    std::filesystem::create_directories(finalPath.parent_path(), ec);

    for (int attempt = 1; attempt <= kMaxRetries; ++attempt) {
        ui.reportStatus("Downloading " + finalPath.filename().string() +
                         (attempt > 1 ? " (retry " + std::to_string(attempt) + ")" : ""));

        const auto result = http.downloadToFile(url, tmpPath,
            [&ui](int percent) { ui.reportProgress(percent); }, allowInsecureHttp);

        if (result.success && sha256File(tmpPath) == expectedChecksum) {
            std::filesystem::remove(finalPath, ec);
            std::filesystem::rename(tmpPath, finalPath, ec);
            if (!ec)
                return true;
        }

        std::filesystem::remove(tmpPath, ec);
    }

    ui.reportFatalError("Failed to download " + finalPath.filename().string() + " after " +
                         std::to_string(kMaxRetries) + " attempts");
    return false;
}

// Removes local files that are no longer part of the manifest, restricted to
// the top-level directories the manifest itself references (e.g. "data/") --
// deliberately never a full scan of the launcher directory, so a malformed
// or malicious manifest can't be used to make the launcher delete arbitrary
// unrelated files such as its own config or executables.
void cleanupStaleFiles(const std::filesystem::path& launcherDir, const Manifest& manifest, IUi& ui)
{
    std::set<std::string> topLevelDirs;
    for (const auto& [relativePath, checksum] : manifest.files) {
        const auto slash = relativePath.find('/');
        if (slash != std::string::npos)
            topLevelDirs.insert(relativePath.substr(0, slash));
    }

    for (const auto& topLevel : topLevelDirs) {
        const auto dir = launcherDir / topLevel;
        std::error_code ec;
        if (!std::filesystem::exists(dir, ec))
            continue;

        for (auto it = std::filesystem::recursive_directory_iterator(dir, ec);
             !ec && it != std::filesystem::recursive_directory_iterator(); ++it) {
            if (it->is_directory())
                continue;

            auto relative = std::filesystem::relative(it->path(), launcherDir, ec).generic_string();
            if (ec || manifest.files.contains(relative))
                continue;

            std::error_code removeEc;
            if (std::filesystem::remove(it->path(), removeEc))
                ui.reportStatus("Removed stale file " + relative);
        }
    }
}

} // namespace

UpdateFlow::UpdateFlow(LauncherConfig config, std::filesystem::path launcherDir,
                        std::filesystem::path launcherPath, IUi& ui)
    : m_config(std::move(config))
    , m_launcherDir(std::move(launcherDir))
    , m_launcherPath(std::move(launcherPath))
    , m_ui(ui)
{
}

bool UpdateFlow::run()
{
    const auto clientPath = m_launcherDir / m_config.clientExecutable;

    HttpClient http(m_config.caCertPath);

    m_ui.reportStatus("Checking for updates...");

    nlohmann::json request = {
        { "clientChecksum", sha256File(clientPath) },
        { "launcherChecksum", sha256File(m_launcherPath) },
        { "os", kOs },
        { "arch", kArch },
    };

    const auto response = http.postJson(m_config.updateUrl, request, m_config.allowInsecureHttp);
    if (!response.success) {
        m_ui.reportFatalError("Update check failed: " + response.error);
        return false;
    }

    const auto manifest = parseManifest(response.body);
    if (!manifest.error.empty()) {
        m_ui.reportFatalError("Update server error: " + manifest.error);
        return false;
    }

    for (const auto& [relativePath, expectedChecksum] : manifest.files) {
        const auto finalPath = m_launcherDir / relativePath;
        if (sha256File(finalPath) == expectedChecksum)
            continue;

        const auto url = joinUrl(manifest.baseUrl, relativePath);
        if (!downloadAndVerify(http, url, finalPath, expectedChecksum, m_ui, m_config.allowInsecureHttp))
            return false;
    }

    if (!manifest.keepFiles)
        cleanupStaleFiles(m_launcherDir, manifest, m_ui);

    if (manifest.client && sha256File(clientPath) != manifest.client->checksum) {
        const auto url = joinUrl(manifest.baseUrl, manifest.client->file);
        if (!downloadAndVerify(http, url, clientPath, manifest.client->checksum, m_ui, m_config.allowInsecureHttp))
            return false;
        makeExecutable(clientPath);
        m_ui.reportStatus("Client updated");
    }

    if (manifest.launcher && sha256File(m_launcherPath) != manifest.launcher->checksum) {
        const auto stagingPath = std::filesystem::path(m_launcherPath.string() + ".new");
        const auto url = joinUrl(manifest.baseUrl, manifest.launcher->file);
        if (!downloadAndVerify(http, url, stagingPath, manifest.launcher->checksum, m_ui, m_config.allowInsecureHttp))
            return false;

        if (!stageLauncherSelfUpdate(m_launcherPath, stagingPath))
            m_ui.reportStatus("Warning: failed to stage launcher self-update");

        std::error_code ec;
        std::filesystem::remove(stagingPath, ec);
        m_ui.reportStatus("Launcher will update on next start");
    }

    m_ui.reportStatus("Starting client...");
    if (!spawnProcess(clientPath, splitArgs(m_config.clientArgs))) {
        m_ui.reportFatalError("Failed to start client: " + clientPath.string());
        return false;
    }

    return true;
}
