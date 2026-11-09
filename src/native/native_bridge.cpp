#include "native_bridge.h"

#include <QCoreApplication>
#include <QGuiApplication>
#include <QFont>
#include <QFontDatabase>
#include <QClipboard>
#include <QMimeData>
#include <QImage>
#include <QImageReader>
#include <QDirIterator>
#include <QTextStream>
#include <QRegularExpression>
#include <QUrl>
#include <QMouseEvent>
#include <QPalette>
#include <QColor>
#include <QStandardPaths>
#include <QWindow>
#include <QQuickItem>
#include <QQuickWindow>
#include <cmath>
#include <iostream>

// ═════════════════════════════════════════════════════════════════════════════
// 1. SplitParser & StdioCollector Implementation
// ═════════════════════════════════════════════════════════════════════════════

SplitParser::SplitParser(QObject *parent)
    : QObject(parent)
{
}

void SplitParser::setSplitMarker(const QString &marker) {
    if (m_splitMarker == marker) return;
    m_splitMarker = marker;
    emit splitMarkerChanged();
}

void SplitParser::pushData(const QByteArray &data) {
    if (data.isEmpty()) return;

    if (m_splitMarker.isEmpty()) {
        emit read(QString::fromUtf8(data));
        return;
    }

    m_buffer.append(data);
    QByteArray markerBytes = m_splitMarker.toUtf8();
    int idx = -1;
    while (!m_buffer.isEmpty() && (idx = m_buffer.indexOf(markerBytes)) != -1) {
        QByteArray chunk = m_buffer.left(idx);
        m_buffer.remove(0, idx + markerBytes.size());
        emit read(QString::fromUtf8(chunk));
    }
}

void SplitParser::flush() {
    if (!m_buffer.isEmpty()) {
        emit read(QString::fromUtf8(m_buffer));
        m_buffer.clear();
    }
}

void SplitParser::reset() {
    m_buffer.clear();
}

StdioCollector::StdioCollector(QObject *parent)
    : SplitParser(parent)
{
}

void StdioCollector::pushData(const QByteArray &data) {
    if (!data.isEmpty()) {
        m_collected.append(data);
    }
}

void StdioCollector::flush() {
    QString nextText = QString::fromUtf8(m_collected);
    m_collected.clear();
    if (m_text != nextText) {
        m_text = nextText;
        emit textChanged();
    }
    emit streamFinished();
}

void StdioCollector::reset() {
    m_collected.clear();
}

// ═════════════════════════════════════════════════════════════════════════════
// 2. Process Implementation
// ═════════════════════════════════════════════════════════════════════════════

Process::Process(QObject *parent)
    : QObject(parent)
{
}

Process::~Process() {
    stopProcess();
}

void Process::setCommand(const QStringList &cmd) {
    if (m_command == cmd) return;
    m_command = cmd;
    emit commandChanged();
    if (m_running) {
        startProcess();
    }
}

void Process::setRunning(bool r) {
    if (m_running == r) return;
    m_running = r;
    emit runningChanged();
    if (m_running) {
        startProcess();
    } else {
        stopProcess();
    }
}

void Process::setStdinEnabled(bool e) {
    if (m_stdinEnabled == e) return;
    m_stdinEnabled = e;
    emit stdinEnabledChanged();
    if (!m_stdinEnabled && m_process && m_process->state() == QProcess::Running) {
        m_process->closeWriteChannel();
    }
}

void Process::write(const QString &data) {
    if (m_process && m_process->state() == QProcess::Running) {
        m_process->write(data.toUtf8());
        if (!m_stdinEnabled) {
            m_process->closeWriteChannel();
        }
    }
}

void Process::setStdoutParser(SplitParser *p) {
    if (m_stdout == p) return;
    m_stdout = p;
    emit stdoutParserChanged();
}

void Process::setStderrParser(SplitParser *p) {
    if (m_stderr == p) return;
    m_stderr = p;
    emit stderrParserChanged();
}

void Process::exec(const QStringList &args) {
    if (!args.isEmpty()) {
        m_command = args;
        emit commandChanged();
    }
    setRunning(true);
}

void Process::startProcess() {
    stopProcess();

    if (m_stdout) m_stdout->reset();
    if (m_stderr) m_stderr->reset();

    if (m_command.isEmpty()) {
        m_running = false;
        emit runningChanged();
        return;
    }

    m_process = new QProcess(this);
    QString prog = m_command.first();
    QStringList args = m_command.mid(1);

    connect(m_process, &QProcess::started, this, &Process::started);
    connect(m_process, &QProcess::readyReadStandardOutput, this, &Process::onReadyReadStdout);
    connect(m_process, &QProcess::readyReadStandardError, this, &Process::onReadyReadStderr);
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &Process::onProcessFinished);
    connect(m_process, &QProcess::errorOccurred, this, &Process::onProcessError);

    m_process->start(prog, args);
}

void Process::stopProcess() {
    if (m_process) {
        m_process->disconnect(this);
        if (m_process->state() != QProcess::NotRunning) {
            m_process->terminate();
            if (!m_process->waitForFinished(300)) {
                m_process->kill();
                m_process->waitForFinished(100);
            }
        }
        m_process->deleteLater();
        m_process = nullptr;
    }
}

void Process::onReadyReadStdout() {
    if (!m_process) return;
    QByteArray data = m_process->readAllStandardOutput();
    if (m_stdout && !data.isEmpty()) {
        m_stdout->pushData(data);
    }
}

void Process::onReadyReadStderr() {
    if (!m_process) return;
    QByteArray data = m_process->readAllStandardError();
    if (m_stderr && !data.isEmpty()) {
        m_stderr->pushData(data);
    }
}

void Process::onProcessFinished(int exitCode, QProcess::ExitStatus /*exitStatus*/) {
    if (m_process) {
        onReadyReadStdout();
        onReadyReadStderr();
    }
    if (m_stdout) {
        m_stdout->flush();
    }
    if (m_stderr) {
        m_stderr->flush();
    }
    if (m_running) {
        m_running = false;
        emit runningChanged();
    }
    emit exited(exitCode);
}

void Process::onProcessError(QProcess::ProcessError /*error*/) {
    if (m_running) {
        m_running = false;
        emit runningChanged();
    }
    emit exited(-1);
}

// ═════════════════════════════════════════════════════════════════════════════
// 3. FileView Implementation
// ═════════════════════════════════════════════════════════════════════════════

FileView::FileView(QObject *parent)
    : QObject(parent)
{
    m_watcher = new QFileSystemWatcher(this);
    connect(m_watcher, &QFileSystemWatcher::fileChanged, this, &FileView::onFileSystemChanged);
    connect(m_watcher, &QFileSystemWatcher::directoryChanged, this, &FileView::onFileSystemChanged);
}

FileView::~FileView() {
}

void FileView::setPath(const QString &p) {
    if (m_path == p) return;
    m_path = p;
    emit pathChanged();
    updateWatcher();
    if (m_preload && !m_path.isEmpty()) {
        readFile();
    }
}

void FileView::setPreload(bool v) {
    if (m_preload == v) return;
    m_preload = v;
    emit preloadChanged();
    if (m_preload && !m_loaded && !m_path.isEmpty()) {
        readFile();
    }
}

void FileView::setWatchChanges(bool v) {
    if (m_watchChanges == v) return;
    m_watchChanges = v;
    emit watchChangesChanged();
    updateWatcher();
}

void FileView::setAtomicWrites(bool v) {
    if (m_atomicWrites == v) return;
    m_atomicWrites = v;
    emit atomicWritesChanged();
}

void FileView::setPrintErrors(bool v) {
    if (m_printErrors == v) return;
    m_printErrors = v;
    emit printErrorsChanged();
}

void FileView::setText(const QString &content) {
    if (m_text == content && m_loaded) {
        emit saved();
        return;
    }
    writeFile(content);
}

void FileView::reload() {
    readFile();
}

void FileView::updateWatcher() {
    if (!m_watcher) return;
    const QStringList files = m_watcher->files();
    if (!files.isEmpty()) {
        m_watcher->removePaths(files);
    }
    const QStringList dirs = m_watcher->directories();
    if (!dirs.isEmpty()) {
        m_watcher->removePaths(dirs);
    }
    if (m_watchChanges && !m_path.isEmpty()) {
        if (QFile::exists(m_path)) {
            m_watcher->addPath(m_path);
        }
        QString parentDir = QFileInfo(m_path).absolutePath();
        if (!parentDir.isEmpty() && QDir(parentDir).exists()) {
            m_watcher->addPath(parentDir);
        }
    }
}

bool FileView::readFile() {
    if (m_path.isEmpty() || !QFile::exists(m_path)) {
        m_loaded = false;
        emit loadedChanged();
        emit loadFailed(QStringLiteral("Archivo no existe"));
        return false;
    }

    QFile file(m_path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (m_printErrors) {
            std::cerr << "[FileView] Error abriendo " << m_path.toStdString() << ": " << file.errorString().toStdString() << "\n";
        }
        emit loadFailed(file.errorString());
        return false;
    }

    QTextStream in(&file);
    QString content = in.readAll();
    file.close();

    m_lastModified = QFileInfo(m_path).lastModified();
    m_text = content;
    m_loaded = true;

    emit loadedChanged();
    emit loaded();
    return true;
}

bool FileView::writeFile(const QString &content) {
    if (m_path.isEmpty()) {
        emit saveFailed(QStringLiteral("Ruta vacía"));
        return false;
    }

    m_isInternalSave = true;

    QFileInfo fi(m_path);
    QDir dir = fi.dir();
    if (!dir.exists()) {
        dir.mkpath(QStringLiteral("."));
    }

    bool success = false;
    if (m_atomicWrites) {
        QSaveFile file(m_path);
        if (file.open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream out(&file);
            out << content;
            out.flush();
            success = file.commit();
        }
    } else {
        QFile file(m_path);
        if (file.open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream out(&file);
            out << content;
            out.flush();
            file.close();
            success = true;
        }
    }

    if (success) {
        m_text = content;
        m_loaded = true;
        m_lastModified = QFileInfo(m_path).lastModified();
        updateWatcher();
        emit loadedChanged();
        emit saved();
    } else {
        if (m_printErrors) {
            std::cerr << "[FileView] Error guardando " << m_path.toStdString() << "\n";
        }
        emit saveFailed(QStringLiteral("Error al escribir archivo"));
    }

    m_isInternalSave = false;
    return success;
}

