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
#include <iostream>

// ═════════════════════════════════════════════════════════════════════════════
// 1. SplitParser Implementation
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

    // D4: Si splitMarker está vacío, emitir cada chunk directamente
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
    if (m_watchChanges && !m_path.isEmpty() && QFile::exists(m_path)) {
        m_watcher->addPath(m_path);
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

void FileView::onFileSystemChanged(const QString &path) {
    if (m_isInternalSave) return;
    if (path == m_path) {
        QFileInfo fi(m_path);
        if (fi.exists() && fi.lastModified() > m_lastModified) {
            readFile();
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
    if (QGuiApplication::clipboard()) {
        connect(QGuiApplication::clipboard(), &QClipboard::dataChanged, this, &Sys::clipboardTextChanged);
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

        // Omitir ocultos (.git, .trash, etc.)
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

            // Parsear frontmatter rápido
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
                // Si título sigue siendo default, buscar primer # Heading
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

void ConfigBackend::load() {
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
                if (obj.contains("themeMode")) m_themeMode = obj["themeMode"].toString("system");
                if (obj.contains("hideScrollbars")) m_hideScrollbars = obj["hideScrollbars"].toBool(false);
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
            save(); // Persistir inmediatamente en el nuevo formato JSON
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

QString SpellBackend::personalDicPath() const {
    return QDir::homePath() + QStringLiteral("/.config/notas/personal.dic");
}

void SpellBackend::discoverDictionaries() {
    m_availableDictionaries.clear();
    const QStringList paths = {
        QStringLiteral("/usr/share/hunspell"),
        QStringLiteral("/usr/share/myspell")
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
    QFile f(personalDicPath());
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

QJsonObject SpellBackend::checkWords(const QString &lang, const QStringList &words) {
    QJsonObject result;
    if (words.isEmpty()) return result;

    QString dict = lang;
    if (dict == "auto" || dict.isEmpty()) {
        dict = m_availableDictionaries.contains("es_ES") ? "es_ES" : (m_availableDictionaries.value(0, "es_ES"));
    }

    QProcess proc;
    proc.start("hunspell", {"-a", "-d", dict});
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

    // Parsear salida hunspell -a:
    // '*' o '+' -> correcto
    // '& <word> <count> <offset>: <sugg1>, <sugg2>' -> error con sugerencias
    // '# <word> <offset>' -> error sin sugerencias
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
