#include "config.h"
#include "consoleui.h"
#include "guiui.h"
#include "selfupdate.h"
#include "updateflow.h"
#include "window.h"

#include <filesystem>
#include <thread>
#include <vector>

#if defined(_WIN32)
#include <windows.h>
#endif

namespace {

// On POSIX, deliberately mirrors ResourceManager::init() (resourcemanager.cpp)
// -- std::filesystem::absolute(argv0), NOT a canonical/proc-self-exe
// resolution. otclient itself resolves its own directory this way, which is
// exactly why a dev symlink such as `./otclient -> build/.../otclient` works:
// the client treats the symlink's own location as home, not the real file's.
// Using canonical() here instead would make `./otclient-launcher` behave
// differently from `./otclient` -- looking for launcher.cfg and data files
// inside the build tree instead of next to the symlink.
#if defined(_WIN32)
std::filesystem::path getExecutablePath(const char*)
{
    std::vector<wchar_t> buffer(MAX_PATH);
    while (true) {
        const DWORD len = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
        if (len == 0)
            return {};
        if (len < buffer.size())
            return std::filesystem::path(buffer.data(), buffer.data() + len);
        buffer.resize(buffer.size() * 2);
    }
}
#else
std::filesystem::path getExecutablePath(const char* argv0)
{
    return std::filesystem::absolute(argv0);
}
#endif

} // namespace

int main(int argc, char** argv)
{
    const auto launcherPath = getExecutablePath(argv[0]);
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

    std::string error;
    const auto config = loadConfig(launcherDir / "launcher.cfg", error);
    if (!config) {
        // No window yet at this point -- report to the console instead.
        ConsoleUi().reportFatalError(error);
        return 1;
    }

    Window window;
    if (!window.init(launcherDir / "assets")) {
        ConsoleUi().reportFatalError("Failed to initialize launcher window (see stderr above for details)");
        return 1;
    }

    GuiUi ui;
    UpdateFlow flow(*config, launcherDir, launcherPath, ui);

    // The update check starts the instant the window opens, on a background
    // thread, so the render loop stays responsive throughout. The Play
    // button only becomes clickable once ui.isReady() is set (see Window::
    // runEventLoop / GuiUi::setReady).
    std::thread worker([&flow, &ui] {
        const bool upToDate = flow.checkAndApplyUpdates();
        ui.setReady(upToDate);
    });

    window.runEventLoop(ui, [&flow] { return flow.spawnClient(); });

    // The window can close before the worker finishes (e.g. mid-download);
    // join rather than detach so `flow`/`ui` outlive their last use.
    // HttpClient's bounded connect/read timeouts keep this from hanging
    // indefinitely.
    worker.join();

    return 0;
}
