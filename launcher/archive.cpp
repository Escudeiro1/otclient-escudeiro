#include "archive.h"

#include "unzip.h"

#include <array>
#include <fstream>
#include <system_error>

namespace {

// The zips this launcher extracts are always created as `zip -r <name>.zip
// <name>/` (see tools/publish-launcher-release.sh), so every entry starts
// with that same single top-level directory name -- which destDir already
// represents. Strip it so files land directly under destDir instead of
// destDir/<name>/... Falls back to the entry name itself if there's no '/'
// (shouldn't happen for these zips, but avoids ever silently dropping data).
std::string stripFirstPathComponent(const std::string& entryName)
{
    const auto slash = entryName.find('/');
    if (slash == std::string::npos)
        return entryName;
    return entryName.substr(slash + 1);
}

} // namespace

bool extractZip(const std::filesystem::path& zipPath, const std::filesystem::path& destDir, std::string& error)
{
    unzFile zipFile = unzOpen(zipPath.string().c_str());
    if (!zipFile) {
        error = "Unable to open zip archive " + zipPath.string();
        return false;
    }

    unz_global_info globalInfo = {};
    if (unzGetGlobalInfo(zipFile, &globalInfo) != UNZ_OK) {
        error = "Unable to read zip archive info for " + zipPath.string();
        unzClose(zipFile);
        return false;
    }

    std::error_code ec;
    std::filesystem::remove_all(destDir, ec);
    std::filesystem::create_directories(destDir, ec);

    constexpr int maxFilenameSize = 1024;
    constexpr int readSize = 8192;
    std::array<char, maxFilenameSize> fileName = {};
    std::array<char, readSize> readBuffer = {};

    for (uint32_t i = 0; i < globalInfo.number_entry; ++i) {
        unz_file_info fileInfo = {};
        fileName.fill('\0');
        if (unzGetCurrentFileInfo(zipFile, &fileInfo, fileName.data(), static_cast<uint16_t>(fileName.size()), nullptr, 0, nullptr, 0) != UNZ_OK) {
            error = "Unable to read zip entry info from " + zipPath.string();
            unzClose(zipFile);
            return false;
        }

        const std::string entryName = fileName.data();
        const bool isDirectory = entryName.ends_with('/') || entryName.ends_with('\\');

        if (!isDirectory) {
            const auto relativePath = stripFirstPathComponent(entryName);
            if (!relativePath.empty()) {
                if (unzOpenCurrentFile(zipFile) != UNZ_OK) {
                    error = "Unable to open zip entry " + entryName;
                    unzClose(zipFile);
                    return false;
                }

                const auto destinationFile = destDir / relativePath;
                std::filesystem::create_directories(destinationFile.parent_path(), ec);

                std::ofstream out(destinationFile, std::ios::binary | std::ios::trunc);
                if (!out.is_open()) {
                    error = "Unable to write " + destinationFile.string();
                    unzCloseCurrentFile(zipFile);
                    unzClose(zipFile);
                    return false;
                }

                int readBytes = 0;
                do {
                    readBytes = unzReadCurrentFile(zipFile, readBuffer.data(), readBuffer.size());
                    if (readBytes < 0) {
                        error = "Unable to read zip entry " + entryName;
                        unzCloseCurrentFile(zipFile);
                        unzClose(zipFile);
                        return false;
                    }
                    if (readBytes > 0)
                        out.write(readBuffer.data(), readBytes);
                } while (readBytes > 0);

                out.close();

                if (unzCloseCurrentFile(zipFile) != UNZ_OK) {
                    error = "Unable to close zip entry " + entryName;
                    unzClose(zipFile);
                    return false;
                }
            }
        }

        if (i + 1 < globalInfo.number_entry && unzGoToNextFile(zipFile) != UNZ_OK) {
            error = "Unable to advance zip archive " + zipPath.string();
            unzClose(zipFile);
            return false;
        }
    }

    unzClose(zipFile);
    return true;
}
