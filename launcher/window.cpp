#include "window.h"

#include <SDL.h>
#include <SDL_image.h>
#include <SDL_ttf.h>

#include <algorithm>
#include <cstdio>

namespace {

constexpr int kWindowWidth = 604;
constexpr int kWindowHeight = 425;

// Logo's measured bottom edge (from a ruler-overlay crop of launcher_bg.png)
// is y=170; the button sits 20px below that.
constexpr int kButtonWidth = 180;
constexpr int kButtonHeight = 44;
constexpr int kButtonTop = 190;
constexpr int kButtonLeft = (kWindowWidth - kButtonWidth) / 2;

constexpr int kLogLeft = 24;
constexpr int kLogTop = 250;
constexpr int kLogWidth = kWindowWidth - 2 * kLogLeft;
constexpr int kLogHeight = (kWindowHeight - 20) - kLogTop;
constexpr int kLogPadding = 8;
constexpr int kLineSpacing = 4;
constexpr int kScrollStepPx = 24;

} // namespace

Window::~Window()
{
    freeLogLines();
    if (m_boldFont && m_boldFont != m_font)
        TTF_CloseFont(static_cast<TTF_Font*>(m_boldFont));
    if (m_font)
        TTF_CloseFont(static_cast<TTF_Font*>(m_font));
    if (m_bgTexture)
        SDL_DestroyTexture(static_cast<SDL_Texture*>(m_bgTexture));
    if (m_renderer)
        SDL_DestroyRenderer(static_cast<SDL_Renderer*>(m_renderer));
    if (m_window)
        SDL_DestroyWindow(static_cast<SDL_Window*>(m_window));
    if (m_initialized) {
        TTF_Quit();
        IMG_Quit();
        SDL_Quit();
    }
}

bool Window::init(const std::filesystem::path& assetsDir)
{
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        std::fprintf(stderr, "SDL_Init failed: %s\n", SDL_GetError());
        return false;
    }
    m_initialized = true;

    if (!(IMG_Init(IMG_INIT_PNG) & IMG_INIT_PNG)) {
        std::fprintf(stderr, "IMG_Init failed: %s\n", IMG_GetError());
        return false;
    }

    if (TTF_Init() != 0) {
        std::fprintf(stderr, "TTF_Init failed: %s\n", TTF_GetError());
        return false;
    }

    auto* window = SDL_CreateWindow("Escudeirot Launcher",
        SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED,
        kWindowWidth, kWindowHeight, SDL_WINDOW_SHOWN);
    if (!window) {
        std::fprintf(stderr, "SDL_CreateWindow failed: %s\n", SDL_GetError());
        return false;
    }
    SDL_SetWindowResizable(window, SDL_FALSE);
    SDL_SetWindowMinimumSize(window, kWindowWidth, kWindowHeight);
    SDL_SetWindowMaximumSize(window, kWindowWidth, kWindowHeight);
    m_window = window;

    auto* renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_ACCELERATED);
    if (!renderer)
        renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_SOFTWARE);
    if (!renderer) {
        std::fprintf(stderr, "SDL_CreateRenderer failed: %s\n", SDL_GetError());
        return false;
    }
    SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND);
    m_renderer = renderer;

    const auto bgPath = (assetsDir / "launcher_bg.png").string();
    auto* bgTexture = IMG_LoadTexture(renderer, bgPath.c_str());
    if (!bgTexture) {
        std::fprintf(stderr, "Failed to load %s: %s\n", bgPath.c_str(), IMG_GetError());
        return false;
    }
    m_bgTexture = bgTexture;

    const auto fontPath = (assetsDir / "Verdana.ttf").string();
    auto* font = TTF_OpenFont(fontPath.c_str(), 14);
    if (!font) {
        std::fprintf(stderr, "Failed to load %s: %s\n", fontPath.c_str(), TTF_GetError());
        return false;
    }
    m_font = font;

    auto* boldFont = TTF_OpenFont(fontPath.c_str(), 16);
    if (boldFont) {
        TTF_SetFontStyle(boldFont, TTF_STYLE_BOLD);
        m_boldFont = boldFont;
    } else {
        m_boldFont = font; // faux-bold unavailable; still readable with the regular font
    }

    return true;
}

void Window::freeLogLines()
{
    for (auto& line : m_logLines) {
        if (line.texture)
            SDL_DestroyTexture(static_cast<SDL_Texture*>(line.texture));
    }
    m_logLines.clear();
}

void Window::appendEvents(std::vector<LogEvent>&& events)
{
    auto* renderer = static_cast<SDL_Renderer*>(m_renderer);
    auto* font = static_cast<TTF_Font*>(m_font);

    for (const auto& event : events) {
        const SDL_Color color = event.isError
            ? SDL_Color{ 255, 140, 140, 255 }
            : SDL_Color{ 255, 255, 255, 255 };

        auto* surface = TTF_RenderUTF8_Blended_Wrapped(font, event.text.c_str(), color,
            kLogWidth - 2 * kLogPadding);
        if (!surface)
            continue;

        RenderedLine line;
        line.texture = SDL_CreateTextureFromSurface(renderer, surface);
        line.width = surface->w;
        line.height = surface->h;
        line.isError = event.isError;
        SDL_FreeSurface(surface);

        if (event.replaceLast && !m_logLines.empty()) {
            if (m_logLines.back().texture)
                SDL_DestroyTexture(static_cast<SDL_Texture*>(m_logLines.back().texture));
            m_logLines.back() = line;
        } else {
            m_logLines.push_back(line);
        }
    }
}

