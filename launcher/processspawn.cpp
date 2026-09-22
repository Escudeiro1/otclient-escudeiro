#include "processspawn.h"

#ifdef _WIN32

#include <windows.h>
#include <shellapi.h>

namespace {

std::wstring utf8ToUtf16(const std::string& str)
{
    if (str.empty())
        return {};
    const int size = MultiByteToWideChar(CP_UTF8, 0, str.c_str(), static_cast<int>(str.size()), nullptr, 0);
    std::wstring result(size, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, str.c_str(), static_cast<int>(str.size()), result.data(), size);
    return result;
}

} // namespace

bool spawnProcess(const std::filesystem::path& executable, const std::vector<std::string>& args)
{
    std::string process = executable.string();
    for (auto& c : process) {
        if (c == '/')
            c = '\\';
    }
    if (process.size() < 4 || process.substr(process.size() - 4) != ".exe")
        process += ".exe";

    std::string commandLine;
    for (const auto& arg : args)
        commandLine += " \"" + arg + "\"";

    const auto wfile = utf8ToUtf16(process);
    const auto wcommandLine = utf8ToUtf16(commandLine);

    return reinterpret_cast<size_t>(ShellExecuteW(nullptr, L"open", wfile.c_str(), wcommandLine.c_str(), nullptr, SW_SHOWNORMAL)) > 32;
}

void makeExecutable(const std::filesystem::path&)
{
    // No-op: Windows infers executability from the .exe extension.
}

#else

#include <sys/stat.h>
#include <unistd.h>

bool spawnProcess(const std::filesystem::path& executable, const std::vector<std::string>& args)
{
    struct stat sts{};
    if (stat(executable.c_str(), &sts) == -1 && errno == ENOENT)
        return false;

    const pid_t pid = fork();
    if (pid == -1)
        return false;

    if (pid == 0) {
        const std::string processStr = executable.string();
        std::vector<char*> cargs;
        cargs.push_back(const_cast<char*>(processStr.c_str()));
        for (const auto& arg : args)
            cargs.push_back(const_cast<char*>(arg.c_str()));
        cargs.push_back(nullptr);

        execv(processStr.c_str(), cargs.data());
        _exit(EXIT_FAILURE);
    }

    return true;
}

void makeExecutable(const std::filesystem::path& path)
{
    std::error_code ec;
    std::filesystem::permissions(path,
        std::filesystem::perms::owner_exec | std::filesystem::perms::group_exec | std::filesystem::perms::others_exec,
        std::filesystem::perm_options::add, ec);
}

#endif