void FileView::onFileSystemChanged(const QString &changedPath) {
    if (m_isInternalSave || m_path.isEmpty()) return;
    QFileInfo fi(m_path);
    if (fi.exists()) {
        if (m_watchChanges && m_watcher && !m_watcher->files().contains(m_path)) {
            m_watcher->addPath(m_path);
        }
        QDateTime mod = fi.lastModified();
        bool shouldReload = (changedPath == m_path) || !m_loaded || (mod != m_lastModified);
        if (shouldReload && readFile()) {
            emit fileChanged();
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// 4. Sys Implementation
// ═════════════════════════════════════════════════════════════════════════════

Sys::Sys(QObject *parent)
    : QObject(parent)
{
    m_initialAction = QString::fromLocal8Bit(qgetenv("NOTAS_INITIAL_ACTION"));
    m_initialTarget = QString::fromLocal8Bit(qgetenv("NOTAS_INITIAL_TARGET"));

    if (QGuiApplication::clipboard()) {
        connect(QGuiApplication::clipboard(), &QClipboard::dataChanged, this, &Sys::clipboardTextChanged);
    }

    if (auto *app = QGuiApplication::instance()) {
        app->installEventFilter(this);
    }

    m_qtColors = readQtColors();
    setupQtThemeWatcher();
    startIpcServer();

    QGuiApplication::setFont(QFont(systemFontFamily()));
    printStartupDiagnostics();
}

Sys::~Sys() {
    if (m_ipcServer) {
        m_ipcServer->close();
        delete m_ipcServer;
        m_ipcServer = nullptr;
    }
    if (!m_currentInstanceSockPath.isEmpty()) {
        QFile::remove(m_currentInstanceSockPath);
    }
    if (!m_currentInstanceJsonPath.isEmpty()) {
        QFile::remove(m_currentInstanceJsonPath);
    }
}

bool Sys::eventFilter(QObject *watched, QEvent *event) {
    if (event->type() == QEvent::MouseButtonPress || event->type() == QEvent::MouseMove) {
        auto *me = static_cast<QMouseEvent*>(event);
        QPointF p = me->scenePosition();
        if (p != m_lastMousePos) {
            m_lastMousePos = p;
            emit lastMousePosChanged();
        }
    } else if (event->type() == QEvent::ApplicationPaletteChange) {
        refreshQtColors();
    }
    return QObject::eventFilter(watched, event);
}

void Sys::setupQtThemeWatcher() {
    if (!m_qtThemeWatcher) {
        m_qtThemeWatcher = new QFileSystemWatcher(this);
        connect(m_qtThemeWatcher, &QFileSystemWatcher::fileChanged, this, &Sys::onQtThemeFileChanged);
        connect(m_qtThemeWatcher, &QFileSystemWatcher::directoryChanged, this, &Sys::onQtThemeFileChanged);
    }
    const QStringList existing = m_qtThemeWatcher->files() + m_qtThemeWatcher->directories();
    if (!existing.isEmpty()) {
        m_qtThemeWatcher->removePaths(existing);
    }
    const QString home = QDir::homePath();
    const QStringList candidates = {
        home + QStringLiteral("/.config/qt6ct/qt6ct.conf"),
        home + QStringLiteral("/.config/qt6ct/style-colors.conf"),
        home + QStringLiteral("/.config/Kvantum/kvantum.kvconfig"),
        home + QStringLiteral("/.config/Kvantum/pywal/pywal.kvconfig"),
        home + QStringLiteral("/.config/kdeglobals"),
        home + QStringLiteral("/.config/qt6ct"),
        home + QStringLiteral("/.config/Kvantum")
    };
    for (const auto &p : candidates) {
        if (QFileInfo::exists(p)) {
            m_qtThemeWatcher->addPath(p);
        }
    }
}

void Sys::onQtThemeFileChanged() {
    QTimer::singleShot(120, this, [this]() {
        setupQtThemeWatcher();
        refreshQtColors();
        emit systemFontChanged();
    });
}

void Sys::refreshQtColors() {
    QJsonObject next = readQtColors();
    if (next != m_qtColors) {
        m_qtColors = next;
        emit qtColorsChanged();
    }
}

static QColor parseConfigColor(const QString &raw) {
    QString s = raw.trimmed();
    if (s.isEmpty()) return QColor();
    if (s.startsWith('#')) {
        if (s.length() == 9) {
            // #AARRGGBB -> #RRGGBB
            QColor c(QStringLiteral("#") + s.mid(3));
            if (c.isValid()) return c;
        }
        QColor c(s);
        if (c.isValid()) return c;
    }
    const QStringList rgb = s.split(',');
    if (rgb.size() >= 3) {
        bool okR = false, okG = false, okB = false;
        int r = rgb[0].trimmed().toInt(&okR);
        int g = rgb[1].trimmed().toInt(&okG);
        int b = rgb[2].trimmed().toInt(&okB);
        if (okR && okG && okB) {
            return QColor(qBound(0, r, 255), qBound(0, g, 255), qBound(0, b, 255));
        }
    }
    return QColor();
}

QJsonObject Sys::readQtColors() const {
    QPalette pal = QGuiApplication::palette();
    QColor bg = pal.color(QPalette::Window);
    QColor surface = pal.color(QPalette::Base);
    QColor altBase = pal.color(QPalette::AlternateBase);
    QColor fg = pal.color(QPalette::WindowText);
    QColor txt = pal.color(QPalette::Text);
    QColor btn = pal.color(QPalette::Button);
    QColor accent = pal.color(QPalette::Highlight);
    QColor link = pal.color(QPalette::Link);
    QColor mid = pal.color(QPalette::Mid);

    const QString home = QDir::homePath();
    QString qt6ctStyle;
    QString colorSchemePath;
    bool customPalette = false;

    QFile qt6ctFile(home + QStringLiteral("/.config/qt6ct/qt6ct.conf"));
    if (qt6ctFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&qt6ctFile);
        while (!in.atEnd()) {
            QString line = in.readLine().trimmed();
            if (line.startsWith(QStringLiteral("style="))) {
                qt6ctStyle = line.mid(6).trimmed();
            } else if (line.startsWith(QStringLiteral("color_scheme_path="))) {
                colorSchemePath = line.mid(18).trimmed();
            } else if (line.startsWith(QStringLiteral("custom_palette="))) {
                customPalette = (line.mid(15).trimmed().compare(QStringLiteral("true"), Qt::CaseInsensitive) == 0);
            }
        }
        qt6ctFile.close();
    }

    if (customPalette && !colorSchemePath.isEmpty() && QFile::exists(colorSchemePath)) {
        QFile csFile(colorSchemePath);
        if (csFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&csFile);
            while (!in.atEnd()) {
                QString line = in.readLine().trimmed();
                if (line.startsWith(QStringLiteral("active_colors="))) {
                    const QStringList cols = line.mid(14).split(',');
                    auto getRole = [&](int idx) -> QColor {
                        return (idx >= 0 && idx < cols.size()) ? parseConfigColor(cols[idx]) : QColor();
                    };
                    if (QColor c = getRole(0); c.isValid()) fg = c;
                    if (QColor c = getRole(1); c.isValid()) btn = c;
                    if (QColor c = getRole(5); c.isValid()) mid = c;
                    if (QColor c = getRole(6); c.isValid()) txt = c;
                    if (QColor c = getRole(9); c.isValid()) surface = c;
                    if (QColor c = getRole(10); c.isValid()) bg = c;
                    if (QColor c = getRole(12); c.isValid()) accent = c;
                    if (QColor c = getRole(14); c.isValid()) link = c;
                    if (QColor c = getRole(16); c.isValid()) altBase = c;
                    break;
                }
            }
            csFile.close();
        }
    }

    const QString styleOverride = QString::fromLocal8Bit(qgetenv("QT_STYLE_OVERRIDE"));
    const bool usesKvantum = qt6ctStyle.compare(QStringLiteral("kvantum"), Qt::CaseInsensitive) == 0
                          || styleOverride.contains(QStringLiteral("kvantum"), Qt::CaseInsensitive);

    if (usesKvantum) {
        QString kvTheme = QString::fromLocal8Bit(qgetenv("KVANTUM_THEME")).trimmed();
        QFile kvMain(home + QStringLiteral("/.config/Kvantum/kvantum.kvconfig"));
        if (kvMain.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&kvMain);
            while (!in.atEnd()) {
                QString line = in.readLine().trimmed();
                if (line.startsWith(QStringLiteral("theme="))) {
                    QString t = line.mid(6).trimmed();
                    if (!t.isEmpty()) kvTheme = t;
                    break;
                }
            }
            kvMain.close();
        }
        if (!kvTheme.isEmpty()) {
            QString baseTheme = kvTheme;
            if (baseTheme.endsWith('#')) baseTheme.chop(1);
            const QStringList kvPaths = {
                home + QStringLiteral("/.config/Kvantum/") + kvTheme + QStringLiteral("/") + kvTheme + QStringLiteral(".kvconfig"),
                home + QStringLiteral("/.config/Kvantum/") + baseTheme + QStringLiteral("/") + kvTheme + QStringLiteral(".kvconfig"),
                QStringLiteral("/usr/share/Kvantum/") + kvTheme + QStringLiteral("/") + kvTheme + QStringLiteral(".kvconfig"),
                QStringLiteral("/usr/share/Kvantum/") + baseTheme + QStringLiteral("/") + kvTheme + QStringLiteral(".kvconfig")
            };
            for (const auto &kp : kvPaths) {
                if (!QFile::exists(kp)) continue;
                QFile kf(kp);
                if (kf.open(QIODevice::ReadOnly | QIODevice::Text)) {
                    QTextStream in(&kf);
                    QString section;
                    while (!in.atEnd()) {
                        QString line = in.readLine().trimmed();
                        if (line.isEmpty() || line.startsWith('#') || line.startsWith(';')) continue;
                        if (line.startsWith('[') && line.endsWith(']')) {
                            section = line.mid(1, line.length() - 2);
                            continue;
                        }
                        if (section != QStringLiteral("GeneralColors")) continue;
                        int eq = line.indexOf('=');
                        if (eq == -1) continue;
                        QString k = line.left(eq).trimmed();
                        QColor c = parseConfigColor(line.mid(eq + 1));
                        if (!c.isValid()) continue;
                        if (k == QStringLiteral("window.color")) bg = c;
                        else if (k == QStringLiteral("base.color")) surface = c;
                        else if (k == QStringLiteral("alt.base.color")) altBase = c;
                        else if (k == QStringLiteral("button.color")) btn = c;
                        else if (k == QStringLiteral("highlight.color")) accent = c;
                        else if (k == QStringLiteral("text.color")) txt = c;
                        else if (k == QStringLiteral("window.text.color")) fg = c;
                        else if (k == QStringLiteral("link.color")) link = c;
                        else if (k == QStringLiteral("disabled.text.color")) mid = c;
                    }
                    kf.close();
                    break;
                }
            }
        }
    } else if (!customPalette && QFile::exists(home + QStringLiteral("/.config/kdeglobals"))) {
        QFile kdeFile(home + QStringLiteral("/.config/kdeglobals"));
        if (kdeFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&kdeFile);
            QString section;
            while (!in.atEnd()) {
                QString line = in.readLine().trimmed();
                if (line.isEmpty() || line.startsWith('#')) continue;
                if (line.startsWith('[') && line.endsWith(']')) {
                    section = line.mid(1, line.length() - 2);
                    continue;
                }
                int eq = line.indexOf('=');
                if (eq == -1) continue;
                QString k = line.left(eq).trimmed();
                QColor c = parseConfigColor(line.mid(eq + 1));
                if (!c.isValid()) continue;
                if (section == QStringLiteral("Colors:Window")) {
                    if (k == QStringLiteral("BackgroundNormal")) bg = c;
                    else if (k == QStringLiteral("ForegroundNormal")) fg = c;
                } else if (section == QStringLiteral("Colors:View")) {
                    if (k == QStringLiteral("BackgroundNormal")) surface = c;
                    else if (k == QStringLiteral("ForegroundNormal")) txt = c;
                    else if (k == QStringLiteral("ForegroundLink")) link = c;
                } else if (section == QStringLiteral("Colors:Button")) {
                    if (k == QStringLiteral("BackgroundNormal")) btn = c;
                } else if (section == QStringLiteral("Colors:Selection")) {
                    if (k == QStringLiteral("BackgroundNormal")) accent = c;
                }
            }
            kdeFile.close();
        }
    }

    auto hex = [](const QColor &c) -> QString {
        return c.isValid() ? c.name(QColor::HexRgb) : QStringLiteral("#000000");
    };
    auto shiftHue = [](const QColor &base, qreal dh, qreal satMul, qreal valShift) -> QColor {
        float h = 0.0f, s = 0.0f, v = 0.0f, a = 1.0f;
        base.getHsvF(&h, &s, &v, &a);
        if (h < 0.0f) {
            return QColor::fromHsvF(0.0f, 0.0f, qBound(0.0f, v + float(valShift), 1.0f));
        }
        float nh = std::fmod(h + float(dh) + 1.0f, 1.0f);
        float ns = qBound(0.0f, s * float(satMul), 1.0f);
        float nv = qBound(0.0f, v + float(valShift), 1.0f);
        return QColor::fromHsvF(nh, ns, nv);
    };

    QColor c2 = (link.isValid() && link != accent) ? link : shiftHue(accent, 0.03, 0.9, 0.04);
    QColor c3 = shiftHue(accent, -0.04, 0.85, 0.06);
    QColor c4 = shiftHue(accent, 0.06, 0.75, 0.04);
    QColor c5 = (btn.isValid() && btn != bg) ? btn : shiftHue(accent, -0.06, 0.7, 0.05);
    QColor c6 = shiftHue(accent, 0.09, 0.65, 0.06);

    QJsonObject special;
    special[QStringLiteral("background")] = hex(bg);
    special[QStringLiteral("foreground")] = hex(fg);
    special[QStringLiteral("cursor")] = hex(txt);

    QJsonObject colors;
    colors[QStringLiteral("color0")] = hex(surface.isValid() ? surface : bg);
    colors[QStringLiteral("color1")] = hex(accent);
    colors[QStringLiteral("color2")] = hex(c2);
    colors[QStringLiteral("color3")] = hex(c3);
    colors[QStringLiteral("color4")] = hex(c4);
    colors[QStringLiteral("color5")] = hex(c5);
    colors[QStringLiteral("color6")] = hex(c6);
    colors[QStringLiteral("color7")] = hex(fg);
    colors[QStringLiteral("color8")] = hex(mid.isValid() ? mid : altBase);
    colors[QStringLiteral("color9")] = hex(shiftHue(accent, 0.0, 1.05, 0.08));
    colors[QStringLiteral("color10")] = hex(shiftHue(c2, 0.0, 1.05, 0.08));
    colors[QStringLiteral("color11")] = hex(shiftHue(c3, 0.0, 1.05, 0.08));
    colors[QStringLiteral("color12")] = hex(shiftHue(c4, 0.0, 1.05, 0.08));
    colors[QStringLiteral("color13")] = hex(shiftHue(c5, 0.0, 1.05, 0.08));
    colors[QStringLiteral("color14")] = hex(shiftHue(c6, 0.0, 1.05, 0.08));
    colors[QStringLiteral("color15")] = hex(txt);

    QJsonObject out;
    out[QStringLiteral("special")] = special;
    out[QStringLiteral("colors")] = colors;
    return out;
}

