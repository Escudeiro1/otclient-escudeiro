#include "config.h"
#include "consoleui.h"
#include "selfupdate.h"
#include "updateflow.h"

#include <filesystem>
#include <vector>

#if defined(_WIN32)
#include <windows.h>
#elif defined(__APPLE__)
#include <mach-o/dyld.h>
#else
#include <unistd.h>
#endif

namespace {

// The launcher must know its own real path (not argv[0], which can be a
// relative path, a symlink, or just "otclient-launcher" if found via PATH)
// so applySelfUpdateIfPending() and UpdateFlow can reliably resolve sibling
// files and the launcher's own directory.
std::filesystem::path getExecutablePath()
{
#if defined(_WIN32)
    std::vector<wchar_t> buffer(MAX_PATH);
    while (true) {
        const DWORD len = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
        if (len == 0)
            return {};
        if (len < buffer.size())
            return std::filesystem::path(buffer.data(), buffer.data() + len);
        buffer.resize(buffer.size() * 2);
    }
#elif defined(__APPLE__)
    uint32_t size = 0;
    _NSGetExecutablePath(nullptr, &size);
    std::vector<char> buffer(size);
    if (_NSGetExecutablePath(buffer.data(), &size) != 0)
        return {};
    std::error_code ec;
    return std::filesystem::canonical(std::filesystem::path(buffer.data()), ec);
#else
    std::error_code ec;
    return std::filesystem::canonical("/proc/self/exe", ec);
#endif
}

} // namespace

int main(int argc, char** argv)
{
    const auto launcherPath = getExecutablePath();
    if (launcherPath.empty()) {
        ConsoleUi().reportFatalError("Could not determine launcher's own executable path");
        return 1;
    }
    const auto launcherDir = launcherPath.parent_path();

    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i)
        args.emplace_back(argv[i]);

    // Must run before any config/network activity: if a previous run staged
    // a newer launcher binary, relaunch it and exit without doing anything
    // else in this (now stale) process.
    if (applySelfUpdateIfPending(launcherPath, args))
        return 0;

    ConsoleUi ui;

    std::string error;
    const auto config = loadConfig(launcherDir / "launcher.cfg", error);
    if (!config) {
        ui.reportFatalError(error);
        return 1;
    }

    UpdateFlow flow(*config, launcherDir, launcherPath, ui);
    return flow.run() ? 0 : 1;
}
