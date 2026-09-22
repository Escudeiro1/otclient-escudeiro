#pragma once

#include "guiui.h"

#include <filesystem>
#include <functional>
#include <vector>

// Owns the launcher's SDL window/renderer and draws the fixed 604x425
// background + Play button + scrollable log panel. Deliberately the only
// file in launcher/ that touches SDL -- everything else (update logic,
// IUi) stays graphics-library-agnostic.
class Window {
public:
    ~Window();

    // assetsDir must contain launcher_bg.png and Verdana.ttf. Returns false
    // on any SDL/asset init failure (reported to stderr directly -- this
    // runs before there's a log panel to report into).
    bool init(const std::filesystem::path& assetsDir);

    // Runs the event/render loop until the window is closed. Drains `ui`
    // for new log lines and its ready state once per frame. Invokes
    // `onPlayClicked` each time Play is clicked while ui.isReady() is true;
    // the window only closes if it returns true, so a spawn failure's error
    // message stays visible and Play can be retried instead of the window
    // vanishing on the same frame the error appears.
    void runEventLoop(GuiUi& ui, const std::function<bool()>& onPlayClicked);

private:
    struct RenderedLine {
        void* texture = nullptr; // SDL_Texture*
        int width = 0;
        int height = 0;
        bool isError = false;
    };

    void appendEvents(std::vector<LogEvent>&& events);
    void renderFrame(bool playEnabled);
    void freeLogLines();

    void* m_window = nullptr;    // SDL_Window*
    void* m_renderer = nullptr;  // SDL_Renderer*
    void* m_bgTexture = nullptr; // SDL_Texture*
    void* m_font = nullptr;      // TTF_Font*
    void* m_boldFont = nullptr;  // TTF_Font* (same file, TTF_STYLE_BOLD)

    std::vector<RenderedLine> m_logLines;
    int m_scrollOffset = 0;
    bool m_initialized = false;
};