void Sys::startIpcServer() {
    QString runtimeDir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (runtimeDir.isEmpty()) runtimeDir = QDir::tempPath();

    QString instancesDir = runtimeDir + QStringLiteral("/criperto-notes/instances");
    QDir().mkpath(instancesDir);

    qint64 pid = QCoreApplication::applicationPid();
    m_currentInstanceSockPath = instancesDir + QStringLiteral("/") + QString::number(pid) + QStringLiteral(".sock");
    m_currentInstanceJsonPath = instancesDir + QStringLiteral("/") + QString::number(pid) + QStringLiteral(".json");

    QFile::remove(m_currentInstanceSockPath);
    QFile::remove(m_currentInstanceJsonPath);

    m_ipcServer = new QLocalServer(this);
    connect(m_ipcServer, &QLocalServer::newConnection, this, &Sys::onNewIpcConnection);

    m_ipcServer->listen(m_currentInstanceSockPath);

    // Compatibilidad: enlazar notas.sock si no existe
    QString legacySock = runtimeDir + QStringLiteral("/notas.sock");
    if (!QFile::exists(legacySock)) {
        QFile::link(m_currentInstanceSockPath, legacySock);
    }

    updateInstanceStatus(QString(), false);
}

void Sys::onNewIpcConnection() {
    while (m_ipcServer && m_ipcServer->hasPendingConnections()) {
        QLocalSocket *client = m_ipcServer->nextPendingConnection();
        connect(client, &QLocalSocket::readyRead, this, [this, client]() {
            QByteArray raw = client->readAll().trimmed();
            if (!raw.isEmpty()) {
                const QList<QByteArray> lines = raw.split('\n');
                for (const QByteArray &line : lines) {
                    QByteArray trimmed = line.trimmed();
                    if (trimmed.isEmpty()) continue;
                    QJsonDocument doc = QJsonDocument::fromJson(trimmed);
                    if (doc.isObject()) {
                        QJsonObject obj = doc.object();
                        QString action = obj[QStringLiteral("action")].toString();
                        QString target = obj[QStringLiteral("target")].toString();
                        qint64 fromPid = obj[QStringLiteral("fromPid")].toInteger();

                        if (action == QStringLiteral("take_edit_lock")) {
                            emit remoteEditLockClaimed(target, fromPid);
                        } else if (action == QStringLiteral("note_saved")) {
                            emit remoteNoteSaved(target);
                        } else if (action == QStringLiteral("note_deleted")) {
                            emit remoteNoteDeleted(target);
                        } else if (action == QStringLiteral("sync")) {
                            emit quickshellConfigChanged();
                            emit ipcCommandReceived(action, target);
                        } else {
                            emit ipcCommandReceived(action, target);
                        }
                    }
                }
            }
            client->deleteLater();
        });
    }
}

void Sys::updateInstanceStatus(const QString &notePath, bool isEditing) {
    if (m_currentInstanceJsonPath.isEmpty()) return;

    qint64 pid = QCoreApplication::applicationPid();
    qint64 now = QDateTime::currentMSecsSinceEpoch();

    QJsonObject obj;
    obj[QStringLiteral("pid")] = pid;
    obj[QStringLiteral("active_note")] = notePath;
    obj[QStringLiteral("is_editing")] = isEditing;
    obj[QStringLiteral("last_focused")] = now;

    QFile f(m_currentInstanceJsonPath);
    if (f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        f.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
        f.flush();
        f.close();
    }
}

bool Sys::isNoteBeingEditedElsewhere(const QString &notePath) const {
    if (notePath.trimmed().isEmpty()) return false;
    QString runtimeDir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (runtimeDir.isEmpty()) runtimeDir = QDir::tempPath();
    QDir dir(runtimeDir + QStringLiteral("/criperto-notes/instances"));
    if (!dir.exists()) return false;

    qint64 myPid = QCoreApplication::applicationPid();
    const QFileInfoList entries = dir.entryInfoList({QStringLiteral("*.json")}, QDir::Files);
    for (const QFileInfo &fi : entries) {
        QString stem = fi.baseName();
        qint64 pid = stem.toLongLong();
        if (pid == myPid || pid <= 0) continue;

        if (!QFile::exists(QStringLiteral("/proc/") + QString::number(pid))) {
            QFile::remove(fi.absoluteFilePath());
            QFile::remove(dir.absoluteFilePath(stem + QStringLiteral(".sock")));
            continue;
        }

        QFile f(fi.absoluteFilePath());
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
            if (doc.isObject()) {
                QJsonObject obj = doc.object();
                QString active = obj[QStringLiteral("active_note")].toString();
                bool editing = obj[QStringLiteral("is_editing")].toBool();
                if (editing && !active.isEmpty() && active == notePath) {
                    return true;
                }
            }
        }
    }
    return false;
}

static void broadcastToOtherInstances(const QJsonObject &payload, qint64 excludePid) {
    QString runtimeDir = QStandardPaths::writableLocation(QStandardPaths::RuntimeLocation);
    if (runtimeDir.isEmpty()) runtimeDir = QDir::tempPath();
    QDir dir(runtimeDir + QStringLiteral("/criperto-notes/instances"));
    if (!dir.exists()) return;

    QByteArray data = QJsonDocument(payload).toJson(QJsonDocument::Compact) + "\n";
    const QFileInfoList entries = dir.entryInfoList({QStringLiteral("*.sock")}, QDir::Files | QDir::System);
    for (const QFileInfo &fi : entries) {
        QString stem = fi.baseName();
        qint64 pid = stem.toLongLong();
        if (pid == excludePid || pid <= 0) continue;

        if (!QFile::exists(QStringLiteral("/proc/") + QString::number(pid))) {
            QFile::remove(fi.absoluteFilePath());
            QFile::remove(dir.absoluteFilePath(stem + QStringLiteral(".json")));
            continue;
        }

        QLocalSocket sock;
        sock.connectToServer(fi.absoluteFilePath());
        if (sock.waitForConnected(80)) {
            sock.write(data);
            sock.flush();
            sock.waitForBytesWritten(80);
            sock.disconnectFromServer();
        }
    }
}

void Sys::claimEditLock(const QString &notePath) {
    qint64 pid = QCoreApplication::applicationPid();
    updateInstanceStatus(notePath, true);

    QJsonObject msg;
    msg[QStringLiteral("action")] = QStringLiteral("take_edit_lock");
    msg[QStringLiteral("target")] = notePath;
    msg[QStringLiteral("fromPid")] = pid;
    broadcastToOtherInstances(msg, pid);
}

void Sys::broadcastNoteSaved(const QString &notePath) {
    qint64 pid = QCoreApplication::applicationPid();
    updateInstanceStatus(notePath, true);

    QJsonObject msg;
    msg[QStringLiteral("action")] = QStringLiteral("note_saved");
    msg[QStringLiteral("target")] = notePath;
    msg[QStringLiteral("fromPid")] = pid;
    broadcastToOtherInstances(msg, pid);
}

void Sys::broadcastNoteDeleted(const QString &notePath) {
    qint64 pid = QCoreApplication::applicationPid();
    updateInstanceStatus(QString(), false);

    QJsonObject msg;
    msg[QStringLiteral("action")] = QStringLiteral("note_deleted");
    msg[QStringLiteral("target")] = notePath;
    msg[QStringLiteral("fromPid")] = pid;
    broadcastToOtherInstances(msg, pid);
}

QString Sys::clipboardText() const {
    if (auto *cb = QGuiApplication::clipboard()) {
        QString txt = cb->text();
        if (!txt.trimmed().isEmpty()) {
            return txt;
        }
    }

    // Fallback nativo para Wayland cuando la ventana aún no tiene foco activo
    QProcess proc;
    proc.start(QStringLiteral("wl-paste"), {QStringLiteral("-n"), QStringLiteral("--type"), QStringLiteral("text/plain")});
    if (proc.waitForFinished(120)) {
        if (proc.exitCode() == 0) {
            QString out = QString::fromUtf8(proc.readAllStandardOutput());
            if (!out.trimmed().isEmpty()) {
                return out;
            }
        }
    } else {
        proc.kill();
        proc.waitForFinished(50);
    }

    return QString();
}

void Sys::setClipboardText(const QString &text) {
    if (auto *cb = QGuiApplication::clipboard()) {
        cb->setText(text);
    }
}

bool Sys::hasTouchscreen() const {
    if (m_hasTouchscreen != -1) {
        return m_hasTouchscreen == 1;
    }

    m_hasTouchscreen = 0;
    QFile devFile(QStringLiteral("/proc/bus/input/devices"));
    if (devFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&devFile);
        QString content = in.readAll();
        if (content.contains(QStringLiteral("touchscreen"), Qt::CaseInsensitive)) {
            m_hasTouchscreen = 1;
        }
    }
    return m_hasTouchscreen == 1;
}

QString Sys::homeDir() const {
    return QDir::homePath();
}

QString Sys::documentsDir() const {
    QString doc = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (doc.isEmpty()) {
        doc = QDir::homePath() + QStringLiteral("/Documentos");
    }
    return doc;
}

QString Sys::dataShareDir() const {
    QString devDir = QDir::currentPath();
    if (QFile::exists(devDir + QStringLiteral("/qml/Main.qml"))) {
        return devDir;
    }
    QString userShare = QDir::homePath() + QStringLiteral("/.local/share/criperto.notes");
    if (QFile::exists(userShare)) {
        return userShare;
    }
    QString legacyShare = QDir::homePath() + QStringLiteral("/.local/share/notas");
    if (QFile::exists(legacyShare)) {
        return legacyShare;
    }
    if (QFile::exists(QStringLiteral("/usr/share/criperto.notes"))) {
        return QStringLiteral("/usr/share/criperto.notes");
    }
    return QStringLiteral("/usr/share/criperto.notes");
}

QString Sys::appExecutable() const {
    return QCoreApplication::applicationFilePath();
}

static bool isForcedNoSyncConfigured() {
    if (qEnvironmentVariableIsSet("NOTAS_NO_SYNC") || qEnvironmentVariableIsSet("NOTAS_STANDALONE")) {
        return true;
    }
    const QString home = QDir::homePath();
    // 1. ~/.config/notas/config.json
    QFile cfgFile(home + QStringLiteral("/.config/notas/config.json"));
    if (cfgFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QJsonDocument doc = QJsonDocument::fromJson(cfgFile.readAll());
        if (doc.isObject()) {
            QJsonObject obj = doc.object();
            if (obj.contains(QStringLiteral("noSync")) && obj[QStringLiteral("noSync")].toBool(false)) {
                return true;
            }
            if (obj.contains(QStringLiteral("no_sync")) && obj[QStringLiteral("no_sync")].toBool(false)) {
                return true;
            }
            if (obj.contains(QStringLiteral("sync")) && !obj[QStringLiteral("sync")].toBool(true)) {
                return true;
            }
            if (obj.contains(QStringLiteral("syncWithQuickshell")) && !obj[QStringLiteral("syncWithQuickshell")].toBool(true)) {
                return true;
            }
        }
        cfgFile.close();
    }
    // 2. Archivos adicionales de configuración (.conf, .toml)
    const QStringList extraFiles = {
        home + QStringLiteral("/.config/notas/config.conf"),
        home + QStringLiteral("/.config/notas/notas.conf"),
        home + QStringLiteral("/.config/notas/config.toml"),
        home + QStringLiteral("/.config/notas/notas.toml"),
        home + QStringLiteral("/.config/quickshell/config/notes.conf")
    };
    for (const QString &extraPath : extraFiles) {
        if (QFile::exists(extraPath)) {
            QFile ef(extraPath);
            if (ef.open(QIODevice::ReadOnly | QIODevice::Text)) {
                QTextStream in(&ef);
                while (!in.atEnd()) {
                    QString line = in.readLine().trimmed();
                    if (line.isEmpty() || line.startsWith('#') || line.startsWith(';')) continue;
                    int eq = line.indexOf('=');
                    if (eq != -1) {
                        QString k = line.left(eq).trimmed().toLower();
                        QString v = line.mid(eq + 1).trimmed().toLower();
                        if ((k == QStringLiteral("nosync") || k == QStringLiteral("no_sync")) && (v == QStringLiteral("true") || v == QStringLiteral("1"))) {
                            return true;
                        }
                        if ((k == QStringLiteral("sync") || k == QStringLiteral("syncwithquickshell")) && (v == QStringLiteral("false") || v == QStringLiteral("0"))) {
                            return true;
                        }
                    }
                }
                ef.close();
            }
        }
    }
    return false;
}

bool Sys::hasQuickshellConfig() const {
    if (isForcedNoSyncConfigured()) {
        return false;
    }
    const QString home = QDir::homePath();
    return QFile::exists(home + QStringLiteral("/.config/quickshell/config/general.conf"))
        || QFile::exists(home + QStringLiteral("/.config/quickshell/config/theme.conf"));
}

