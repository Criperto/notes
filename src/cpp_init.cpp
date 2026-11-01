#include "cpp_init.h"
#include <QtGui/QGuiApplication>
#include <QtQuickControls2/QQuickStyle>
#include <QtCore/QString>

extern "C" void notas_init_qt(void) {
    QQuickStyle::setStyle(QStringLiteral("Basic"));
    QGuiApplication::setDesktopFileName(QStringLiteral("dev.criperto.Notas"));
}
