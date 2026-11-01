#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QByteArray>
#include <QProcess>
#include <QSaveFile>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QDateTime>
#include <QFileSystemWatcher>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonDocument>
#include <QTimer>
#include <QtQmlIntegration/qqmlintegration.h>

// ── 1. SplitParser ───────────────────────────────────────────────────────────
class SplitParser : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString splitMarker READ splitMarker WRITE setSplitMarker NOTIFY splitMarkerChanged)

public:
    explicit SplitParser(QObject *parent = nullptr);

    QString splitMarker() const { return m_splitMarker; }
    void setSplitMarker(const QString &marker);

    void pushData(const QByteArray &data);
    void flush();

signals:
    void splitMarkerChanged();
    void read(const QString &data);

private:
    QString m_splitMarker = QStringLiteral("\n");
    QByteArray m_buffer;
};

// ── 2. Process ───────────────────────────────────────────────────────────────
class Process : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QStringList command READ command WRITE setCommand NOTIFY commandChanged)
    Q_PROPERTY(bool running READ isRunning WRITE setRunning NOTIFY runningChanged)
    Q_PROPERTY(bool stdinEnabled READ stdinEnabled WRITE setStdinEnabled NOTIFY stdinEnabledChanged)
    Q_PROPERTY(SplitParser* stdout READ stdoutParser WRITE setStdoutParser NOTIFY stdoutParserChanged)
    Q_PROPERTY(SplitParser* stderr READ stderrParser WRITE setStderrParser NOTIFY stderrParserChanged)

public:
    explicit Process(QObject *parent = nullptr);
    ~Process() override;

    QStringList command() const { return m_command; }
    void setCommand(const QStringList &cmd);

    bool isRunning() const { return m_running; }
    void setRunning(bool r);

    bool stdinEnabled() const { return m_stdinEnabled; }
    void setStdinEnabled(bool e);

    SplitParser* stdoutParser() const { return m_stdout; }
    void setStdoutParser(SplitParser *p);

    SplitParser* stderrParser() const { return m_stderr; }
    void setStderrParser(SplitParser *p);

    Q_INVOKABLE void exec(const QStringList &args = QStringList());
    Q_INVOKABLE void write(const QString &data);

signals:
    void commandChanged();
    void runningChanged();
    void stdinEnabledChanged();
    void stdoutParserChanged();
    void stderrParserChanged();
    void started();
    void exited(int exitCode);

private slots:
    void onReadyReadStdout();
    void onReadyReadStderr();
    void onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onProcessError(QProcess::ProcessError error);

private:
    void startProcess();
    void stopProcess();

    QStringList m_command;
    bool m_running = false;
    bool m_stdinEnabled = false;
    SplitParser *m_stdout = nullptr;
    SplitParser *m_stderr = nullptr;
    QProcess *m_process = nullptr;
};

// ── 3. FileView ──────────────────────────────────────────────────────────────
class FileView : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString path READ path WRITE setPath NOTIFY pathChanged)
    Q_PROPERTY(bool preload READ preload WRITE setPreload NOTIFY preloadChanged)
    Q_PROPERTY(bool watchChanges READ watchChanges WRITE setWatchChanges NOTIFY watchChangesChanged)
    Q_PROPERTY(bool atomicWrites READ atomicWrites WRITE setAtomicWrites NOTIFY atomicWritesChanged)
    Q_PROPERTY(bool printErrors READ printErrors WRITE setPrintErrors NOTIFY printErrorsChanged)
    Q_PROPERTY(bool loaded READ isLoaded NOTIFY loadedChanged)

public:
    explicit FileView(QObject *parent = nullptr);
    ~FileView() override;

    QString path() const { return m_path; }
    void setPath(const QString &p);

    bool preload() const { return m_preload; }
    void setPreload(bool v);

    bool watchChanges() const { return m_watchChanges; }
    void setWatchChanges(bool v);

    bool atomicWrites() const { return m_atomicWrites; }
    void setAtomicWrites(bool v);

    bool printErrors() const { return m_printErrors; }
    void setPrintErrors(bool v);

    bool isLoaded() const { return m_loaded; }

    Q_INVOKABLE QString text() const { return m_text; }
    Q_INVOKABLE void setText(const QString &content);
    Q_INVOKABLE void reload();
    Q_INVOKABLE void waitForJob() {}

signals:
    void pathChanged();
    void preloadChanged();
    void watchChangesChanged();
    void atomicWritesChanged();
    void printErrorsChanged();
    void loadedChanged();

    void loaded();
    void fileChanged();
    void saved();
    void saveFailed(const QString &error);
    void loadFailed(const QString &error);

private slots:
    void onFileSystemChanged(const QString &path);

private:
    void updateWatcher();
    bool readFile();
    bool writeFile(const QString &content);

    QString m_path;
    bool m_preload = true;
    bool m_watchChanges = true;
    bool m_atomicWrites = true;
    bool m_printErrors = false;
    bool m_loaded = false;
    QString m_text;
    QFileSystemWatcher *m_watcher = nullptr;
    QDateTime m_lastModified;
    bool m_isInternalSave = false;
};

// ── 4. Sys Singleton ────────────────────────────────────────────────────────
class Sys : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString clipboardText READ clipboardText WRITE setClipboardText NOTIFY clipboardTextChanged)
    Q_PROPERTY(bool hasTouchscreen READ hasTouchscreen CONSTANT)
    Q_PROPERTY(QString homeDir READ homeDir CONSTANT)
    Q_PROPERTY(QString dataShareDir READ dataShareDir CONSTANT)
    Q_PROPERTY(QString appExecutable READ appExecutable CONSTANT)