bool Sys::wmNeedsWindowControls() const {
    const QString cli = QString::fromUtf8(qgetenv("NOTAS_WINDOW_CONTROLS")).trimmed().toLower();
    if (cli == QStringLiteral("always")) return true;
    if (cli == QStringLiteral("never")) return false;

    if (qEnvironmentVariableIsSet("HYPRLAND_INSTANCE_SIGNATURE") ||
        qEnvironmentVariableIsSet("SWAYSOCK") ||
        qEnvironmentVariableIsSet("NIRI_SOCKET")) {
        return false;
    }
    const QString desktop = QString::fromUtf8(qgetenv("XDG_CURRENT_DESKTOP")).toLower();
    const QString session = QString::fromUtf8(qgetenv("DESKTOP_SESSION")).toLower();
    if (desktop.contains(QStringLiteral("wayfire")) ||
        desktop.contains(QStringLiteral("quantum")) ||
        session.contains(QStringLiteral("wayfire")) ||
        session.contains(QStringLiteral("quantum")) ||
        qEnvironmentVariableIsSet("WAYFIRE_CONFIG_FILE")) {
        return true;
    }
    return true;
}

void Sys::startSystemMove(QObject *windowObj) {
    if (!windowObj) return;
    auto *win = qobject_cast<QWindow*>(windowObj);
    if (!win) {
        auto *item = qobject_cast<QQuickItem*>(windowObj);
        if (item) win = item->window();
    }
    if (win) {
        win->startSystemMove();
    }
}

namespace {
struct FontResolution {
    QString family;
    QString provenance;
};

FontResolution resolveBodyFont() {
    const QString home = QDir::homePath();
    // 1. Quickshell font config
    QFile qsFontFile(home + QStringLiteral("/.config/quickshell/config/font.conf"));
    if (qsFontFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&qsFontFile);
        while (!in.atEnd()) {
            QString line = in.readLine().trimmed();
            if (line.startsWith(QStringLiteral("fontFamily")) && line.contains('=')) {
                QString val = line.section('=', 1).trimmed();
                if (!val.isEmpty()) return { val, QStringLiteral("[Quickshell font.conf]") };
            }
        }
    }
    // 2. qt6ct font config
    QFile qt6ctFile(home + QStringLiteral("/.config/qt6ct/qt6ct.conf"));
    if (qt6ctFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&qt6ctFile);
        while (!in.atEnd()) {
            QString line = in.readLine().trimmed();
            if (line.startsWith(QStringLiteral("general="))) {
                QString val = line.mid(8).trimmed();
                if (val.startsWith('"') && val.endsWith('"')) {
                    val = val.mid(1, val.length() - 2);
                }
                const QStringList parts = val.split(',');
                if (!parts.isEmpty() && !parts[0].trimmed().isEmpty()) {
                    return { parts[0].trimmed(), QStringLiteral("[Tema Qt / qt6ct]") };
                }
            }
        }
    }
    // 3. Qt application font
    QString appFont = QGuiApplication::font().family();
    if (!appFont.isEmpty() && appFont != QStringLiteral("Sans Serif") && appFont != QStringLiteral("Sans")) {
        return { appFont, QStringLiteral("[Tema Qt / QGuiApplication]") };
    }

    // 4. Fallback de código abierto (SIL Open Font License 1.1)
    const QStringList openSourceCandidates = {
        QStringLiteral("Plus Jakarta Sans"),
        QStringLiteral("Outfit"),
        QStringLiteral("Inter"),
        QStringLiteral("Noto Sans"),
        QStringLiteral("Roboto"),
        QStringLiteral("DejaVu Sans")
    };
    const QStringList installed = QFontDatabase::families();
    for (const QString &cand : openSourceCandidates) {
        if (installed.contains(cand, Qt::CaseInsensitive)) {
            return { cand, QStringLiteral("[Fallback SIL OFL]") };
        }
    }
    return { QStringLiteral("Plus Jakarta Sans"), QStringLiteral("[Fallback SIL OFL]") };
}

FontResolution resolveDisplayFont() {
    const QString home = QDir::homePath();
    // 1. Quickshell font config
    QFile qsFontFile(home + QStringLiteral("/.config/quickshell/config/font.conf"));
    if (qsFontFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&qsFontFile);
        while (!in.atEnd()) {
            QString line = in.readLine().trimmed();
            if (line.startsWith(QStringLiteral("fontFamilyDisplay")) && line.contains('=')) {
                QString val = line.section('=', 1).trimmed();
                if (!val.isEmpty()) return { val, QStringLiteral("[Quickshell font.conf]") };
            }
        }
    }

    // 2. Fallback de código abierto
    const QStringList openSourceCandidates = {
        QStringLiteral("Outfit"),
        QStringLiteral("Plus Jakarta Sans"),
        QStringLiteral("Inter"),
        QStringLiteral("Noto Sans")
    };
    const QStringList installed = QFontDatabase::families();
    for (const QString &cand : openSourceCandidates) {
        if (installed.contains(cand, Qt::CaseInsensitive)) {
            return { cand, QStringLiteral("[Fallback SIL OFL]") };
        }
    }
    FontResolution body = resolveBodyFont();
    if (!body.family.isEmpty() && body.family != QStringLiteral("Plus Jakarta Sans")) {
        return { body.family, body.provenance };
    }
    return { QStringLiteral("Outfit"), QStringLiteral("[Fallback SIL OFL]") };
}

FontResolution resolveRoundedFont() {
    const QString home = QDir::homePath();
    QFile qsFontFile(home + QStringLiteral("/.config/quickshell/config/font.conf"));
    if (qsFontFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&qsFontFile);
        while (!in.atEnd()) {
            QString line = in.readLine().trimmed();
            if (line.startsWith(QStringLiteral("fontFamilyRounded")) && line.contains('=')) {
                QString val = line.section('=', 1).trimmed();
                if (!val.isEmpty()) return { val, QStringLiteral("[Quickshell font.conf]") };
            }
        }
    }
    return resolveBodyFont();
}

FontResolution resolveMonospaceFont() {
    const QString home = QDir::homePath();
    // 1. Quickshell font config
    QFile qsFontFile(home + QStringLiteral("/.config/quickshell/config/font.conf"));
    if (qsFontFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&qsFontFile);
        while (!in.atEnd()) {
            QString line = in.readLine().trimmed();
            if (line.startsWith(QStringLiteral("systemMonospaceFontFamily")) && line.contains('=')) {
                QString val = line.section('=', 1).trimmed();
                if (!val.isEmpty()) return { val, QStringLiteral("[Quickshell font.conf]") };
            }
        }
    }
    // 2. qt6ct fixed font
    QFile qt6ctFile(home + QStringLiteral("/.config/qt6ct/qt6ct.conf"));
    if (qt6ctFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&qt6ctFile);
        while (!in.atEnd()) {
            QString line = in.readLine().trimmed();
            if (line.startsWith(QStringLiteral("fixed="))) {
                QString val = line.mid(6).trimmed();
                if (val.startsWith('"') && val.endsWith('"')) {
                    val = val.mid(1, val.length() - 2);
                }
                const QStringList parts = val.split(',');
                if (!parts.isEmpty() && !parts[0].trimmed().isEmpty()) {
                    return { parts[0].trimmed(), QStringLiteral("[Tema Qt / qt6ct]") };
                }
            }
        }
    }
    // 3. Qt Fixed Font
    QString fixed = QFontDatabase::systemFont(QFontDatabase::FixedFont).family();
    if (!fixed.isEmpty() && fixed != QStringLiteral("Monospace") && fixed != QStringLiteral("Courier")) {
        return { fixed, QStringLiteral("[Tema Qt / QGuiApplication]") };
    }
    // 4. Open source monospace
    const QStringList monoCandidates = {
        QStringLiteral("JetBrains Mono"),
        QStringLiteral("JetBrainsMono Nerd Font"),
        QStringLiteral("Fira Code"),
        QStringLiteral("Cascadia Code"),
        QStringLiteral("Source Code Pro"),
        QStringLiteral("DejaVu Sans Mono")
    };
    const QStringList installed = QFontDatabase::families();
    for (const QString &cand : monoCandidates) {
        if (installed.contains(cand, Qt::CaseInsensitive)) {
            return { cand, QStringLiteral("[Fallback SIL OFL]") };
        }
    }
    return { QStringLiteral("JetBrains Mono"), QStringLiteral("[Fallback SIL OFL]") };
}
} // namespace

QString Sys::systemFontFamily() const {
    return resolveBodyFont().family;
}

QString Sys::systemFontFamilyDisplay() const {
    return resolveDisplayFont().family;
}

QString Sys::systemFontFamilyRounded() const {
    return resolveRoundedFont().family;
}

QString Sys::systemMonospaceFontFamily() const {
    return resolveMonospaceFont().family;
}

void Sys::printStartupDiagnostics() const {
    if (qEnvironmentVariableIsSet("NOTAS_QUIET")) return;
    const QString home = QDir::homePath();
    const QString configPath = home + QStringLiteral("/.config/notas/config.json");
    const bool forcedNoSync = isForcedNoSyncConfigured();
    const bool qsDetected = hasQuickshellConfig();
    const QString qsStatus = qsDetected
        ? QStringLiteral("Detectado e integrado (~/.config/quickshell)")
        : (forcedNoSync ? QStringLiteral("Desactivado por config (noSync / standalone)") : QStringLiteral("No detectado (Modo Standalone)"));

    const FontResolution bodyInfo = resolveBodyFont();
    const FontResolution dispInfo = resolveDisplayFont();
    const FontResolution monoInfo = resolveMonospaceFont();

    const QString hunspellBin = QStandardPaths::findExecutable(QStringLiteral("hunspell"));

    auto formatRow = [](const QString &label, const QString &value) -> QString {
        QString val = value;
        if (val.length() > 57) {
            val = val.left(54) + QStringLiteral("...");
        }
        QString paddedVal = val.leftJustified(57, ' ', true);
        return QStringLiteral("│ • ") + label.leftJustified(14, ' ', true) + QStringLiteral(": ") + paddedVal + QStringLiteral(" │\n");
    };

    fprintf(stdout, "\n");
    fprintf(stdout, "╭─────────────────────────────────────────────────────────────────────────────╮\n");
    fprintf(stdout, "│ 📝 dev.criperto.Notas v0.1.14 (criperto.notes)                             │\n");
    fprintf(stdout, "│    Editor nativo de notas en Markdown para Wayland                          │\n");
    fprintf(stdout, "├─────────────────────────────────────────────────────────────────────────────┤\n");
    fprintf(stdout, "%s", formatRow(QStringLiteral("Configuración"), configPath).toUtf8().constData());
    fprintf(stdout, "%s", formatRow(QStringLiteral("Quickshell"), qsStatus).toUtf8().constData());
    fprintf(stdout, "%s", formatRow(QStringLiteral("Fuente Texto"), bodyInfo.family + QStringLiteral(" ") + bodyInfo.provenance).toUtf8().constData());
    fprintf(stdout, "%s", formatRow(QStringLiteral("Fuente Display"), dispInfo.family + QStringLiteral(" ") + dispInfo.provenance).toUtf8().constData());
    fprintf(stdout, "%s", formatRow(QStringLiteral("Fuente Mono"), monoInfo.family + QStringLiteral(" ") + monoInfo.provenance).toUtf8().constData());
    fprintf(stdout, "%s", formatRow(QStringLiteral("Motor Spell"), hunspellBin.isEmpty() ? QStringLiteral("No encontrado (Desactivado)") : hunspellBin).toUtf8().constData());
    fprintf(stdout, "╰─────────────────────────────────────────────────────────────────────────────╯\n\n");
    fflush(stdout);
}

QString Sys::env(const QString &name, const QString &fallback) const {
    QByteArray val = qgetenv(name.toUtf8().constData());
    if (val.isEmpty()) return fallback;
    return QString::fromUtf8(val);
}

bool Sys::execDetached(const QStringList &args) const {
    if (args.isEmpty()) return false;
    QProcess proc;
    proc.setProgram(args.first());
    proc.setArguments(args.mid(1));
    proc.setStandardInputFile(QProcess::nullDevice());
    proc.setStandardOutputFile(QProcess::nullDevice());
    proc.setStandardErrorFile(QProcess::nullDevice());
    return proc.startDetached();
}

bool Sys::clipboardHasImage() const {
    auto *cb = QGuiApplication::clipboard();
    if (!cb) return false;
    const QMimeData *mime = cb->mimeData();
    if (!mime) return false;
    if (mime->hasImage()) return true;

    if (mime->hasUrls()) {
        const auto urls = mime->urls();
        if (!urls.isEmpty()) {
            QString path = urls.first().toLocalFile();
            QString ext = QFileInfo(path).suffix().toLower();
            return (ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "webp" || ext == "gif" || ext == "svg" || ext == "bmp");
        }
    }
    return false;
}

