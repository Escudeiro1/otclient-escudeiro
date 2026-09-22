#include "guiui.h"

void GuiUi::reportStatus(const std::string& text)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    m_pending.push_back({ text, false, false });
    m_progressLineOpen = false;
}

void GuiUi::reportProgress(int percent)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    const std::string text = percent < 0 ? "Working..." : "Progress: " + std::to_string(percent) + "%";
    m_pending.push_back({ text, false, m_progressLineOpen });
    m_progressLineOpen = true;
}

void GuiUi::reportFatalError(const std::string& message)
{
    std::lock_guard<std::mutex> lock(m_mutex);
    m_pending.push_back({ "Error: " + message, true, false });
    m_progressLineOpen = false;
}

std::vector<LogEvent> GuiUi::drainEvents()
{
    std::lock_guard<std::mutex> lock(m_mutex);
    auto events = std::move(m_pending);
    m_pending.clear();
    return events;
}
