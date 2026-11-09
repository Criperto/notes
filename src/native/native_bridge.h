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
#include <QPointF>
#include <QLocalServer>
#include <QLocalSocket>
#include <QtQmlIntegration/qqmlintegration.h>

// ── 1. SplitParser & StdioCollector ──────────────────────────────────────────
class SplitParser : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString splitMarker READ splitMarker WRITE setSplitMarker NOTIFY splitMarkerChanged)

public:
    explicit SplitParser(QObject *parent = nullptr);

    QString splitMarker() const { return m_splitMarker; }
    void setSplitMarker(const QString &marker);

    virtual void pushData(const QByteArray &data);
    virtual void flush();
    virtual void reset();

signals:
    void splitMarkerChanged();
    void read(const QString &data);

private:
    QString m_splitMarker = QStringLiteral("\n");
    QByteArray m_buffer;
};

class StdioCollector : public SplitParser {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(QString text READ text NOTIFY textChanged)

public:
    explicit StdioCollector(QObject *parent = nullptr);

    QString text() const { return m_text; }

    void pushData(const QByteArray &data) override;
    void flush() override;
    void reset() override;

signals:
    void textChanged();
    void streamFinished();

private:
    QByteArray m_collected;
    QString m_text;
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
    Q_PROPERTY(QString homePath READ homeDir CONSTANT)
    Q_PROPERTY(QString documentsDir READ documentsDir CONSTANT)
    Q_PROPERTY(QString dataShareDir READ dataShareDir CONSTANT)
    Q_PROPERTY(QString appExecutable READ appExecutable CONSTANT)
    Q_PROPERTY(QString initialAction READ initialAction CONSTANT)
    Q_PROPERTY(QString initialTarget READ initialTarget CONSTANT)
    Q_PROPERTY(qreal lastMouseX READ lastMouseX NOTIFY lastMousePosChanged)
    Q_PROPERTY(qreal lastMouseY READ lastMouseY NOTIFY lastMousePosChanged)
    Q_PROPERTY(QJsonObject qtColors READ qtColors NOTIFY qtColorsChanged)
    Q_PROPERTY(bool hasQuickshellConfig READ hasQuickshellConfig NOTIFY quickshellConfigChanged)
    Q_PROPERTY(bool wmNeedsWindowControls READ wmNeedsWindowControls CONSTANT)
    Q_PROPERTY(bool windowControlsOnLeft READ windowControlsOnLeft CONSTANT)
    Q_PROPERTY(QString systemFontFamily READ systemFontFamily NOTIFY systemFontChanged)
    Q_PROPERTY(QString systemFontFamilyDisplay READ systemFontFamilyDisplay NOTIFY systemFontChanged)
    Q_PROPERTY(QString systemFontFamilyRounded READ systemFontFamilyRounded NOTIFY systemFontChanged)
    Q_PROPERTY(QString systemMonospaceFontFamily READ systemMonospaceFontFamily NOTIFY systemFontChanged)

public:
    explicit Sys(QObject *parent = nullptr);
    ~Sys() override;

    QString clipboardText() const;
    void setClipboardText(const QString &text);

    bool hasTouchscreen() const;
    QString homeDir() const;
    QString documentsDir() const;
    QString dataShareDir() const;
    QString appExecutable() const;
    QString initialAction() const { return m_initialAction; }
    QString initialTarget() const { return m_initialTarget; }

    qreal lastMouseX() const { return m_lastMousePos.x(); }
    qreal lastMouseY() const { return m_lastMousePos.y(); }
    QJsonObject qtColors() const { return m_qtColors; }
    bool hasQuickshellConfig() const;
    bool wmNeedsWindowControls() const;
    bool windowControlsOnLeft() const;
    QString systemFontFamily() const;
    QString systemFontFamilyDisplay() const;
    QString systemFontFamilyRounded() const;
    QString systemMonospaceFontFamily() const;
    void printStartupDiagnostics() const;

    bool eventFilter(QObject *watched, QEvent *event) override;