QString Sys::pasteClipboardImage(const QString &destDir, const QString &baseName, const QString &relPrefix) {
    auto *cb = QGuiApplication::clipboard();
    if (!cb) return QString();
    const QMimeData *mime = cb->mimeData();
    if (!mime) return QString();

    QDir dir(destDir);
    if (!dir.exists()) {
        dir.mkpath(QStringLiteral("."));
    }

    if (mime->hasImage()) {
        QImage img = qvariant_cast<QImage>(mime->imageData());
        if (!img.isNull()) {
            QString destName = baseName + QStringLiteral(".png");
            QString fullPath = dir.filePath(destName);
            if (img.save(fullPath, "PNG")) {
                return relPrefix + destName;
            }
        }
    }

    if (mime->hasUrls()) {
        const auto urls = mime->urls();
        if (!urls.isEmpty()) {
            QString srcPath = urls.first().toLocalFile();
            QFileInfo srcFi(srcPath);
            QString ext = srcFi.suffix().toLower();
            if (ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "webp" || ext == "gif" || ext == "svg" || ext == "bmp") {
                QString destName = baseName + QStringLiteral(".") + ext;
                QString fullPath = dir.filePath(destName);
                if (QFile::copy(srcPath, fullPath)) {
                    return relPrefix + destName;
                }
            }
        }
    }

    return QString();
}

static QString historyDirForNote(const QString &notePath) {
    if (notePath.isEmpty()) return QString();
    QFileInfo fi(notePath);
    QString absPath = fi.absoluteFilePath();
    QString stem = fi.baseName();
    if (stem.isEmpty()) stem = QStringLiteral("note");
    QString safeStem;
    for (const QChar &c : stem) {
        if (c.isLetterOrNumber() || c == QLatin1Char('_') || c == QLatin1Char('-')) {
            safeStem.append(c);
        } else {
            safeStem.append(QLatin1Char('_'));
        }
    }
    quint64 h = 0xcbf29ce484222325ULL;
    QByteArray bytes = absPath.toUtf8();
    for (int i = 0; i < bytes.size(); ++i) {
        h ^= static_cast<quint8>(bytes.at(i));
        h *= 0x100000001b3ULL;
    }
    quint32 folded = static_cast<quint32>((h >> 32) ^ (h & 0xffffffffULL));
    QString hashStr = QStringLiteral("%1").arg(folded, 8, 16, QLatin1Char('0'));
    QString folderName = safeStem + QLatin1Char('-') + hashStr;

    QString stateHome = qEnvironmentVariable("XDG_STATE_HOME");
    QString baseDir;
    if (!stateHome.isEmpty()) {
        baseDir = stateHome + QStringLiteral("/qs-notes/history");
    } else {
        baseDir = QDir::homePath() + QStringLiteral("/.local/state/qs-notes/history");
    }
    return baseDir + QLatin1Char('/') + folderName;
}

QString Sys::loadHistoryUndo(const QString &notePath) const {
    QString dir = historyDirForNote(notePath);
    if (dir.isEmpty()) return QString();
    QFile f(dir + QStringLiteral("/undo.json"));
    if (!f.open(QIODevice::ReadOnly)) return QString();
    return QString::fromUtf8(f.readAll());
}

bool Sys::saveHistoryUndo(const QString &notePath, const QString &jsonData) const {
    QString dir = historyDirForNote(notePath);
    if (dir.isEmpty() || jsonData.isEmpty()) return false;
    QDir().mkpath(dir);
    QSaveFile sf(dir + QStringLiteral("/undo.json"));
    if (!sf.open(QIODevice::WriteOnly)) return false;
    sf.write(jsonData.toUtf8());
    return sf.commit();
}

extern "C" {
    char *notas_render_latex_svg(const char *latex, bool display, const char *color, double pt_size);
    char *notas_diff_lines(const char *text_a, const char *text_b);
    char *notas_diff_words(const char *line_a, const char *line_b);
    char *notas_detect_language(const char *text);
    void notas_free_string(char *ptr);
}

QString Sys::renderLatexSvg(const QString &latex, bool display, const QString &colorHex, double ptSize) const {
    if (latex.trimmed().isEmpty()) return QString();

    static QHash<QString, QString> s_latexCache;
    static QStringList s_cacheKeys;
    const int MAX_CACHE_SIZE = 256;

    QString effectiveColor = colorHex.trimmed();
    if (effectiveColor.isEmpty()) {
        effectiveColor = QStringLiteral("#ffffff");
    }

    QString cacheKey = QStringLiteral("%1|%2|%3|%4")
        .arg(latex)
        .arg(display ? 1 : 0)
        .arg(effectiveColor)
        .arg(QString::number(ptSize, 'f', 1));

    if (s_latexCache.contains(cacheKey)) {
        return s_latexCache.value(cacheKey);
    }

    QByteArray latexBytes = latex.toUtf8();
    QByteArray colorBytes = effectiveColor.toUtf8();
    const char *colPtr = colorBytes.constData();

    char *resPtr = notas_render_latex_svg(latexBytes.constData(), display, colPtr, ptSize);
    if (!resPtr) {
        return QStringLiteral("ERROR:Error desconocido al renderizar fórmula LaTeX");
    }

    QString svgResult = QString::fromUtf8(resPtr);
    notas_free_string(resPtr);

    if (s_cacheKeys.size() >= MAX_CACHE_SIZE) {
        QString oldKey = s_cacheKeys.takeFirst();
        s_latexCache.remove(oldKey);
    }
    s_cacheKeys.append(cacheKey);
    s_latexCache.insert(cacheKey, svgResult);

    return svgResult;
}

QJsonArray Sys::diffLines(const QString &textA, const QString &textB) const {
    QByteArray bytesA = textA.toUtf8();
    QByteArray bytesB = textB.toUtf8();
    char *resPtr = notas_diff_lines(bytesA.constData(), bytesB.constData());
    if (!resPtr) return QJsonArray();

    QByteArray jsonBytes(resPtr);
    notas_free_string(resPtr);

    QJsonDocument doc = QJsonDocument::fromJson(jsonBytes);
    if (doc.isArray()) {
        return doc.array();
    }
    return QJsonArray();
}

QJsonArray Sys::diffWords(const QString &lineA, const QString &lineB) const {
    QByteArray bytesA = lineA.toUtf8();
    QByteArray bytesB = lineB.toUtf8();
    char *resPtr = notas_diff_words(bytesA.constData(), bytesB.constData());
    if (!resPtr) return QJsonArray();

    QByteArray jsonBytes(resPtr);
    notas_free_string(resPtr);

    QJsonDocument doc = QJsonDocument::fromJson(jsonBytes);
    if (doc.isArray()) {
        return doc.array();
    }
    return QJsonArray();
}

QString Sys::detectLanguage(const QString &text) const {
    if (text.trimmed().length() < 8) return QString();
    QByteArray bytes = text.toUtf8();
    char *resPtr = notas_detect_language(bytes.constData());
    if (!resPtr) return QString();

    QString lang = QString::fromUtf8(resPtr);
    notas_free_string(resPtr);
    return lang;
}

QJsonObject Sys::indexNotes(const QString &notesDirStr) const {
    QJsonObject root;
    QJsonArray notesArr;
    QJsonObject imagesObj;

    QDir dir(notesDirStr);
    if (!dir.exists()) {
        root[QStringLiteral("ok")] = false;
        root[QStringLiteral("notes")] = notesArr;
        root[QStringLiteral("images")] = imagesObj;
        return root;
    }

    QDirIterator it(notesDirStr, QDir::Files | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        it.next();
        QFileInfo fi = it.fileInfo();
        QString path = fi.absoluteFilePath();
        QString relPath = dir.relativeFilePath(path);

        if (relPath.startsWith(QStringLiteral(".")) || relPath.contains(QStringLiteral("/."))) {
            continue;
        }

        QString ext = fi.suffix().toLower();
        if (ext == "md" || ext == "txt") {
            QJsonObject meta;
            QString slug = relPath;
            if (slug.endsWith(QStringLiteral(".md")) || slug.endsWith(QStringLiteral(".txt"))) {
                slug.chop(fi.suffix().length() + 1);
            }
            meta[QStringLiteral("key")] = relPath;
            meta[QStringLiteral("slug")] = slug;
            meta[QStringLiteral("id")] = slug;
            meta[QStringLiteral("fileName")] = relPath;
            meta[QStringLiteral("filePath")] = path;
            meta[QStringLiteral("fileModified")] = fi.lastModified().toString(Qt::ISODate);
            meta[QStringLiteral("mtime")] = static_cast<double>(fi.lastModified().toMSecsSinceEpoch());
            meta[QStringLiteral("size")] = static_cast<qint64>(fi.size());

            bool isFolder = fi.fileName().startsWith(QStringLiteral("index.")) || fi.dir().dirName() == fi.baseName();
            meta[QStringLiteral("isFolderNote")] = isFolder;
            meta[QStringLiteral("baseFolder")] = fi.absolutePath();

            QFile nf(path);
            QString title = fi.baseName();
            QString subtitle;
            QJsonArray tags;
            bool pinned = false;
            QString color;
            QJsonArray previewImgs;

            if (nf.open(QIODevice::ReadOnly | QIODevice::Text)) {
                QTextStream nIn(&nf);
                QString line = nIn.readLine();
                if (line.trimmed() == QStringLiteral("---")) {
                    while (!nIn.atEnd()) {
                        line = nIn.readLine();
                        if (line.trimmed() == QStringLiteral("---")) break;
                        int colon = line.indexOf(':');
                        if (colon != -1) {
                            QString k = line.left(colon).trimmed().toLower();
                            QString v = line.mid(colon + 1).trimmed();
                            if (k == "title" && !v.isEmpty()) title = v.remove('"');
                            else if (k == "subtitle" && !v.isEmpty()) subtitle = v.remove('"');
                            else if (k == "pinned") pinned = (v.toLower() == "true");
                            else if (k == "color") color = v.remove('"');
                            else if (k == "tags") {
                                QString raw = v.remove('[').remove(']').remove('"');
                                const auto parts = raw.split(',', Qt::SkipEmptyParts);
                                for (const auto &p : parts) tags.append(p.trimmed());
                            }
                        }
                    }
                }
                if (title == fi.baseName()) {
                    while (!nIn.atEnd()) {
                        line = nIn.readLine().trimmed();
                        if (line.startsWith(QStringLiteral("# "))) {
                            title = line.mid(2).trimmed();
                            break;
                        }
                    }
                }
                nf.close();
            }

            meta[QStringLiteral("title")] = title;
            meta[QStringLiteral("subtitle")] = subtitle;
            meta[QStringLiteral("tags")] = tags;
            meta[QStringLiteral("pinned")] = pinned;
            meta[QStringLiteral("color")] = color;
            meta[QStringLiteral("previewImages")] = previewImgs;

            notesArr.append(meta);
        } else if (ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "webp" || ext == "gif" || ext == "bmp") {
            QImageReader reader(path);
            QSize sz = reader.size();
            if (sz.isValid()) {
                QJsonObject dims;
                dims[QStringLiteral("width")] = sz.width();
                dims[QStringLiteral("height")] = sz.height();
                imagesObj[relPath] = dims;
            }
        }
    }

    root[QStringLiteral("ok")] = true;
    root[QStringLiteral("notes")] = notesArr;
    root[QStringLiteral("images")] = imagesObj;
    return root;
}

// ═════════════════════════════════════════════════════════════════════════════
// 5. ConfigBackend Implementation
// ═════════════════════════════════════════════════════════════════════════════

ConfigBackend::ConfigBackend(QObject *parent)
    : QObject(parent)
{
    m_notasDir = QStringLiteral("$XDG_DOCUMENTS_DIR/notes");
    if (!QFile::exists(QDir::homePath() + QStringLiteral("/.cache/wal/colors.json"))) {
        m_themeMode = QStringLiteral("qt");
    }

    m_saveTimer = new QTimer(this);
    m_saveTimer->setSingleShot(true);
    m_saveTimer->setInterval(250);
    connect(m_saveTimer, &QTimer::timeout, this, &ConfigBackend::save);

    load();

    if (hasQuickshellConfig()) {
        loadQuickshellConfig();
        setupQuickshellWatcher();
    }
}

ConfigBackend::~ConfigBackend() {
    if (m_saveTimer && m_saveTimer->isActive()) {
        m_saveTimer->stop();
        save();
    }
}

static bool extractLuaTableBool(const QString &filePath, const QString &tableName, const QString &keyName, bool defaultVal) {
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return defaultVal;
    QTextStream in(&file);
    QString content = in.readAll();
    file.close();

    int idx = content.indexOf(QRegularExpression(QStringLiteral("\\b") + tableName + QStringLiteral("\\s*=\\s*\\{")));
    if (idx == -1) return defaultVal;

    int openBrace = content.indexOf('{', idx);
    if (openBrace == -1) return defaultVal;

    int depth = 0;
    int closeBrace = -1;
    for (int i = openBrace; i < content.length(); ++i) {
        if (content[i] == '{') {
            depth++;
        } else if (content[i] == '}') {
            depth--;
            if (depth == 0) {
                closeBrace = i;
                break;
            }
        }
    }
    if (closeBrace == -1) closeBrace = content.length();

    QString block = content.mid(openBrace + 1, closeBrace - openBrace - 1);
    QRegularExpression keyRegex(QStringLiteral("\\b") + keyName + QStringLiteral("\\s*=\\s*(true|false)"), QRegularExpression::CaseInsensitiveOption);
    auto keyMatch = keyRegex.match(block);
    if (keyMatch.hasMatch()) {
        return keyMatch.captured(1).compare(QStringLiteral("true"), Qt::CaseInsensitive) == 0;
    }
    return defaultVal;
}

