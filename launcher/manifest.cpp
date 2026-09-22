#include "manifest.h"

namespace {

std::optional<BinaryDescriptor> parseBinaryDescriptor(const nlohmann::json& j, const char* key)
{
    if (!j.contains(key) || !j[key].is_object())
        return std::nullopt;

    const auto& obj = j[key];
    if (!obj.contains("file") || !obj.contains("checksum"))
        return std::nullopt;

    BinaryDescriptor descriptor;
    descriptor.file = obj.value("file", "");
    descriptor.checksum = obj.value("checksum", "");
    if (descriptor.file.empty() || descriptor.checksum.empty())
        return std::nullopt;

    return descriptor;
}

} // namespace

Manifest parseManifest(const std::string& body)
{
    Manifest manifest;

    nlohmann::json j;
    try {
        j = nlohmann::json::parse(body);
    } catch (const nlohmann::json::exception& e) {
        manifest.error = std::string("Invalid manifest JSON: ") + e.what();
        return manifest;
    }

    if (!j.is_object()) {
        manifest.error = "Manifest response is not a JSON object";
        return manifest;
    }

    manifest.error = j.value("error", "");
    if (!manifest.error.empty())
        return manifest;

    manifest.baseUrl = j.value("url", "");
    manifest.keepFiles = j.value("keepFiles", false);

    if (j.contains("files") && j["files"].is_object()) {
        for (const auto& [key, value] : j["files"].items()) {
            if (value.is_string())
                manifest.files[key] = value.get<std::string>();
        }
    }

    if (j.contains("bootstrapFiles") && j["bootstrapFiles"].is_object()) {
        for (const auto& [key, value] : j["bootstrapFiles"].items()) {
            if (value.is_string())
                manifest.bootstrapFiles[key] = value.get<std::string>();
        }
    }

    if (j.contains("archives") && j["archives"].is_array()) {
        for (const auto& entry : j["archives"]) {
            if (!entry.is_object())
                continue;
            ArchiveDescriptor descriptor;
            descriptor.name = entry.value("name", "");
            descriptor.file = entry.value("file", "");
            descriptor.checksum = entry.value("checksum", "");
            descriptor.extractTo = entry.value("extractTo", "");
            if (!descriptor.file.empty() && !descriptor.checksum.empty() && !descriptor.extractTo.empty())
                manifest.archives.push_back(std::move(descriptor));
        }
    }

    manifest.client = parseBinaryDescriptor(j, "client");
    manifest.launcher = parseBinaryDescriptor(j, "launcher");

    if (manifest.baseUrl.empty() && (!manifest.files.empty() || !manifest.bootstrapFiles.empty() || !manifest.archives.empty())) {
        manifest.error = "Manifest lists files but has no base url";
    }

    return manifest;
}
