#include "cpp_init.h"
#include <QtGui/QGuiApplication>
#include <QtGui/QSurfaceFormat>
#include <QtQuick/QQuickWindow>
#include <QtQuickControls2/QQuickStyle>
#include <QtCore/QString>
#include <QtCore/QLoggingCategory>

extern "C" void notas_init_qt(void) {
    QLoggingCategory::setFilterRules(QStringLiteral("qt.qpa.wayland.textinput.warning=false\n"));
    QQuickStyle::setStyle(QStringLiteral("Basic"));
    QGuiApplication::setDesktopFileName(QStringLiteral("dev.criperto.Notas"));

    // Habilitar soporte de transparencia y búfer alfa en Wayland/X11
    QQuickWindow::setDefaultAlphaBuffer(true);
    QSurfaceFormat format = QSurfaceFormat::defaultFormat();
    format.setAlphaBufferSize(8);
    QSurfaceFormat::setDefaultFormat(format);
}