bool ConfigBackend::hasQuickshellConfig() const {
    if (isForcedNoSyncConfigured()) {
        return false;
    }
    if (!m_syncWithQuickshell) {
        return false;
    }
    const QString home = QDir::homePath();
    return QFile::exists(home + QStringLiteral("/.config/quickshell/config/general.conf"))
        || QFile::exists(home + QStringLiteral("/.config/quickshell/config/theme.conf"));
}

void ConfigBackend::setSyncWithQuickshell(bool val) {
    if (m_syncWithQuickshell == val) return;
    m_syncWithQuickshell = val;
    emit syncWithQuickshellChanged();
    emit hasQuickshellConfigChanged();
    if (hasQuickshellConfig()) {
        loadQuickshellConfig();
        setupQuickshellWatcher();
    } else {
        if (m_qsWatcher) {
            delete m_qsWatcher;
            m_qsWatcher = nullptr;
        }
        load();
    }
    scheduleSave();
}

void ConfigBackend::loadQuickshellConfig() {
    const QString home = QDir::homePath();
    bool changedOpacity = false;
    bool changedScrollbars = false;
    bool changedThemeMode = false;
    bool changedCustomTheme = false;
    bool changedLightMode = false;
    bool changedNotesDir = false;
    bool changedPreviews = false;
    bool changedCycle = false;
    bool changedCardsPerRow = false;
    bool changedImportMode = false;
    bool changedExternalMode = false;
    bool changedCloseAction = false;
    bool changedZoom = false;
    bool changedSpellMode = false;
    bool changedBlur = false;
    bool changedAnimations = false;
    bool changedFontScale = false;

    // 1. General config
    QFile genFile(home + QStringLiteral("/.config/quickshell/config/general.conf"));
    if (genFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&genFile);
        while (!in.atEnd()) {
            QString line = in.readLine().trimmed();
            if (line.isEmpty() || line.startsWith('#') || line.startsWith(';')) continue;
            int eq = line.indexOf('=');
            if (eq == -1) continue;
            QString k = line.left(eq).trimmed();
            QString v = line.mid(eq + 1).trimmed();
            if (k == QStringLiteral("panelOpacity")) {
                int op = qBound(20, v.toInt(), 100);
                if (m_panelOpacity != op) {
                    m_panelOpacity = op;
                    changedOpacity = true;
                }
            } else if (k == QStringLiteral("hideScrollbars")) {
                bool hs = (v.compare(QStringLiteral("true"), Qt::CaseInsensitive) == 0);
                if (m_hideScrollbars != hs) {
                    m_hideScrollbars = hs;
                    changedScrollbars = true;
                }
            } else if (k == QStringLiteral("animationsEnabled") || k == QStringLiteral("animations")) {
                bool ae = (v.compare(QStringLiteral("true"), Qt::CaseInsensitive) == 0);
                if (m_animationsEnabled != ae) {
                    m_animationsEnabled = ae;
                    changedAnimations = true;
                }
            } else if (k == QStringLiteral("blurEnabled") || k == QStringLiteral("blur")) {
                bool be = (v.compare(QStringLiteral("true"), Qt::CaseInsensitive) == 0);
                if (m_blurEnabled != be) {
                    m_blurEnabled = be;
                    changedBlur = true;
                }
            }
        }
        genFile.close();
    }

    // 2. Theme config
    QFile themeFile(home + QStringLiteral("/.config/quickshell/config/theme.conf"));
    if (themeFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&themeFile);
        while (!in.atEnd()) {
            QString line = in.readLine().trimmed();
            if (line.isEmpty() || line.startsWith('#') || line.startsWith(';')) continue;
            int eq = line.indexOf('=');
            if (eq == -1) continue;
            QString k = line.left(eq).trimmed();
            QString v = line.mid(eq + 1).trimmed();
            if (k == QStringLiteral("useWallpaperColor")) {
                bool useWal = (v.compare(QStringLiteral("true"), Qt::CaseInsensitive) == 0);
                QString mode = useWal ? QStringLiteral("pywal") : QStringLiteral("custom");
                if (m_themeMode != mode) {
                    m_themeMode = mode;
                    changedThemeMode = true;
                }
            } else if (k == QStringLiteral("customThemeName")) {
                if (!v.isEmpty() && m_customThemeName != v) {
                    m_customThemeName = v;
                    changedCustomTheme = true;
                }
            } else if (k == QStringLiteral("lightMode")) {
                bool lm = (v.compare(QStringLiteral("true"), Qt::CaseInsensitive) == 0);
                if (m_lightMode != lm) {
                    m_lightMode = lm;
                    changedLightMode = true;
                }
            }
        }
        themeFile.close();
    }

    // 3. Notes config
    QFile notesFile(home + QStringLiteral("/.config/quickshell/config/notes.conf"));
    if (notesFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&notesFile);
        while (!in.atEnd()) {
            QString line = in.readLine().trimmed();
            if (line.isEmpty() || line.startsWith('#') || line.startsWith(';')) continue;
            int eq = line.indexOf('=');
            if (eq == -1) continue;
            QString k = line.left(eq).trimmed();
            QString v = line.mid(eq + 1).trimmed();
            if (k == QStringLiteral("notesDir")) {
                QString expanded = v;
                if (expanded.contains(QStringLiteral("$HOME"))) {
                    expanded.replace(QStringLiteral("$HOME"), home);
                }
                if (expanded.contains(QStringLiteral("$XDG_DOCUMENTS_DIR"))) {
                    QString docs = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
                    if (docs.isEmpty()) docs = home + QStringLiteral("/Documentos");
                    expanded.replace(QStringLiteral("$XDG_DOCUMENTS_DIR"), docs);
                }
                if (expanded.startsWith(QStringLiteral("~/"))) {
                    expanded = home + expanded.mid(1);
                }
                if (!expanded.isEmpty() && m_notasDir != expanded) {
                    m_notasDir = expanded;
                    changedNotesDir = true;
                }
            } else if (k == QStringLiteral("showImagePreviews")) {
                bool sp = (v.compare(QStringLiteral("true"), Qt::CaseInsensitive) == 0);
                if (m_showImagePreviews != sp) {
                    m_showImagePreviews = sp;
                    changedPreviews = true;
                }
            } else if (k == QStringLiteral("cyclePreviewImages")) {
                bool cp = (v.compare(QStringLiteral("true"), Qt::CaseInsensitive) == 0);
                if (m_cyclePreviewImages != cp) {
                    m_cyclePreviewImages = cp;
                    changedCycle = true;
                }
            } else if (k == QStringLiteral("cardsPerRow")) {
                int cpr = qBound(2, v.toInt(), 5);
                if (m_cardsPerRow != cpr) {
                    m_cardsPerRow = cpr;
                    changedCardsPerRow = true;
                }
            } else if (k == QStringLiteral("importMode")) {
                if (!v.isEmpty() && m_importMode != v) {
                    m_importMode = v;
                    changedImportMode = true;
                }
            } else if (k == QStringLiteral("externalFileOpenMode")) {
                if (!v.isEmpty() && m_externalFileOpenMode != v) {
                    m_externalFileOpenMode = v;
                    changedExternalMode = true;
                }
            } else if (k == QStringLiteral("previewCloseAction")) {
                if (!v.isEmpty() && m_previewCloseAction != v) {
                    m_previewCloseAction = v;
                    changedCloseAction = true;
                }
            } else if (k == QStringLiteral("editorZoom")) {
                int z = qBound(50, v.toInt(), 300);
                if (z > 0 && m_editorZoom != z) {
                    m_editorZoom = z;
                    changedZoom = true;
                }
            } else if (k == QStringLiteral("spellcheckMode")) {
                if (!v.isEmpty() && m_spellcheckMode != v) {
                    m_spellcheckMode = v;
                    changedSpellMode = true;
                }
            }
        }
        notesFile.close();
    }

    // 4. Hyprland Lua settings (blur & animations)
    const QString userSettingsLua = home + QStringLiteral("/.config/hypr/user_settings.lua");
    const QString themeLua = home + QStringLiteral("/.config/hypr/theme.lua");

    if (QFile::exists(userSettingsLua) || QFile::exists(themeLua)) {
        bool hyprBlur = true;
        if (QFile::exists(userSettingsLua)) {
            hyprBlur = extractLuaTableBool(userSettingsLua, QStringLiteral("blur"), QStringLiteral("enabled"), true);
        } else if (QFile::exists(themeLua)) {
            hyprBlur = extractLuaTableBool(themeLua, QStringLiteral("blur"), QStringLiteral("enabled"), true);
        }
        if (m_blurEnabled != hyprBlur) {
            m_blurEnabled = hyprBlur;
            changedBlur = true;
        }

        bool hyprAnim = true;
        if (QFile::exists(userSettingsLua)) {
            hyprAnim = extractLuaTableBool(userSettingsLua, QStringLiteral("animations"), QStringLiteral("enabled"), true);
        } else if (QFile::exists(themeLua)) {
            hyprAnim = extractLuaTableBool(themeLua, QStringLiteral("animations"), QStringLiteral("enabled"), true);
        }
        if (m_animationsEnabled != hyprAnim) {
            m_animationsEnabled = hyprAnim;
            changedAnimations = true;
        }
    }

    // 5. Quickshell font config (fontSizeScale)
    QFile fontFile(home + QStringLiteral("/.config/quickshell/config/font.conf"));
    if (fontFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&fontFile);
        while (!in.atEnd()) {
            QString line = in.readLine().trimmed();
            if (line.isEmpty() || line.startsWith('#') || line.startsWith(';')) continue;
            int eq = line.indexOf('=');
            if (eq == -1) continue;
            QString k = line.left(eq).trimmed();
            QString v = line.mid(eq + 1).trimmed();
            if (k == QStringLiteral("fontSizeScale")) {
                bool ok = false;
                double sc = v.toDouble(&ok);
                if (ok && sc >= 0.5 && sc <= 2.5) {
                    double clamped = qBound(0.85, sc, 1.35);
                    if (!qFuzzyCompare(m_fontSizeScale, clamped)) {
                        m_fontSizeScale = clamped;
                        changedFontScale = true;
                    }
                }
            }
        }
        fontFile.close();
    }

    if (changedOpacity) emit panelOpacityChanged();
    if (changedScrollbars) emit hideScrollbarsChanged();
    if (changedBlur) emit blurEnabledChanged();
    if (changedAnimations) emit animationsEnabledChanged();
    if (changedFontScale) emit fontSizeScaleChanged();
    if (changedThemeMode) emit themeModeChanged();
    if (changedCustomTheme) emit customThemeNameChanged();
    if (changedLightMode) emit lightModeChanged();
    if (changedNotesDir) emit notasDirChanged();
    if (changedPreviews) emit showImagePreviewsChanged();
    if (changedCycle) emit cyclePreviewImagesChanged();
    if (changedCardsPerRow) emit cardsPerRowChanged();
    if (changedImportMode) emit importModeChanged();
    if (changedExternalMode) emit externalFileOpenModeChanged();
    if (changedCloseAction) emit previewCloseActionChanged();
    if (changedZoom) emit editorZoomChanged();
    if (changedSpellMode) emit spellcheckModeChanged();
}

void ConfigBackend::setupQuickshellWatcher() {
    if (!m_qsWatcher) {
        m_qsWatcher = new QFileSystemWatcher(this);
        connect(m_qsWatcher, &QFileSystemWatcher::fileChanged, this, [this]() {
            QTimer::singleShot(150, this, [this]() {
                loadQuickshellConfig();
                setupQuickshellWatcher();
            });
        });
    }

    const QString home = QDir::homePath();
    const QStringList qsFiles = {
        home + QStringLiteral("/.config/quickshell/config/general.conf"),
        home + QStringLiteral("/.config/quickshell/config/theme.conf"),
        home + QStringLiteral("/.config/quickshell/config/notes.conf"),
        home + QStringLiteral("/.config/quickshell/config/font.conf"),
        home + QStringLiteral("/.config/hypr/user_settings.lua"),
        home + QStringLiteral("/.config/hypr/theme.lua")
    };
    for (const auto &f : qsFiles) {
        if (QFile::exists(f) && !m_qsWatcher->files().contains(f)) {
            m_qsWatcher->addPath(f);
        }
    }
}

QString ConfigBackend::configFilePath() const {
    return QDir::homePath() + QStringLiteral("/.config/notas/config.json");
}

