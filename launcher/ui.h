#pragma once

#include <string>

// Abstraction so UpdateFlow never depends on how progress/errors are actually
// displayed. This pass only ships ConsoleUi; a future GUI implementation is a
// drop-in replacement with zero changes to updateflow.cpp.
class IUi {
public:
    virtual ~IUi() = default;

    virtual void reportStatus(const std::string& text) = 0;
    virtual void reportProgress(int percent) = 0; // -1 = indeterminate
    virtual void reportFatalError(const std::string& message) = 0;
};
