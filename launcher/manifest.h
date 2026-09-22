#pragma once

#include <map>
#include <optional>
#include <string>

#include <nlohmann/json.hpp>

struct BinaryDescriptor {
    std::string file;
    std::string checksum; // sha256 hex
};

struct Manifest {
    std::string error;
    std::string baseUrl;
    std::map<std::string, std::string> files; // relative path -> sha256 hex
    bool keepFiles = false;
    std::optional<BinaryDescriptor> client;
    std::optional<BinaryDescriptor> launcher;
};

// Parses the manifest response body. On malformed JSON, returns a Manifest
// with `error` set (never throws) so callers have a single failure path to
// check, matching how a server-reported `error` field is handled.
Manifest parseManifest(const std::string& body);