QString ConfigBackend::legacyConfigFilePath() const {
    return QDir::homePath() + QStringLiteral("/.config/quickshell/config/notes.conf");
}

void ConfigBackend::scheduleSave() {
    if (m_saveTimer) {
        m_saveTimer->start();
    }
}

void ConfigBackend::setNotasDir(const QString &val) {
    if (m_notasDir == val) return;
    m_notasDir = val;
    emit notasDirChanged();
    scheduleSave();
}

QString ConfigBackend::resolvedNotasDir() const {
    QString p = m_notasDir.trimmed();
    if (p.isEmpty()) p = QStringLiteral("$XDG_DOCUMENTS_DIR/notes");
    const QString home = QDir::homePath();
    if (p == QStringLiteral("~")) return home;
    if (p.startsWith(QStringLiteral("~/"))) p = home + p.mid(1);
    p.replace(QStringLiteral("$HOME"), home);
    QString docs = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (docs.isEmpty()) docs = home + QStringLiteral("/Documentos");
    p.replace(QStringLiteral("$XDG_DOCUMENTS_DIR"), docs);
    if (p.length() > 1 && p.endsWith('/')) p.chop(1);
    return p;
}

QString ConfigBackend::windowControlsMode() const {
    const QString cli = QString::fromUtf8(qgetenv("NOTAS_WINDOW_CONTROLS")).trimmed().toLower();
    if (!cli.isEmpty()) {
        return cli;
    }
    return m_windowControlsMode;
}

void ConfigBackend::setWindowControlsMode(const QString &val) {
    if (m_windowControlsMode == val) return;
    m_windowControlsMode = val;
    emit windowControlsModeChanged();
    scheduleSave();
}

void ConfigBackend::setEditorFontSize(int val) {
    if (m_editorFontSize == val) return;
    m_editorFontSize = val;
    emit editorFontSizeChanged();
    scheduleSave();
}

void ConfigBackend::setEditorZoom(int val) {
    if (m_editorZoom == val) return;
    m_editorZoom = val;
    emit editorZoomChanged();
    scheduleSave();
}

void ConfigBackend::setShowImagePreviews(bool val) {
    if (m_showImagePreviews == val) return;
    m_showImagePreviews = val;
    emit showImagePreviewsChanged();
    scheduleSave();
}

void ConfigBackend::setCyclePreviewImages(bool val) {
    if (m_cyclePreviewImages == val) return;
    m_cyclePreviewImages = val;
    emit cyclePreviewImagesChanged();
    scheduleSave();
}

void ConfigBackend::setBlurEnabled(bool val) {
    if (m_blurEnabled == val) return;
    m_blurEnabled = val;
    emit blurEnabledChanged();
    scheduleSave();
}

void ConfigBackend::setLanguage(const QString &val) {
    if (m_language == val) return;
    m_language = val;
    emit languageChanged();
    scheduleSave();
}

void ConfigBackend::setSpellCheckEnabled(bool val) {
    if (m_spellCheckEnabled == val) return;
    m_spellCheckEnabled = val;
    emit spellCheckEnabledChanged();
    scheduleSave();
}

void ConfigBackend::setSpellCheckLanguage(const QString &val) {
    if (m_spellCheckLanguage == val) return;
    m_spellCheckLanguage = val;
    emit spellCheckLanguageChanged();
    scheduleSave();
}

void ConfigBackend::setThemeMode(const QString &val) {
    if (m_themeMode == val) return;
    m_themeMode = val;
    emit themeModeChanged();
    scheduleSave();
}

void ConfigBackend::setHideScrollbars(bool val) {
    if (m_hideScrollbars == val) return;
    m_hideScrollbars = val;
    emit hideScrollbarsChanged();
    scheduleSave();
}

void ConfigBackend::setCardsPerRow(int val) {
    int clamped = qBound(2, val, 5);
    if (m_cardsPerRow == clamped) return;
    m_cardsPerRow = clamped;
    emit cardsPerRowChanged();
    scheduleSave();
}

void ConfigBackend::setImportMode(const QString &val) {
    if (m_importMode == val) return;
    m_importMode = val;
    emit importModeChanged();
    scheduleSave();
}

void ConfigBackend::setExternalFileOpenMode(const QString &val) {
    if (m_externalFileOpenMode == val) return;
    m_externalFileOpenMode = val;
    emit externalFileOpenModeChanged();
    scheduleSave();
}

void ConfigBackend::setPreviewCloseAction(const QString &val) {
    if (m_previewCloseAction == val) return;
    m_previewCloseAction = val;
    emit previewCloseActionChanged();
    scheduleSave();
}

void ConfigBackend::setSpellcheckMode(const QString &val) {
    if (m_spellcheckMode == val) return;
    m_spellcheckMode = val;
    emit spellcheckModeChanged();
    scheduleSave();
}

void ConfigBackend::setDisabledSpellLanguages(const QString &val) {
    if (m_disabledSpellLanguages == val) return;
    m_disabledSpellLanguages = val;
    emit disabledSpellLanguagesChanged();
    scheduleSave();
}

void ConfigBackend::setPrimarySpellLanguage(const QString &val) {
    if (m_primarySpellLanguage == val) return;
    m_primarySpellLanguage = val;
    emit primarySpellLanguageChanged();
    scheduleSave();
}

void ConfigBackend::setIgnoreUppercase(bool val) {
    if (m_ignoreUppercase == val) return;
    m_ignoreUppercase = val;
    emit ignoreUppercaseChanged();
    scheduleSave();
}

void ConfigBackend::setIgnoreWithDigits(bool val) {
    if (m_ignoreWithDigits == val) return;
    m_ignoreWithDigits = val;
    emit ignoreWithDigitsChanged();
    scheduleSave();
}

void ConfigBackend::setAutoDetectParagraphLanguage(bool val) {
    if (m_autoDetectParagraphLanguage == val) return;
    m_autoDetectParagraphLanguage = val;
    emit autoDetectParagraphLanguageChanged();
    scheduleSave();
}

void ConfigBackend::setPanelOpacity(int val) {
    int clamped = qBound(20, val, 100);
    if (m_panelOpacity == clamped) return;
    m_panelOpacity = clamped;
    emit panelOpacityChanged();
    scheduleSave();
}

void ConfigBackend::setAnimationsEnabled(bool val) {
    if (m_animationsEnabled == val) return;
    m_animationsEnabled = val;
    emit animationsEnabledChanged();
    scheduleSave();
}

void ConfigBackend::setFontSizeScale(double val) {
    double clamped = qBound(0.85, val, 1.35);
    if (qFuzzyCompare(m_fontSizeScale, clamped)) return;
    m_fontSizeScale = clamped;
    emit fontSizeScaleChanged();
    scheduleSave();
}

void ConfigBackend::setUiScale(double val) {
    double clamped = qBound(0.75, val, 2.0);
    if (qFuzzyCompare(m_uiScale, clamped)) return;
    m_uiScale = clamped;
    emit uiScaleChanged();
    scheduleSave();
}

void ConfigBackend::setCustomThemeName(const QString &val) {
    if (m_customThemeName == val || val.isEmpty()) return;
    m_customThemeName = val;
    emit customThemeNameChanged();
    scheduleSave();
}

void ConfigBackend::setLightMode(bool val) {
    if (m_lightMode == val) return;
    m_lightMode = val;
    emit lightModeChanged();
    scheduleSave();
}

void ConfigBackend::setVersionHistoryEnabled(bool val) {
    if (m_versionHistoryEnabled == val) return;
    m_versionHistoryEnabled = val;
    emit versionHistoryEnabledChanged();
    scheduleSave();
}

void ConfigBackend::setVersionHistoryMax(int val) {
    int bounded = qBound(10, val, 200);
    if (m_versionHistoryMax == bounded) return;
    m_versionHistoryMax = bounded;
    emit versionHistoryMaxChanged();
    scheduleSave();
}

void ConfigBackend::setVersionHistoryMaxMb(int val) {
    int bounded = qBound(1, val, 100);
    if (m_versionHistoryMaxMb == bounded) return;
    m_versionHistoryMaxMb = bounded;
    emit versionHistoryMaxMbChanged();
    scheduleSave();
}

void ConfigBackend::setPersistUndo(bool val) {
    if (m_persistUndo == val) return;
    m_persistUndo = val;
    emit persistUndoChanged();
    scheduleSave();
}

void ConfigBackend::setShowSourceModeButton(bool val) {
    if (m_showSourceModeButton == val) return;
    m_showSourceModeButton = val;
    emit showSourceModeButtonChanged();
    scheduleSave();
}

void ConfigBackend::load() {
    const bool hasPywal = QFile::exists(QDir::homePath() + QStringLiteral("/.cache/wal/colors.json"));
    QString path = configFilePath();
    if (QFile::exists(path)) {
        QFile file(path);
        if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
            if (doc.isObject()) {
                QJsonObject obj = doc.object();
                if (obj.contains("notasDir")) {
                    QString nd = obj["notasDir"].toString().trimmed();
                    if (!nd.isEmpty()) m_notasDir = nd;
                }
                if (obj.contains("editorFontSize")) m_editorFontSize = obj["editorFontSize"].toInt(16);
                if (obj.contains("editorZoom")) m_editorZoom = obj["editorZoom"].toInt(100);
                if (obj.contains("showImagePreviews")) m_showImagePreviews = obj["showImagePreviews"].toBool(true);
                if (obj.contains("cyclePreviewImages")) m_cyclePreviewImages = obj["cyclePreviewImages"].toBool(true);
                if (obj.contains("blurEnabled")) m_blurEnabled = obj["blurEnabled"].toBool(true);
                if (obj.contains("language")) m_language = obj["language"].toString("auto");
                if (obj.contains("spellCheckEnabled")) m_spellCheckEnabled = obj["spellCheckEnabled"].toBool(true);
                if (obj.contains("spellCheckLanguage")) m_spellCheckLanguage = obj["spellCheckLanguage"].toString("auto");
                if (obj.contains("themeMode")) m_themeMode = obj["themeMode"].toString(hasPywal ? "pywal" : "qt");
                if (obj.contains("hideScrollbars")) m_hideScrollbars = obj["hideScrollbars"].toBool(false);

                if (obj.contains("cardsPerRow")) m_cardsPerRow = obj["cardsPerRow"].toInt(3);
                if (obj.contains("importMode")) m_importMode = obj["importMode"].toString("move");
                if (obj.contains("externalFileOpenMode")) m_externalFileOpenMode = obj["externalFileOpenMode"].toString("preview");
                if (obj.contains("previewCloseAction")) m_previewCloseAction = obj["previewCloseAction"].toString("home");
                if (obj.contains("spellcheckMode")) m_spellcheckMode = obj["spellcheckMode"].toString("auto");
                if (obj.contains("disabledSpellLanguages")) m_disabledSpellLanguages = obj["disabledSpellLanguages"].toString();
                if (obj.contains("primarySpellLanguage")) m_primarySpellLanguage = obj["primarySpellLanguage"].toString();
                if (obj.contains("ignoreUppercase")) m_ignoreUppercase = obj["ignoreUppercase"].toBool(true);
                if (obj.contains("ignoreWithDigits")) m_ignoreWithDigits = obj["ignoreWithDigits"].toBool(true);
                if (obj.contains("autoDetectParagraphLanguage")) m_autoDetectParagraphLanguage = obj["autoDetectParagraphLanguage"].toBool(true);
                if (obj.contains("panelOpacity")) m_panelOpacity = qBound(20, obj["panelOpacity"].toInt(94), 100);
                if (obj.contains("animationsEnabled")) m_animationsEnabled = obj["animationsEnabled"].toBool(true);
                if (obj.contains("fontSizeScale")) m_fontSizeScale = obj["fontSizeScale"].toDouble(1.0);
                if (obj.contains("uiScale")) m_uiScale = qBound(0.75, obj["uiScale"].toDouble(1.0), 2.0);
                if (obj.contains("customThemeName")) m_customThemeName = obj["customThemeName"].toString("amarillo");
                if (obj.contains("lightMode")) m_lightMode = obj["lightMode"].toBool(false);
                if (obj.contains("syncWithQuickshell")) m_syncWithQuickshell = obj["syncWithQuickshell"].toBool(true);
                if (obj.contains("versionHistoryEnabled")) m_versionHistoryEnabled = obj["versionHistoryEnabled"].toBool(true);
                if (obj.contains("versionHistoryMax")) m_versionHistoryMax = qBound(10, obj["versionHistoryMax"].toInt(50), 200);
                if (obj.contains("versionHistoryMaxMb")) m_versionHistoryMaxMb = qBound(1, obj["versionHistoryMaxMb"].toInt(5), 100);
                if (obj.contains("persistUndo")) m_persistUndo = obj["persistUndo"].toBool(true);
                if (obj.contains("showSourceModeButton")) m_showSourceModeButton = obj["showSourceModeButton"].toBool(false);
                if (obj.contains("windowControlsMode")) m_windowControlsMode = obj["windowControlsMode"].toString("auto");
                if (isForcedNoSyncConfigured()) m_syncWithQuickshell = false;

                // Migrar modos antiguos inexistentes ("dark", "light", "system")
                bool migrated = false;
                if (m_themeMode == QStringLiteral("dark")) {
                    m_themeMode = hasPywal ? QStringLiteral("pywal") : QStringLiteral("custom");
                    m_lightMode = false;
                    migrated = true;
                } else if (m_themeMode == QStringLiteral("light")) {
                    m_themeMode = QStringLiteral("custom");
                    m_lightMode = true;
                    migrated = true;
                } else if (m_themeMode == QStringLiteral("system")) {
                    m_themeMode = QStringLiteral("qt");
                    migrated = true;
                }
                file.close();
                if (migrated) save();
                return;
            }
            file.close();
            return;
        }
    }

    // Migración inicial desde legacy notes.conf si existe
    QString legacyPath = legacyConfigFilePath();
    if (QFile::exists(legacyPath)) {
        QFile lf(legacyPath);
        if (lf.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&lf);
            while (!in.atEnd()) {
                QString line = in.readLine().trimmed();
                if (line.isEmpty() || line.startsWith('#')) continue;
                int eq = line.indexOf('=');
                if (eq != -1) {
                    QString k = line.left(eq).trimmed();
                    QString v = line.mid(eq + 1).trimmed();
                    if (k == "notasDir" && !v.isEmpty()) m_notasDir = v;
                    else if (k == "editorFontSize") m_editorFontSize = v.toInt();
                    else if (k == "editorZoom") m_editorZoom = v.toInt();
                    else if (k == "showImagePreviews") m_showImagePreviews = (v == "true");
                    else if (k == "cyclePreviewImages") m_cyclePreviewImages = (v == "true");
                    else if (k == "blurEnabled") m_blurEnabled = (v == "true");
                    else if (k == "language") m_language = v;
                    else if (k == "spellCheckEnabled") m_spellCheckEnabled = (v == "true");
                    else if (k == "spellCheckLanguage") m_spellCheckLanguage = v;
                    else if (k == "themeMode") m_themeMode = v;
                    else if (k == "hideScrollbars") m_hideScrollbars = (v == "true");
                }
            }
            lf.close();
            save();
        }
    }
}

