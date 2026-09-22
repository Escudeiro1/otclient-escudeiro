#include "sha256.h"

#include <array>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <vector>

#include <openssl/evp.h>

namespace {

std::string digestToHex(const unsigned char* digest, unsigned int len)
{
    std::ostringstream ss;
    ss << std::hex << std::setfill('0');
    for (unsigned int i = 0; i < len; ++i)
        ss << std::setw(2) << static_cast<int>(digest[i]);
    return ss.str();
}

} // namespace

std::string sha256File(const std::filesystem::path& path)
{
    std::ifstream file(path, std::ios::binary);
    if (!file.is_open())
        return "";

    EVP_MD_CTX* context = EVP_MD_CTX_new();
    if (!context)
        return "";

    bool ok = EVP_DigestInit_ex(context, EVP_sha256(), nullptr) == 1;

    constexpr size_t CHUNK_SIZE = 1 << 16; // 64 KiB
    std::vector<char> buffer(CHUNK_SIZE);
    while (ok && file) {
        file.read(buffer.data(), static_cast<std::streamsize>(buffer.size()));
        const auto bytesRead = file.gcount();
        if (bytesRead <= 0)
            break;
        ok = EVP_DigestUpdate(context, buffer.data(), static_cast<size_t>(bytesRead)) == 1;
    }

    std::array<unsigned char, EVP_MAX_MD_SIZE> digest{};
    unsigned int digestLength = 0;
    ok = ok && EVP_DigestFinal_ex(context, digest.data(), &digestLength) == 1;
    EVP_MD_CTX_free(context);

    if (!ok)
        return "";

    return digestToHex(digest.data(), digestLength);
}

std::string sha256Bytes(const unsigned char* data, size_t len)
{
    std::array<unsigned char, EVP_MAX_MD_SIZE> digest{};
    unsigned int digestLength = 0;

    EVP_MD_CTX* context = EVP_MD_CTX_new();
    if (!context)
        return "";

    const bool ok = EVP_DigestInit_ex(context, EVP_sha256(), nullptr) == 1 &&
                    EVP_DigestUpdate(context, data, len) == 1 &&
                    EVP_DigestFinal_ex(context, digest.data(), &digestLength) == 1;
    EVP_MD_CTX_free(context);

    if (!ok)
        return "";

    return digestToHex(digest.data(), digestLength);
}
