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

    // Returns true if the client was successfully spawned (or an update-free
    // run completed and the client was launched). False means a fatal error
    // was already reported via IUi and the caller should exit non-zero.
    bool run();

private:
    LauncherConfig m_config;
    std::filesystem::path m_launcherDir;
    std::filesystem::path m_launcherPath;
    IUi& m_ui;
};