void ConfigBackend::save() {
    QJsonObject obj;
    QString path = configFilePath();
    QFile existingFile(path);
    if (existingFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QJsonDocument existingDoc = QJsonDocument::fromJson(existingFile.readAll());
        if (existingDoc.isObject()) {
            obj = existingDoc.object();
        }
        existingFile.close();
    }

    obj[QStringLiteral("notasDir")] = m_notasDir;
    obj[QStringLiteral("editorFontSize")] = m_editorFontSize;
    obj[QStringLiteral("editorZoom")] = m_editorZoom;
    obj[QStringLiteral("showImagePreviews")] = m_showImagePreviews;
    obj[QStringLiteral("cyclePreviewImages")] = m_cyclePreviewImages;
    obj[QStringLiteral("blurEnabled")] = m_blurEnabled;
    obj[QStringLiteral("language")] = m_language;
    obj[QStringLiteral("spellCheckEnabled")] = m_spellCheckEnabled;
    obj[QStringLiteral("spellCheckLanguage")] = m_spellCheckLanguage;
    obj[QStringLiteral("themeMode")] = m_themeMode;
    obj[QStringLiteral("hideScrollbars")] = m_hideScrollbars;

    obj[QStringLiteral("cardsPerRow")] = m_cardsPerRow;
    obj[QStringLiteral("importMode")] = m_importMode;
    obj[QStringLiteral("externalFileOpenMode")] = m_externalFileOpenMode;
    obj[QStringLiteral("previewCloseAction")] = m_previewCloseAction;
    obj[QStringLiteral("spellcheckMode")] = m_spellcheckMode;
    obj[QStringLiteral("disabledSpellLanguages")] = m_disabledSpellLanguages;
    obj[QStringLiteral("primarySpellLanguage")] = m_primarySpellLanguage;
    obj[QStringLiteral("ignoreUppercase")] = m_ignoreUppercase;
    obj[QStringLiteral("ignoreWithDigits")] = m_ignoreWithDigits;
    obj[QStringLiteral("autoDetectParagraphLanguage")] = m_autoDetectParagraphLanguage;
    obj[QStringLiteral("panelOpacity")] = m_panelOpacity;
    obj[QStringLiteral("animationsEnabled")] = m_animationsEnabled;
    obj[QStringLiteral("fontSizeScale")] = m_fontSizeScale;
    obj[QStringLiteral("uiScale")] = m_uiScale;
    obj[QStringLiteral("customThemeName")] = m_customThemeName;
    obj[QStringLiteral("lightMode")] = m_lightMode;
    obj[QStringLiteral("syncWithQuickshell")] = m_syncWithQuickshell;
    obj[QStringLiteral("versionHistoryEnabled")] = m_versionHistoryEnabled;
    obj[QStringLiteral("versionHistoryMax")] = m_versionHistoryMax;
    obj[QStringLiteral("versionHistoryMaxMb")] = m_versionHistoryMaxMb;
    obj[QStringLiteral("persistUndo")] = m_persistUndo;
    obj[QStringLiteral("showSourceModeButton")] = m_showSourceModeButton;
    obj[QStringLiteral("windowControlsMode")] = m_windowControlsMode;

    if (isForcedNoSyncConfigured()) {
        obj[QStringLiteral("syncWithQuickshell")] = false;
    }

    QFileInfo fi(path);
    fi.dir().mkpath(QStringLiteral("."));

    QSaveFile file(path);
    if (file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
        file.commit();
    }
}

void ConfigBackend::reload() {
    load();
    emit notasDirChanged();
    emit editorFontSizeChanged();
    emit editorZoomChanged();
    emit showImagePreviewsChanged();
    emit cyclePreviewImagesChanged();
    emit blurEnabledChanged();
    emit languageChanged();
    emit spellCheckEnabledChanged();
    emit spellCheckLanguageChanged();
    emit themeModeChanged();
    emit hideScrollbarsChanged();

    emit cardsPerRowChanged();
    emit importModeChanged();
    emit externalFileOpenModeChanged();
    emit previewCloseActionChanged();
    emit spellcheckModeChanged();
    emit disabledSpellLanguagesChanged();
    emit primarySpellLanguageChanged();
    emit ignoreUppercaseChanged();
    emit ignoreWithDigitsChanged();
    emit autoDetectParagraphLanguageChanged();
    emit panelOpacityChanged();
    emit animationsEnabledChanged();
    emit fontSizeScaleChanged();
    emit uiScaleChanged();
    emit customThemeNameChanged();
    emit lightModeChanged();
}

// ═════════════════════════════════════════════════════════════════════════════
// 6. SpellBackend Implementation
// ═════════════════════════════════════════════════════════════════════════════

SpellBackend::SpellBackend(QObject *parent)
    : QObject(parent)
{
    discoverDictionaries();
    loadPersonalWords();
}

void SpellBackend::refreshDictionaries() {
    discoverDictionaries();
    loadPersonalWords();
}

QString SpellBackend::personalDicPath() const {
    return QDir::homePath() + QStringLiteral("/.config/notas/personal.dic");
}

void SpellBackend::discoverDictionaries() {
    m_availableDictionaries.clear();
    const QStringList paths = {
        QDir::homePath() + QStringLiteral("/.local/share/criperto.notes/dictionaries"),
        QDir::homePath() + QStringLiteral("/.local/share/notas/dictionaries"),
        QStringLiteral("/usr/share/hunspell"),
        QStringLiteral("/usr/share/myspell"),
        QDir::homePath() + QStringLiteral("/.local/share/hunspell")
    };

    for (const auto &p : paths) {
        QDir d(p);
        if (d.exists()) {
            const auto entries = d.entryList({QStringLiteral("*.dic")}, QDir::Files);
            for (const auto &e : entries) {
                QString lang = QFileInfo(e).baseName();
                if (!m_availableDictionaries.contains(lang)) {
                    m_availableDictionaries.append(lang);
                }
            }
        }
    }
    emit availableDictionariesChanged();
}

void SpellBackend::loadPersonalWords() {
    m_personalWords.clear();
    QString p = personalDicPath();
    QFileInfo fi(p);
    if (!fi.exists()) {
        fi.dir().mkpath(QStringLiteral("."));
        QFile initFile(p);
        if (initFile.open(QIODevice::WriteOnly | QIODevice::Text)) {
            initFile.close();
        }
    }
    QFile f(p);
    if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&f);
        while (!in.atEnd()) {
            QString w = in.readLine().trimmed();
            if (!w.isEmpty() && !m_personalWords.contains(w)) {
                m_personalWords.append(w);
            }
        }
        f.close();
    }
    emit personalWordsChanged();
}

void SpellBackend::savePersonalWords() {
    QString p = personalDicPath();
    QFileInfo fi(p);
    fi.dir().mkpath(QStringLiteral("."));

    QSaveFile f(p);
    if (f.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QTextStream out(&f);
        for (const auto &w : m_personalWords) {
            out << w << "\n";
        }
        f.commit();
    }
}

void SpellBackend::addPersonalWord(const QString &word) {
    QString clean = word.trimmed();
    if (clean.isEmpty() || m_personalWords.contains(clean)) return;
    m_personalWords.append(clean);
    savePersonalWords();
    emit personalWordsChanged();
}

void SpellBackend::removePersonalWord(const QString &word) {
    QString clean = word.trimmed();
    if (m_personalWords.removeAll(clean) > 0) {
        savePersonalWords();
        emit personalWordsChanged();
    }
}

void SpellBackend::clearPersonalWords() {
    if (!m_personalWords.isEmpty()) {
        m_personalWords.clear();
        savePersonalWords();
        emit personalWordsChanged();
    }
}

QJsonObject SpellBackend::checkWords(const QString &lang, const QStringList &words) {
    QJsonObject result;
    if (words.isEmpty()) return result;

    QString dict = lang;
    if (dict == "auto" || dict.isEmpty() || !m_availableDictionaries.contains(dict)) {
        dict = m_availableDictionaries.contains("es_AR")
            ? QStringLiteral("es_AR")
            : (m_availableDictionaries.contains("es_ES")
                ? QStringLiteral("es_ES")
                : m_availableDictionaries.value(0, QStringLiteral("es_AR")));
    }

    QString dictArg = dict;
    const QStringList searchDirs = {
        QDir::homePath() + QStringLiteral("/.local/share/criperto.notes/dictionaries"),
        QDir::homePath() + QStringLiteral("/.local/share/notas/dictionaries"),
        QStringLiteral("/usr/share/hunspell"),
        QStringLiteral("/usr/share/myspell"),
        QDir::homePath() + QStringLiteral("/.local/share/hunspell")
    };
    for (const auto &d : searchDirs) {
        QString candidate = d + QStringLiteral("/") + dict;
        if (QFile::exists(candidate + QStringLiteral(".dic")) && QFile::exists(candidate + QStringLiteral(".aff"))) {
            dictArg = candidate;
            break;
        }
    }

    QFileInfo pdFi(personalDicPath());
    pdFi.dir().mkpath(QStringLiteral("."));
    if (!pdFi.exists()) {
        QFile pf(personalDicPath());
        if (pf.open(QIODevice::WriteOnly | QIODevice::Text)) pf.close();
    }

    QProcess proc;
    proc.start("hunspell", {"-a", "-d", dictArg, "-p", personalDicPath()});
    if (!proc.waitForStarted(1000)) {
        return result;
    }

    QTextStream out(&proc);
    for (const auto &w : words) {
        if (m_personalWords.contains(w, Qt::CaseInsensitive)) {
            continue;
        }
        out << "^" << w << "\n";
    }
    out.flush();
    proc.closeWriteChannel();

    if (!proc.waitForFinished(2000)) {
        proc.kill();
    }

    QByteArray rawOut = proc.readAllStandardOutput();
    QTextStream in(rawOut);

    while (!in.atEnd()) {
        QString line = in.readLine().trimmed();
        if (line.startsWith('&')) {
            QStringList tokens = line.split(' ');
            if (tokens.size() >= 5) {
                QString word = tokens[1];
                int colonIdx = line.indexOf(':');
                QJsonArray suggArr;
                if (colonIdx != -1) {
                    QString suggs = line.mid(colonIdx + 1).trimmed();
                    const auto parts = suggs.split(',', Qt::SkipEmptyParts);
                    for (const auto &s : parts) {
                        suggArr.append(s.trimmed());
                    }
                }
                QJsonObject item;
                item["valid"] = false;
                item["suggestions"] = suggArr;
                result[word] = item;
            }
        } else if (line.startsWith('#')) {
            QStringList tokens = line.split(' ');
            if (tokens.size() >= 2) {
                QString word = tokens[1];
                QJsonObject item;
                item["valid"] = false;
                item["suggestions"] = QJsonArray();
                result[word] = item;
            }
        }
    }

    return result;
}