    Q_INVOKABLE QString env(const QString &name, const QString &fallback = QString()) const;
    Q_INVOKABLE bool execDetached(const QStringList &args) const;
    Q_INVOKABLE bool clipboardHasImage() const;
    Q_INVOKABLE QString pasteClipboardImage(const QString &destDir, const QString &baseName, const QString &relPrefix = QStringLiteral("assets/"));
    Q_INVOKABLE QJsonObject indexNotes(const QString &notesDir) const;
    Q_INVOKABLE QString loadHistoryUndo(const QString &notePath) const;
    Q_INVOKABLE bool saveHistoryUndo(const QString &notePath, const QString &jsonData) const;
    Q_INVOKABLE QString renderLatexSvg(const QString &latex, bool display = false, const QString &colorHex = QString(), double ptSize = 12.0) const;
    Q_INVOKABLE QJsonArray diffLines(const QString &textA, const QString &textB) const;
    Q_INVOKABLE QJsonArray diffWords(const QString &lineA, const QString &lineB) const;
    Q_INVOKABLE QString detectLanguage(const QString &text) const;
    Q_INVOKABLE QJsonObject readQtColors() const;
    Q_INVOKABLE void refreshQtColors();
    Q_INVOKABLE void updateInstanceStatus(const QString &notePath, bool isEditing);
    Q_INVOKABLE bool isNoteBeingEditedElsewhere(const QString &notePath) const;
    Q_INVOKABLE void claimEditLock(const QString &notePath);
    Q_INVOKABLE void broadcastNoteSaved(const QString &notePath);
    Q_INVOKABLE void broadcastNoteDeleted(const QString &notePath);
    Q_INVOKABLE void startSystemMove(QObject *windowObj);

signals:
    void clipboardTextChanged();
    void lastMousePosChanged();
    void qtColorsChanged();
    void systemFontChanged();
    void quickshellConfigChanged();
    void ipcCommandReceived(const QString &action, const QString &target);
    void remoteEditLockClaimed(const QString &notePath, qint64 newOwnerPid);
    void remoteNoteSaved(const QString &notePath);
    void remoteNoteDeleted(const QString &notePath);

private slots:
    void onNewIpcConnection();
    void onQtThemeFileChanged();

private:
    void startIpcServer();
    void setupQtThemeWatcher();

    mutable int m_hasTouchscreen = -1;
    QPointF m_lastMousePos = QPointF(100, 100);
    QString m_initialAction;
    QString m_initialTarget;
    QLocalServer *m_ipcServer = nullptr;
    QFileSystemWatcher *m_qtThemeWatcher = nullptr;
    QJsonObject m_qtColors;
    QString m_currentInstanceSockPath;
    QString m_currentInstanceJsonPath;
};