public:
    explicit Sys(QObject *parent = nullptr);

    QString clipboardText() const;
    void setClipboardText(const QString &text);

    bool hasTouchscreen() const;
    QString homeDir() const;
    QString dataShareDir() const;
    QString appExecutable() const;

    Q_INVOKABLE QString env(const QString &name, const QString &fallback = QString()) const;
    Q_INVOKABLE bool execDetached(const QStringList &args) const;
    Q_INVOKABLE bool clipboardHasImage() const;
    Q_INVOKABLE QString pasteClipboardImage(const QString &destDir, const QString &baseName, const QString &relPrefix = QStringLiteral("assets/"));
    Q_INVOKABLE QJsonObject indexNotes(const QString &notesDir) const;

signals:
    void clipboardTextChanged();

private:
    mutable int m_hasTouchscreen = -1;
};

// ── 5. ConfigBackend Singleton ──────────────────────────────────────────────
class ConfigBackend : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString notasDir READ notasDir WRITE setNotasDir NOTIFY notasDirChanged)
    Q_PROPERTY(int editorFontSize READ editorFontSize WRITE setEditorFontSize NOTIFY editorFontSizeChanged)
    Q_PROPERTY(int editorZoom READ editorZoom WRITE setEditorZoom NOTIFY editorZoomChanged)
    Q_PROPERTY(bool showImagePreviews READ showImagePreviews WRITE setShowImagePreviews NOTIFY showImagePreviewsChanged)
    Q_PROPERTY(bool cyclePreviewImages READ cyclePreviewImages WRITE setCyclePreviewImages NOTIFY cyclePreviewImagesChanged)
    Q_PROPERTY(bool blurEnabled READ blurEnabled WRITE setBlurEnabled NOTIFY blurEnabledChanged)
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY languageChanged)
    Q_PROPERTY(bool spellCheckEnabled READ spellCheckEnabled WRITE setSpellCheckEnabled NOTIFY spellCheckEnabledChanged)
    Q_PROPERTY(QString spellCheckLanguage READ spellCheckLanguage WRITE setSpellCheckLanguage NOTIFY spellCheckLanguageChanged)
    Q_PROPERTY(QString themeMode READ themeMode WRITE setThemeMode NOTIFY themeModeChanged)
    Q_PROPERTY(bool hideScrollbars READ hideScrollbars WRITE setHideScrollbars NOTIFY hideScrollbarsChanged)

public:
    explicit ConfigBackend(QObject *parent = nullptr);
    ~ConfigBackend() override;

    QString notasDir() const { return m_notasDir; }
    void setNotasDir(const QString &val);

    int editorFontSize() const { return m_editorFontSize; }
    void setEditorFontSize(int val);

    int editorZoom() const { return m_editorZoom; }
    void setEditorZoom(int val);

    bool showImagePreviews() const { return m_showImagePreviews; }
    void setShowImagePreviews(bool val);

    bool cyclePreviewImages() const { return m_cyclePreviewImages; }
    void setCyclePreviewImages(bool val);

    bool blurEnabled() const { return m_blurEnabled; }
    void setBlurEnabled(bool val);

    QString language() const { return m_language; }
    void setLanguage(const QString &val);

    bool spellCheckEnabled() const { return m_spellCheckEnabled; }
    void setSpellCheckEnabled(bool val);

    QString spellCheckLanguage() const { return m_spellCheckLanguage; }
    void setSpellCheckLanguage(const QString &val);

    QString themeMode() const { return m_themeMode; }
    void setThemeMode(const QString &val);

    bool hideScrollbars() const { return m_hideScrollbars; }
    void setHideScrollbars(bool val);

    Q_INVOKABLE void save();
    Q_INVOKABLE void reload();

signals:
    void notasDirChanged();
    void editorFontSizeChanged();
    void editorZoomChanged();
    void showImagePreviewsChanged();
    void cyclePreviewImagesChanged();
    void blurEnabledChanged();
    void languageChanged();
    void spellCheckEnabledChanged();
    void spellCheckLanguageChanged();
    void themeModeChanged();
    void hideScrollbarsChanged();

private:
    void load();
    void scheduleSave();
    QString configFilePath() const;
    QString legacyConfigFilePath() const;

    QString m_notasDir;
    int m_editorFontSize = 16;
    int m_editorZoom = 100;
    bool m_showImagePreviews = true;
    bool m_cyclePreviewImages = true;
    bool m_blurEnabled = true;
    QString m_language = QStringLiteral("auto");
    bool m_spellCheckEnabled = true;
    QString m_spellCheckLanguage = QStringLiteral("auto");
    QString m_themeMode = QStringLiteral("system");
    bool m_hideScrollbars = false;

    QTimer *m_saveTimer = nullptr;
};

// ── 6. SpellBackend Singleton ───────────────────────────────────────────────
class SpellBackend : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QStringList availableDictionaries READ availableDictionaries NOTIFY availableDictionariesChanged)

public:
    explicit SpellBackend(QObject *parent = nullptr);

    QStringList availableDictionaries() const { return m_availableDictionaries; }

    Q_INVOKABLE QJsonObject checkWords(const QString &lang, const QStringList &words);
    Q_INVOKABLE void addPersonalWord(const QString &word);
    Q_INVOKABLE QStringList personalWords() const { return m_personalWords; }

signals:
    void availableDictionariesChanged();
    void personalWordsChanged();

private:
    void discoverDictionaries();
    void loadPersonalWords();
    void savePersonalWords();
    QString personalDicPath() const;

    QStringList m_availableDictionaries;
    QStringList m_personalWords;
};
