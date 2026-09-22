#pragma once

#include <filesystem>
#include <string>

// Extracts a zip file to destDir, creating it fresh (any existing directory
// at destDir is removed first, so a re-extraction can never leave stale
// files from a previous version behind -- the directory-level equivalent of
// per-file stale-cleanup). Returns false and sets `error` on any failure;
// destDir's prior contents are only removed once the zip has already been
// opened successfully.
bool extractZip(const std::filesystem::path& zipPath, const std::filesystem::path& destDir, std::string& error);
