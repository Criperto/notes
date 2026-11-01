#include "cpp_init.h"
#include <QtGui/QGuiApplication>
#include <QtQuickControls2/QQuickStyle>
#include <QtCore/QString>
#include <QtCore/QLoggingCategory>

extern "C" void notas_init_qt(void) {
    QLoggingCategory::setFilterRules(QStringLiteral("qt.qpa.wayland.textinput.warning=false\n"));
    QQuickStyle::setStyle(QStringLiteral("Basic"));
    QGuiApplication::setDesktopFileName(QStringLiteral("dev.criperto.Notas"));
}
