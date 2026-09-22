#pragma once

#include "ui.h"

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

// One entry in the launcher window's log panel.
struct LogEvent {
    std::string text;
    bool isError = false;
    // True for progress-percentage updates: the window should replace its
    // most recent non-replacing line's display instead of appending a new
    // one, exactly like ConsoleUi's carriage-return trick, just applied to
    // a scrollback list instead of a terminal line.
    bool replaceLast = false;
};

// Thread-safe IUi implementation with no SDL/rendering code of its own:
// UpdateFlow::checkAndApplyUpdates() calls reportStatus/reportProgress/
// reportFatalError from a background worker thread; Window drains the
// queued events once per frame on the main/render thread.
class GuiUi final : public IUi {
public:
    void reportStatus(const std::string& text) override;
    void reportProgress(int percent) override;
    void reportFatalError(const std::string& message) override;

    // Returns and clears everything queued since the last call. Safe to call
    // from the render thread only.
    std::vector<LogEvent> drainEvents();

    // Not part of IUi -- set by the worker thread once checkAndApplyUpdates()
    // returns, polled by the render thread to decide whether Play is
    // clickable yet.
    void setReady(bool ready) { m_ready.store(ready); }
    bool isReady() const { return m_ready.load(); }

private:
    std::mutex m_mutex;
    std::vector<LogEvent> m_pending;
    bool m_progressLineOpen = false;
    std::atomic<bool> m_ready{ false };
};
