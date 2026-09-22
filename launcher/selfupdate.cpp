#include "selfupdate.h"

#include "processspawn.h"

#include <algorithm>
#include <chrono>
#include <cctype>

namespace {

// Strips a trailing "-<timestamp>" suffix (as written by stageLauncherSelfUpdate),
// not just everything after the first dash: the launcher's own base name
// ("otclient-launcher") already contains a dash, and truncating at the first
// one would collapse it down to "otclient" -- colliding with the unrelated
// game client binary that lives in the same directory.
std::string normalizeName(std::string name)
{
    const auto dash = name.rfind('-');
    if (dash != std::string::npos) {
        const auto suffix = name.substr(dash + 1);
        const bool allDigits = !suffix.empty() &&
            std::ranges::all_of(suffix, [](unsigned char c) { return std::isdigit(c); });
        if (allDigits)
            name = name.substr(0, dash);
    }
    std::ranges::transform(name, name.begin(), [](unsigned char c) { return std::tolower(c); });
    return name;
}

} // namespace

bool applySelfUpdateIfPending(const std::filesystem::path& currentLauncherPath,
                               const std::vector<std::string>& args)
{
    const auto targetName = normalizeName(currentLauncherPath.stem().string());
    const auto dir = currentLauncherPath.parent_path();

    std::error_code ec;
    if (dir.empty() || !std::filesystem::exists(dir, ec) || ec)
        return false;

    auto lastWrite = std::filesystem::last_write_time(currentLauncherPath, ec);
    std::filesystem::path winner = currentLauncherPath;

    for (auto it = std::filesystem::directory_iterator(dir, ec);
         !ec && it != std::filesystem::directory_iterator(); ++it) {
        const auto& entry = *it;
        if (std::filesystem::is_directory(entry.path()))
            continue;
        if (normalizeName(entry.path().stem().string()) != targetName)
            continue;
        if (entry.path().extension() != currentLauncherPath.extension())
            continue;

        std::error_code writeEc;
        const auto writeTime = std::filesystem::last_write_time(entry.path(), writeEc);
        if (!writeEc && writeTime > lastWrite) {
            lastWrite = writeTime;
            winner = entry.path();
        }
    }
    if (ec)
        return false;

    // Clean up every matching file that isn't the winner, regardless of
    // whether the winner turns out to be the currently-running file.
    for (auto it = std::filesystem::directory_iterator(dir, ec);
         !ec && it != std::filesystem::directory_iterator(); ++it) {
        const auto& entry = *it;
        if (std::filesystem::is_directory(entry.path()))
            continue;
        if (normalizeName(entry.path().stem().string()) != targetName)
            continue;
        if (entry.path().extension() != currentLauncherPath.extension())
            continue;
        if (entry.path() == winner)
            continue;

        std::error_code removeEc;
        std::filesystem::remove(entry.path(), removeEc);
    }
    if (ec)
        return false;

    if (winner == currentLauncherPath)
        return false;

    spawnProcess(winner, args);
    return true;
}

bool stageLauncherSelfUpdate(const std::filesystem::path& currentLauncherPath,
                              const std::filesystem::path& sourcePath)
{
    const auto timestamp = std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();

    const auto stagedPath = currentLauncherPath.parent_path() /
        (currentLauncherPath.stem().string() + "-" + std::to_string(timestamp) + currentLauncherPath.extension().string());

    std::error_code ec;
    std::filesystem::copy_file(sourcePath, stagedPath, std::filesystem::copy_options::overwrite_existing, ec);
    if (ec)
        return false;

    makeExecutable(stagedPath);
    return true;
}
