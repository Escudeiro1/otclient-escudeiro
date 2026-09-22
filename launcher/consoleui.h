#pragma once

#include "ui.h"

class ConsoleUi final : public IUi {
public:
    void reportStatus(const std::string& text) override;
    void reportProgress(int percent) override;
    void reportFatalError(const std::string& message) override;

private:
    bool m_progressLineOpen = false;
};
