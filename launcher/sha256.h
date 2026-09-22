#pragma once

#include <filesystem>
#include <string>

// Lowercase hex SHA-256. Returns an empty string on any I/O or hashing error.
std::string sha256File(const std::filesystem::path& path);
std::string sha256Bytes(const unsigned char* data, size_t len);
