#include "consoleui.h"

#include <cstdio>

void ConsoleUi::reportStatus(const std::string& text)
{
    if (m_progressLineOpen) {
        std::fputc('\n', stdout);
        m_progressLineOpen = false;
    }
    std::printf("%s\n", text.c_str());
    std::fflush(stdout);
}

void ConsoleUi::reportProgress(int percent)
{
    if (percent < 0) {
        std::printf("\r...                    \r");
    } else {
        std::printf("\rDownloading: %3d%%", percent);
    }
    std::fflush(stdout);
    m_progressLineOpen = true;
}

void ConsoleUi::reportFatalError(const std::string& message)
{
    if (m_progressLineOpen) {
        std::fputc('\n', stdout);
        m_progressLineOpen = false;
    }
    std::fprintf(stderr, "Error: %s\n", message.c_str());
    std::fflush(stderr);
}
