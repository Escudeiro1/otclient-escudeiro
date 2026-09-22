#pragma once

#include "config.h"
#include "ui.h"

#include <filesystem>

// Orchestrates a single launcher run: check for updates, apply them, spawn
// the client. All status/progress/error reporting goes through IUi so a
// future real UI can replace ConsoleUi without touching this logic.
class UpdateFlow {
public:
    UpdateFlow(LauncherConfig config, std::filesystem::path launcherDir,
               std::filesystem::path launcherPath, IUi& ui);

    // Checks for and applies updates (data files, client executable, staged
    // launcher self-update) but does NOT spawn the client. Returns true only
    // if the client is now confirmed up to date and ready to run; false
    // means a fatal error was already reported via IUi. Split out from
    // spawnClient() so a GUI can gate a "Play" button's enabled state on
    // this call's result without also launching the client immediately.
    bool checkAndApplyUpdates();

    // Spawns the (now up to date) client. Only meaningful to call after
    // checkAndApplyUpdates() has returned true.
    bool spawnClient();

private:
    LauncherConfig m_config;
    std::filesystem::path m_launcherDir;
    std::filesystem::path m_launcherPath;
    IUi& m_ui;
};
