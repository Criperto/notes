#include "native_bridge.h"

#include <QCoreApplication>
#include <QGuiApplication>
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
}

Sys::~Sys() {
    if (m_ipcServer) {
        m_ipcServer->close();
        delete m_ipcServer;
        m_ipcServer = nullptr;
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
    QString sockPath = runtimeDir + QStringLiteral("/notas.sock");

    QFile::remove(sockPath);

    m_ipcServer = new QLocalServer(this);
    connect(m_ipcServer, &QLocalServer::newConnection, this, &Sys::onNewIpcConnection);

    if (!m_ipcServer->listen(sockPath)) {
        // Fallback al nombre abstracto o por defecto
        m_ipcServer->listen(QStringLiteral("notas"));
    }
}

void Sys::onNewIpcConnection() {
    while (m_ipcServer && m_ipcServer->hasPendingConnections()) {
        QLocalSocket *client = m_ipcServer->nextPendingConnection();
        connect(client, &QLocalSocket::readyRead, this, [this, client]() {
            QByteArray raw = client->readAll().trimmed();
            if (!raw.isEmpty()) {
                QJsonDocument doc = QJsonDocument::fromJson(raw);
                if (doc.isObject()) {
                    QJsonObject obj = doc.object();
                    QString action = obj[QStringLiteral("action")].toString();
                    QString target = obj[QStringLiteral("target")].toString();
                    emit ipcCommandReceived(action, target);
                }
            }
            client->deleteLater();
        });
    }
}

QString Sys::clipboardText() const {
    if (auto *cb = QGuiApplication::clipboard()) {
        return cb->text();
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

QString Sys::dataShareDir() const {
    QString devDir = QDir::currentPath();
    if (QFile::exists(devDir + QStringLiteral("/qml/Main.qml"))) {
        return devDir;
    }
    QString userShare = QDir::homePath() + QStringLiteral("/.local/share/notas");
    if (QFile::exists(userShare)) {
        return userShare;
    }
    return QStringLiteral("/usr/share/notas");
}

QString Sys::appExecutable() const {
    return QCoreApplication::applicationFilePath();
}

QString Sys::env(const QString &name, const QString &fallback) const {
    QByteArray val = qgetenv(name.toUtf8().constData());
    if (val.isEmpty()) return fallback;
    return QString::fromUtf8(val);
}

bool Sys::execDetached(const QStringList &args) const {
    if (args.isEmpty()) return false;
    return QProcess::startDetached(args.first(), args.mid(1));
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
    m_notasDir = QDir::homePath() + QStringLiteral("/Documentos/notes");
    if (!QFile::exists(QDir::homePath() + QStringLiteral("/.cache/wal/colors.json"))) {
        m_themeMode = QStringLiteral("qt");
    }

    m_saveTimer = new QTimer(this);
    m_saveTimer->setSingleShot(true);
    m_saveTimer->setInterval(250);
    connect(m_saveTimer, &QTimer::timeout, this, &ConfigBackend::save);

    load();
}

ConfigBackend::~ConfigBackend() {
    if (m_saveTimer && m_saveTimer->isActive()) {
        m_saveTimer->stop();
        save();
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

void ConfigBackend::setPanelOpacity(int val) {
    int clamped = qBound(50, val, 100);
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

void ConfigBackend::load() {
    const bool hasPywal = QFile::exists(QDir::homePath() + QStringLiteral("/.cache/wal/colors.json"));
    QString path = configFilePath();
    if (QFile::exists(path)) {
        QFile file(path);
        if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
            if (doc.isObject()) {
                QJsonObject obj = doc.object();
                if (obj.contains("notasDir")) m_notasDir = obj["notasDir"].toString();
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
                if (obj.contains("importMode")) m_importMode = obj["importMode"].toString("copy");
                if (obj.contains("spellcheckMode")) m_spellcheckMode = obj["spellcheckMode"].toString("auto");
                if (obj.contains("disabledSpellLanguages")) m_disabledSpellLanguages = obj["disabledSpellLanguages"].toString();
                if (obj.contains("primarySpellLanguage")) m_primarySpellLanguage = obj["primarySpellLanguage"].toString();
                if (obj.contains("ignoreUppercase")) m_ignoreUppercase = obj["ignoreUppercase"].toBool(true);
                if (obj.contains("ignoreWithDigits")) m_ignoreWithDigits = obj["ignoreWithDigits"].toBool(true);
                if (obj.contains("panelOpacity")) m_panelOpacity = qBound(50, obj["panelOpacity"].toInt(94), 100);
                if (obj.contains("animationsEnabled")) m_animationsEnabled = obj["animationsEnabled"].toBool(true);
                if (obj.contains("fontSizeScale")) m_fontSizeScale = obj["fontSizeScale"].toDouble(1.0);
                if (obj.contains("customThemeName")) m_customThemeName = obj["customThemeName"].toString("amarillo");
                if (obj.contains("lightMode")) m_lightMode = obj["lightMode"].toBool(false);

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
    obj[QStringLiteral("spellcheckMode")] = m_spellcheckMode;
    obj[QStringLiteral("disabledSpellLanguages")] = m_disabledSpellLanguages;
    obj[QStringLiteral("primarySpellLanguage")] = m_primarySpellLanguage;
    obj[QStringLiteral("ignoreUppercase")] = m_ignoreUppercase;
    obj[QStringLiteral("ignoreWithDigits")] = m_ignoreWithDigits;
    obj[QStringLiteral("panelOpacity")] = m_panelOpacity;
    obj[QStringLiteral("animationsEnabled")] = m_animationsEnabled;
    obj[QStringLiteral("fontSizeScale")] = m_fontSizeScale;
    obj[QStringLiteral("customThemeName")] = m_customThemeName;
    obj[QStringLiteral("lightMode")] = m_lightMode;

    QString path = configFilePath();
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
    emit spellcheckModeChanged();
    emit disabledSpellLanguagesChanged();
    emit primarySpellLanguageChanged();
    emit ignoreUppercaseChanged();
    emit ignoreWithDigitsChanged();
    emit panelOpacityChanged();
    emit animationsEnabledChanged();
    emit fontSizeScaleChanged();
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