// ── 5. ConfigBackend Singleton ──────────────────────────────────────────────
class ConfigBackend : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString notasDir READ notasDir WRITE setNotasDir NOTIFY notasDirChanged)
    Q_PROPERTY(QString resolvedNotasDir READ resolvedNotasDir NOTIFY notasDirChanged)
    Q_PROPERTY(QString windowControlsMode READ windowControlsMode WRITE setWindowControlsMode NOTIFY windowControlsModeChanged)
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

    Q_PROPERTY(int cardsPerRow READ cardsPerRow WRITE setCardsPerRow NOTIFY cardsPerRowChanged)
    Q_PROPERTY(QString importMode READ importMode WRITE setImportMode NOTIFY importModeChanged)
    Q_PROPERTY(QString externalFileOpenMode READ externalFileOpenMode WRITE setExternalFileOpenMode NOTIFY externalFileOpenModeChanged)
    Q_PROPERTY(QString previewCloseAction READ previewCloseAction WRITE setPreviewCloseAction NOTIFY previewCloseActionChanged)
    Q_PROPERTY(QString spellcheckMode READ spellcheckMode WRITE setSpellcheckMode NOTIFY spellcheckModeChanged)
    Q_PROPERTY(QString disabledSpellLanguages READ disabledSpellLanguages WRITE setDisabledSpellLanguages NOTIFY disabledSpellLanguagesChanged)
    Q_PROPERTY(QString primarySpellLanguage READ primarySpellLanguage WRITE setPrimarySpellLanguage NOTIFY primarySpellLanguageChanged)
    Q_PROPERTY(bool ignoreUppercase READ ignoreUppercase WRITE setIgnoreUppercase NOTIFY ignoreUppercaseChanged)
    Q_PROPERTY(bool ignoreWithDigits READ ignoreWithDigits WRITE setIgnoreWithDigits NOTIFY ignoreWithDigitsChanged)
    Q_PROPERTY(bool autoDetectParagraphLanguage READ autoDetectParagraphLanguage WRITE setAutoDetectParagraphLanguage NOTIFY autoDetectParagraphLanguageChanged)
    Q_PROPERTY(int panelOpacity READ panelOpacity WRITE setPanelOpacity NOTIFY panelOpacityChanged)
    Q_PROPERTY(bool animationsEnabled READ animationsEnabled WRITE setAnimationsEnabled NOTIFY animationsEnabledChanged)
    Q_PROPERTY(double fontSizeScale READ fontSizeScale WRITE setFontSizeScale NOTIFY fontSizeScaleChanged)
    Q_PROPERTY(double uiScale READ uiScale WRITE setUiScale NOTIFY uiScaleChanged)
    Q_PROPERTY(QString customThemeName READ customThemeName WRITE setCustomThemeName NOTIFY customThemeNameChanged)
    Q_PROPERTY(bool lightMode READ lightMode WRITE setLightMode NOTIFY lightModeChanged)
    Q_PROPERTY(bool hasQuickshellConfig READ hasQuickshellConfig NOTIFY hasQuickshellConfigChanged)
    Q_PROPERTY(bool syncWithQuickshell READ syncWithQuickshell WRITE setSyncWithQuickshell NOTIFY syncWithQuickshellChanged)
    Q_PROPERTY(bool versionHistoryEnabled READ versionHistoryEnabled WRITE setVersionHistoryEnabled NOTIFY versionHistoryEnabledChanged)
    Q_PROPERTY(int versionHistoryMax READ versionHistoryMax WRITE setVersionHistoryMax NOTIFY versionHistoryMaxChanged)
    Q_PROPERTY(int versionHistoryMaxMb READ versionHistoryMaxMb WRITE setVersionHistoryMaxMb NOTIFY versionHistoryMaxMbChanged)
    Q_PROPERTY(bool persistUndo READ persistUndo WRITE setPersistUndo NOTIFY persistUndoChanged)
    Q_PROPERTY(bool showSourceModeButton READ showSourceModeButton WRITE setShowSourceModeButton NOTIFY showSourceModeButtonChanged)

public:
    explicit ConfigBackend(QObject *parent = nullptr);
    ~ConfigBackend() override;

    bool hasQuickshellConfig() const;
    bool syncWithQuickshell() const { return m_syncWithQuickshell; }
    void setSyncWithQuickshell(bool val);

    QString notasDir() const { return m_notasDir; }
    void setNotasDir(const QString &val);
    QString resolvedNotasDir() const;

    QString windowControlsMode() const;
    void setWindowControlsMode(const QString &val);

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

    int cardsPerRow() const { return m_cardsPerRow; }
    void setCardsPerRow(int val);

    QString importMode() const { return m_importMode; }
    void setImportMode(const QString &val);

    QString externalFileOpenMode() const { return m_externalFileOpenMode; }
    void setExternalFileOpenMode(const QString &val);

    QString previewCloseAction() const { return m_previewCloseAction; }
    void setPreviewCloseAction(const QString &val);

    QString spellcheckMode() const { return m_spellcheckMode; }
    void setSpellcheckMode(const QString &val);

    QString disabledSpellLanguages() const { return m_disabledSpellLanguages; }
    void setDisabledSpellLanguages(const QString &val);

    QString primarySpellLanguage() const { return m_primarySpellLanguage; }
    void setPrimarySpellLanguage(const QString &val);

    bool ignoreUppercase() const { return m_ignoreUppercase; }
    void setIgnoreUppercase(bool val);

    bool ignoreWithDigits() const { return m_ignoreWithDigits; }
    void setIgnoreWithDigits(bool val);

    bool autoDetectParagraphLanguage() const { return m_autoDetectParagraphLanguage; }
    void setAutoDetectParagraphLanguage(bool val);

    int panelOpacity() const { return m_panelOpacity; }
    void setPanelOpacity(int val);

    bool animationsEnabled() const { return m_animationsEnabled; }
    void setAnimationsEnabled(bool val);

    double fontSizeScale() const { return m_fontSizeScale; }
    void setFontSizeScale(double val);

    double uiScale() const { return m_uiScale; }
    void setUiScale(double val);

    QString customThemeName() const { return m_customThemeName; }
    void setCustomThemeName(const QString &val);

    bool lightMode() const { return m_lightMode; }
    void setLightMode(bool val);

    bool versionHistoryEnabled() const { return m_versionHistoryEnabled; }
    void setVersionHistoryEnabled(bool val);

    int versionHistoryMax() const { return m_versionHistoryMax; }
    void setVersionHistoryMax(int val);

    int versionHistoryMaxMb() const { return m_versionHistoryMaxMb; }
    void setVersionHistoryMaxMb(int val);

    bool persistUndo() const { return m_persistUndo; }
    void setPersistUndo(bool val);

    bool showSourceModeButton() const { return m_showSourceModeButton; }
    void setShowSourceModeButton(bool val);

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

    void cardsPerRowChanged();
    void importModeChanged();
    void externalFileOpenModeChanged();
    void previewCloseActionChanged();
    void spellcheckModeChanged();
    void disabledSpellLanguagesChanged();
    void primarySpellLanguageChanged();
    void ignoreUppercaseChanged();
    void ignoreWithDigitsChanged();
    void autoDetectParagraphLanguageChanged();
    void panelOpacityChanged();
    void animationsEnabledChanged();
    void fontSizeScaleChanged();
    void uiScaleChanged();
    void customThemeNameChanged();
    void lightModeChanged();
    void hasQuickshellConfigChanged();
    void syncWithQuickshellChanged();
    void versionHistoryEnabledChanged();
    void versionHistoryMaxChanged();
    void versionHistoryMaxMbChanged();
    void persistUndoChanged();
    void showSourceModeButtonChanged();
    void windowControlsModeChanged();

