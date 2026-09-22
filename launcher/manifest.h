#pragma once

#include <map>
#include <optional>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

struct BinaryDescriptor {
    std::string file;
    std::string checksum; // sha256 hex
};

// A whole directory distributed as a single zip, downloaded once and
// extracted locally rather than diffed file-by-file (modules/mods/data are
// thousands of small files -- one request per directory instead).
struct ArchiveDescriptor {
    std::string name;      // e.g. "modules" -- used for logging only
    std::string file;      // e.g. "modules.zip", resolved against baseUrl
    std::string checksum;  // sha256 hex of the zip itself
    std::string extractTo; // relative path to extract into, e.g. "modules"
};

struct Manifest {
    std::string error;
    std::string baseUrl;
    std::map<std::string, std::string> files; // relative path -> sha256 hex, always kept in sync
    // Same shape as `files`, but only ever fetched if the local file is
    // missing -- never overwrites an existing (possibly user-customized)
    // copy, e.g. otclientrc.lua.
    std::map<std::string, std::string> bootstrapFiles;
    std::vector<ArchiveDescriptor> archives;
    bool keepFiles = false;
    std::optional<BinaryDescriptor> client;
    std::optional<BinaryDescriptor> launcher;
};

// Parses the manifest response body. On malformed JSON, returns a Manifest
// with `error` set (never throws) so callers have a single failure path to
// check, matching how a server-reported `error` field is handled.
Manifest parseManifest(const std::string& body);