void Window::renderFrame(bool playEnabled)
{
    auto* renderer = static_cast<SDL_Renderer*>(m_renderer);
    auto* boldFont = static_cast<TTF_Font*>(m_boldFont);

    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
    SDL_RenderClear(renderer);

    const SDL_Rect fullRect{ 0, 0, kWindowWidth, kWindowHeight };
    SDL_RenderCopy(renderer, static_cast<SDL_Texture*>(m_bgTexture), nullptr, &fullRect);

    // Play button
    const SDL_Rect buttonRect{ kButtonLeft, kButtonTop, kButtonWidth, kButtonHeight };
    if (playEnabled)
        SDL_SetRenderDrawColor(renderer, 0xC9, 0xA2, 0x3A, 255);
    else
        SDL_SetRenderDrawColor(renderer, 0x5A, 0x5A, 0x5A, 255);
    SDL_RenderFillRect(renderer, &buttonRect);

    if (playEnabled)
        SDL_SetRenderDrawColor(renderer, 0x8A, 0x6E, 0x1C, 255);
    else
        SDL_SetRenderDrawColor(renderer, 0x3A, 0x3A, 0x3A, 255);
    SDL_RenderDrawRect(renderer, &buttonRect);

    const SDL_Color buttonTextColor = playEnabled
        ? SDL_Color{ 0x20, 0x14, 0x00, 255 }
        : SDL_Color{ 0xdf, 0xdf, 0xdf, 0x88 };
    auto* labelSurface = TTF_RenderUTF8_Blended(boldFont, "PLAY", buttonTextColor);
    if (labelSurface) {
        auto* labelTexture = SDL_CreateTextureFromSurface(renderer, labelSurface);
        const SDL_Rect labelRect{
            buttonRect.x + (buttonRect.w - labelSurface->w) / 2,
            buttonRect.y + (buttonRect.h - labelSurface->h) / 2,
            labelSurface->w, labelSurface->h
        };
        SDL_RenderCopy(renderer, labelTexture, nullptr, &labelRect);
        SDL_DestroyTexture(labelTexture);
        SDL_FreeSurface(labelSurface);
    }

    // Log panel
    const SDL_Rect logRect{ kLogLeft, kLogTop, kLogWidth, kLogHeight };
    SDL_SetRenderDrawColor(renderer, 0x20, 0x20, 0x20, 0xC8);
    SDL_RenderFillRect(renderer, &logRect);
    SDL_SetRenderDrawColor(renderer, 0x10, 0x10, 0x10, 0xFF);
    SDL_RenderDrawRect(renderer, &logRect);

    SDL_RenderSetClipRect(renderer, &logRect);

    int totalHeight = 0;
    for (const auto& line : m_logLines)
        totalHeight += line.height + kLineSpacing;

    const int visibleHeight = kLogHeight - 2 * kLogPadding;
    const int overflow = std::max(0, totalHeight - visibleHeight);
    m_scrollOffset = std::clamp(m_scrollOffset, 0, overflow);

    int y = logRect.y + kLogPadding - overflow + m_scrollOffset;
    for (const auto& line : m_logLines) {
        if (line.texture && y + line.height > logRect.y && y < logRect.y + logRect.h) {
            const SDL_Rect dst{ logRect.x + kLogPadding, y, line.width, line.height };
            SDL_RenderCopy(renderer, static_cast<SDL_Texture*>(line.texture), nullptr, &dst);
        }
        y += line.height + kLineSpacing;
    }

    SDL_RenderSetClipRect(renderer, nullptr);

    SDL_RenderPresent(renderer);
}

void Window::runEventLoop(GuiUi& ui, const std::function<bool()>& onPlayClicked)
{
    const SDL_Rect buttonRect{ kButtonLeft, kButtonTop, kButtonWidth, kButtonHeight };
    bool running = true;

    while (running) {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_QUIT) {
                running = false;
            } else if (event.type == SDL_MOUSEBUTTONDOWN && event.button.button == SDL_BUTTON_LEFT) {
                const SDL_Point point{ event.button.x, event.button.y };
                if (ui.isReady() && SDL_PointInRect(&point, &buttonRect)) {
                    if (onPlayClicked())
                        running = false;
                }
            } else if (event.type == SDL_MOUSEWHEEL) {
                m_scrollOffset = std::max(0, m_scrollOffset + event.wheel.y * kScrollStepPx);
            }
        }

        appendEvents(ui.drainEvents());
        renderFrame(ui.isReady());

        SDL_Delay(16);
    }
}
