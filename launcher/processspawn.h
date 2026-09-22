#pragma once

#include <filesystem>
#include <string>
#include <vector>

// Standalone (no framework/Platform dependency): POSIX branch mirrors
// src/framework/platform/unixplatform.cpp's spawnProcess (fork+execv),
// Windows branch mirrors src/framework/platform/win32platform.cpp's
// (ShellExecuteW, verb "open").
bool spawnProcess(const std::filesystem::path& executable, const std::vector<std::string>& args);

// Sets the owner/group/other execute bits on POSIX (no-op on Windows, where
// executability is inferred from the .exe extension, not a permission bit).
// This is the fix for the confirmed bug where the existing in-process
// updater (ResourceManager::updateExecutable) never does this, causing
// execv() to fail silently on Linux.
void makeExecutable(const std::filesystem::path& path);
