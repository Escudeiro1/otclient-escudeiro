#pragma once

#include <filesystem>
#include <string>
#include <vector>

// Standalone reimplementation of ResourceManager::launchCorrect()
// (src/framework/core/resourcemanager.cpp:1197-1274). Must be the first
// thing main() does, before any config/network activity: if a newer sibling
// launcher binary (written by a previous run's stageLauncherSelfUpdate) is
// found, this spawns it and returns true -- the caller must exit immediately
// without doing any update-check work in that case.
bool applySelfUpdateIfPending(const std::filesystem::path& currentLauncherPath,
                               const std::vector<std::string>& args);

// Writes `sourcePath`'s content as a timestamped sibling of `currentLauncherPath`
// (same naming scheme as ResourceManager::updateExecutable), setting the
// executable bit on POSIX so it's launchable without a prior chmod step. The
// currently-running launcher file itself is never touched.
bool stageLauncherSelfUpdate(const std::filesystem::path& currentLauncherPath,
                              const std::filesystem::path& sourcePath);