private:
    void load();
    void scheduleSave();
    void loadQuickshellConfig();
    void setupQuickshellWatcher();
    QString configFilePath() const;
    QString legacyConfigFilePath() const;

    QString m_notasDir;
    QString m_windowControlsMode = QStringLiteral("auto");
    int m_editorFontSize = 16;
    int m_editorZoom = 100;
    bool m_showImagePreviews = true;
    bool m_cyclePreviewImages = true;
    bool m_blurEnabled = true;
    QString m_language = QStringLiteral("auto");
    bool m_spellCheckEnabled = true;
    QString m_spellCheckLanguage = QStringLiteral("auto");
    QString m_themeMode = QStringLiteral("pywal");
    bool m_hideScrollbars = false;
    bool m_syncWithQuickshell = true;

    int m_cardsPerRow = 3;
    QString m_importMode = QStringLiteral("move");
    QString m_externalFileOpenMode = QStringLiteral("preview");
    QString m_previewCloseAction = QStringLiteral("home");
    QString m_spellcheckMode = QStringLiteral("auto");
    QString m_disabledSpellLanguages;
    QString m_primarySpellLanguage;
    bool m_ignoreUppercase = true;
    bool m_ignoreWithDigits = true;
    bool m_autoDetectParagraphLanguage = true;
    int m_panelOpacity = 94;
    bool m_animationsEnabled = true;
    double m_fontSizeScale = 1.0;
    double m_uiScale = 1.0;
    QString m_customThemeName = QStringLiteral("amarillo");
    bool m_lightMode = false;
    bool m_versionHistoryEnabled = true;
    int m_versionHistoryMax = 50;
    int m_versionHistoryMaxMb = 5;
    bool m_persistUndo = true;
    bool m_showSourceModeButton = false;

    QTimer *m_saveTimer = nullptr;
    QFileSystemWatcher *m_qsWatcher = nullptr;
};

// ── 6. SpellBackend Singleton ───────────────────────────────────────────────
class SpellBackend : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QStringList availableDictionaries READ availableDictionaries NOTIFY availableDictionariesChanged)
    Q_PROPERTY(QStringList personalWords READ personalWords NOTIFY personalWordsChanged)

public:
    explicit SpellBackend(QObject *parent = nullptr);

    QStringList availableDictionaries() const { return m_availableDictionaries; }
    QStringList personalWords() const { return m_personalWords; }

    Q_INVOKABLE QJsonObject checkWords(const QString &lang, const QStringList &words);
    Q_INVOKABLE void addPersonalWord(const QString &word);
    Q_INVOKABLE void removePersonalWord(const QString &word);
    Q_INVOKABLE void clearPersonalWords();
    Q_INVOKABLE void refreshDictionaries();

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
