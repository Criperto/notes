// NotesContent.qml — Vista principal de la aplicación de notas
import "."
import Notas
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Controls
import "PreviewLogic.js" as PreviewLogic
import "ImportLogic.js" as ImportLogic
import "SortLogic.js" as SortLogic

Item {
    id: root

    signal closeRequested
    signal openSettingsRequested(var originRect, string initialTab)
    property bool isSettingsOpen: false

    function getSettingsButtonRect() {
        if (!settingsBtn) return null;
        try {
            var origin = settingsBtn.mapToItem(null, 0, 0);
            return Qt.rect(origin.x, origin.y, settingsBtn.width, settingsBtn.height);
        } catch (e) {
            return null;
        }
    }

    property bool _morphTransitioning: false
    property string activeMorphSlug: ""
    property var morphingNoteData: null
    property bool isCardMorph: false
    property var _cardRegistry: ({})
    property alias editorModal: editorModal
    property alias morphContainer: morphContainer
    property alias undoToast: undoToast
    property string keyboardSelectedSlug: ""
    property bool keyboardNavActive: false
    property string initialAction: ""
    property string initialTarget: ""
    property bool _initialActionHandled: false
    property bool launchedForExternal: (initialAction === "previewFile" || initialAction === "openPath" || initialAction === "preview" || initialAction === "edit" || (initialAction === "open" && initialTarget !== ""))
    property bool isReadyToShow: (initialAction === "" || initialAction === "raise" || initialAction === "toggle" || (initialAction === "open" && initialTarget === ""))
    property bool _previewCloseAnimActive: false
    property real _previewCloseDy: 0
    property real _previewCloseScale: 0.35

    Timer {
        id: readyToShowFallbackTimer
        interval: 600
        repeat: false
        running: !root.isReadyToShow
        onTriggered: root.isReadyToShow = true
    }

    function showUndoToast(key, noteData) {
        if (key) NotesService.queueDelete(key, noteData);
    }

    function commitUndoToast() {
        NotesService.commitPendingDeletions();
    }

    function requestCardDelete(key, noteData) {
        if (!key) return;
        NotesService.queueDelete(key, noteData);
    }

    // Estado del menú/modal de importación y dependencias
    property string importCardState: "hidden" // "hidden" | "drop_hint" | "docx_confirm" | "docx_converting" | "docx_missing_deps" | "deps_installing"
    property var pendingDocxItems: []
    property string pendingDocxName: ""
    property bool startupDepsDialogVisible: false

    // F18: cierre por borrado (hacia el toast, sin relayout)
    readonly property int deleteAnimMs: 320
    property bool _deleteAnimActive: false
    property string _delKey: ""
    property var _delNote: null
    property real _delScale: 0.3
    property real _delDy: 0

    readonly property color cardBaseColor: Qt.hsva(Theme.surface.hsvHue,
                                                  Math.min(1, Theme.surface.hsvSaturation),
                                                  Math.min(1, Theme.surface.hsvValue + 0.03),
                                                  0.55)

    readonly property var activeNotesList: (root.undoToast && root.undoToast.pendingSlug !== "")
        ? NotesService.filteredNotes.filter(n => (n.key || n.slug || n.id) !== root.undoToast.pendingSlug)
        : NotesService.filteredNotes
    readonly property var pinnedNotesList: activeNotesList.filter(n => !!n.pinned)
    readonly property var otherNotesList: activeNotesList.filter(n => !n.pinned)

    readonly property var pinnedColumnsData: PreviewLogic.distributeToColumns(root.pinnedNotesList, notesScroll ? notesScroll.cols : 3)
    readonly property var otherColumnsData: PreviewLogic.distributeToColumns(root.otherNotesList, notesScroll ? notesScroll.cols : 3)

    // F26 (FLIP): reacomodo con slide suave. First en notesAboutToChange (antes de
    // reasignar), Last tras asentar el layout (flipSettleTimer), Invert+Play por tarjeta.
    property var _flipFirst: ({})
    property bool _flipArmed: false
    property int _flipCols: -1
    readonly property int _flipMaxCards: 40
    readonly property real _flipMargin: 200

    Timer {
        id: flipSettleTimer
        interval: 16
        repeat: false
        onTriggered: root._flipPlay()
    }

    // First: foto de posiciones visibles en coords. del contenido del scroll.
    // (mapToItem incluye el Translate vigente → re-entradas parten de lo visual.)
    function _flipSnapshot() {
        root._flipFirst = ({});
        root._flipArmed = false;
        if (!(Theme.animationsEnabled && !GamemodeService.gamemodeActive)) return;
        if (!notesScroll || !notesScroll.contentItem) return;
        if (root._morphTransitioning || morphContainer.isVisible || morphContainer.isExpanded) return;
        if (root._deleteAnimActive) return;
        if (notesScroll.moving || notesScroll.flicking) return;
        if ((NotesService.searchQuery || "").trim() !== "" || (NotesService.activeTagFilter || "") !== "") return;
        var snap = {};
        for (var k in root._cardRegistry) {
            var card = root._cardRegistry[k];
            if (!card) continue;
            try {
                var p = card.mapToItem(notesScroll.contentItem, 0, 0);
                snap[k] = { x: p.x, y: p.y };
            } catch (e) {}
        }
        root._flipFirst = snap;
        root._flipCols = notesScroll.cols;
        root._flipArmed = true;
    }

    // Last + Invert + Play.
    function _flipPlay() {
        if (!root._flipArmed) return;
        root._flipArmed = false;
        var first = root._flipFirst;
        root._flipFirst = ({});
        if (!(Theme.animationsEnabled && !GamemodeService.gamemodeActive)) return;
        if (!notesScroll || !notesScroll.contentItem) return;
        if (root._morphTransitioning || morphContainer.isVisible || morphContainer.isExpanded) return;
        if (root._flipCols !== -1 && notesScroll.cols !== root._flipCols) return; // resize: salto directo
        if ((NotesService.searchQuery || "").trim() !== "" || (NotesService.activeTagFilter || "") !== "") return;
        var last = {};
        for (var k in root._cardRegistry) {
            var card = root._cardRegistry[k];
            if (!card) continue;
            try {
                var p = card.mapToItem(notesScroll.contentItem, 0, 0);
                last[k] = { x: p.x, y: p.y };
            } catch (e) {}
        }
        var res = PreviewLogic.computeSlideDeltas(first, last);
        var moved = res.moved || [];
        if (moved.length === 0) return;
        // Solo visibles (+ margen); las de fuera saltan directo.
        var viewY = notesScroll.contentY;
        var viewH = notesScroll.height;
        var inScope = [];
        for (var i = 0; i < moved.length; i++) {
            var c2 = root._cardRegistry[moved[i].key];
            if (!c2 || typeof c2.slideFrom !== "function") continue;
            var ny = (last[moved[i].key] || {}).y;
            if (ny === undefined) continue;
            var ch = c2.height || 0;
            if (ny + ch < viewY - root._flipMargin || ny > viewY + viewH + root._flipMargin) {
                if (typeof c2.slideCancel === "function") c2.slideCancel();
                continue;
            }
            moved[i].dist = Math.abs(moved[i].dx) + Math.abs(moved[i].dy);
            inScope.push(moved[i]);
        }
        if (inScope.length === 0) return;
        // Tope: las que más se mueven primero.
        inScope.sort(function(a, b) { return b.dist - a.dist; });
        if (inScope.length > root._flipMaxCards) inScope = inScope.slice(0, root._flipMaxCards);
        var topKey = inScope[0].key;
        // Cascada por columna: dentro de cada columna (por x nueva) se ordena por y
        // nueva; la de arriba arranca primero y cada una de abajo espera 60ms más.
        var cols = {};
        for (var m = 0; m < inScope.length; m++) {
            var nl2 = last[inScope[m].key];
            var ck = Math.round((nl2 ? nl2.x : 0) / 10);
            if (!cols[ck]) cols[ck] = [];
            cols[ck].push(inScope[m]);
        }
        for (var ckey in cols) {
            cols[ckey].sort(function(a, b) { return last[a.key].y - last[b.key].y; });
            for (var r = 0; r < cols[ckey].length; r++) cols[ckey][r].delay = Math.min(r, 6) * 60;
        }
        for (var j = 0; j < inScope.length; j++) {
            var cc = root._cardRegistry[inScope[j].key];
            if (cc && typeof cc.slideFrom === "function") {
                cc.slideFrom(inScope[j].dx, inScope[j].dy, inScope[j].key === topKey, inScope[j].delay || 0);
            }
        }
    }
    function _ensureCardVisible(card) {
        if (!card || !notesScroll) return;
        try {
            if (!card.parent || typeof card.mapToItem !== "function") return;
            var mapped = card.mapToItem(notesScroll.contentItem, 0, 0);
            var cardY = mapped.y;
            var cardH = card.height;
            var viewY = notesScroll.contentY;
            var viewH = notesScroll.height;
            var margin = 20;

            if (cardY - margin < viewY) {
                notesScroll.contentY = Math.max(0, cardY - margin);
            } else if (cardY + cardH + margin > viewY + viewH) {
                notesScroll.contentY = Math.max(0, cardY + cardH + margin - viewH);
            }
        } catch (e) {}
    }

    function _syncColModel(lm, items) {
        if (!lm) return;
        var list = items || [];
        var newSlugs = {};
        for (var i = 0; i < list.length; i++) {
            var s = list[i] ? (list[i].key || list[i].slug || list[i].id) : "";
            if (s) newSlugs[s] = true;
        }

        // 1. Quitar elementos obsoletos
        for (var j = lm.count - 1; j >= 0; j--) {
            var cur = lm.get(j);
            var cs = cur ? (cur.key || "") : "";
            if (!cs || !newSlugs[cs]) {
                lm.remove(j);
            }
        }

        // 2. Insertar o mover
        for (var k = 0; k < list.length; k++) {
            var it = list[k];
            var islug = it ? (it.key || it.slug || it.id) : "";
            if (!islug) continue;

            var found = -1;
            for (var m = 0; m < lm.count; m++) {
                var ex = lm.get(m);
                if (ex && ex.key === islug) {
                    found = m;
                    break;
                }
            }

            if (found === -1) {
                lm.insert(k, { key: islug });
            } else if (found !== k && k < lm.count) {
                lm.move(found, k, 1);
            }
        }
    }

    function _moveSpatialSelection(dir) {
        var list = root.activeNotesList;
        if (!list || list.length === 0) return;

        root.keyboardNavActive = true;
        var curSlug = root.keyboardSelectedSlug;
        var curCard = curSlug ? root._cardRegistry[curSlug] : null;

        var curX = 0;
        var curY = 0;
        var validCur = false;
        if (curCard) {
            try {
                if (curCard.parent && typeof curCard.mapToItem === "function") {
                    var curPos = curCard.mapToItem(notesScroll.contentItem, curCard.width / 2, curCard.height / 2);
                    curX = curPos.x;
                    curY = curPos.y;
                    validCur = true;
                }
            } catch (e) {
                delete root._cardRegistry[curSlug];
            }
        }

        if (!validCur || !curSlug) {
            root.keyboardSelectedSlug = list[0].key || list[0].slug || list[0].id;
            var firstCard = root._cardRegistry[root.keyboardSelectedSlug];
            if (firstCard) _ensureCardVisible(firstCard);
            return;
        }

        var bestSlug = "";
        var bestDist = Infinity;

        for (var i = 0; i < list.length; i++) {
            var s = list[i].key || list[i].slug || list[i].id;
            if (s === curSlug) continue;
            var card = root._cardRegistry[s];
            if (!card) continue;
            var p = null;
            try {
                if (card.parent && typeof card.mapToItem === "function") {
                    p = card.mapToItem(notesScroll.contentItem, card.width / 2, card.height / 2);
                }
            } catch (e) {
                delete root._cardRegistry[s];
                continue;
            }
            if (!p) continue;

            var dx = p.x - curX;
            var dy = p.y - curY;
            var dist = Infinity;

            if (dir === "right") {
                if (dx > 15) dist = dx * 1.5 + Math.abs(dy);
            } else if (dir === "left") {
                if (dx < -15) dist = (-dx) * 1.5 + Math.abs(dy);
            } else if (dir === "down") {
                if (dy > 15) dist = dy * 2.0 + Math.abs(dx);
            } else if (dir === "up") {
                if (dy < -15) dist = (-dy) * 2.0 + Math.abs(dx);
            }

            if (dist < bestDist) {
                bestDist = dist;
                bestSlug = s;
            }
        }

        if (bestSlug) {
            root.keyboardSelectedSlug = bestSlug;
            var targetCard = root._cardRegistry[bestSlug];
            if (targetCard) _ensureCardVisible(targetCard);
        }
    }

    function requestNewNoteWithTitle(title) {
        if (root._morphTransitioning || morphContainer.isVisible || NotesService.isEditing) return;
        // createNote(tipo, títuloInicial): el morph lo abre solo vía isEditing.
        // (Antes se pasaba un callback como título: el título quedaba con el
        // source de la función. No se sembraba "# title" en el cuerpo: el título
        // vive en el campo de título, igual que en las notas normales.)
        NotesService.createNote("text", title);
    }

    focus: true
    Keys.onPressed: (event) => {
        if (morphContainer.isExpanded || NotesService.isEditing || editorModal.visible || root.activeMorphSlug !== "") {
            if (event.key === Qt.Key_Escape) {
                root.closeNoteWithMorph();
                event.accepted = true;
            }
            return;
        }

        if (fab.expanded && event.key === Qt.Key_Escape) {
            fab.expanded = false;
            event.accepted = true;
            return;
        }

        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
            searchInput.forceActiveFocus();
            searchInput.selectAll();
            event.accepted = true;
            return;
        }

        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_N) {
            root.requestNewNote();
            event.accepted = true;
            return;
        }

        if (((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Slash || event.key === Qt.Key_Question)) || event.key === Qt.Key_F1) {
            root.openShortcutsSheet();
            event.accepted = true;
            return;
        }

        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Comma) {
            var originSt = settingsBtn.mapToItem(null, 0, 0);
            root.openSettingsRequested(Qt.rect(originSt.x, originSt.y, settingsBtn.width, settingsBtn.height));
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Tab && !searchInput.activeFocus) {
            if (event.modifiers & Qt.ShiftModifier) {
                searchInput.forceActiveFocus();
                searchInput.selectAll();
            } else {
                fab.forceActiveFocus();
            }
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Escape) {
            root.closeRequested();
            event.accepted = true;
            return;
        }

        if (event.key === Qt.Key_Slash && !searchInput.activeFocus) {
            searchInput.forceActiveFocus();
            searchInput.selectAll();
            event.accepted = true;
            return;
        }

        var activeList = root.activeNotesList;

        if (event.key === Qt.Key_P && !searchInput.activeFocus && root.keyboardSelectedSlug !== "") {
            var curNote = activeList.find(n => (n.key || n.slug || n.id) === root.keyboardSelectedSlug);
            if (curNote) {
                NotesService.togglePin(curNote);
                event.accepted = true;
                return;
            }
        }

        // Navegación espacial con teclado en las tarjetas (flechas, Enter y Supr)
        if (activeList.length > 0 && !searchInput.activeFocus) {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (root.keyboardSelectedSlug !== "") {
                    var noteData = activeList.find(n => (n.key || n.slug || n.id) === root.keyboardSelectedSlug);
                    if (noteData) {
                        var originCard = _findCurrentCardPosition(noteData.key || noteData.slug || noteData.id) || { x: width * 0.2, y: height * 0.2, width: width * 0.6, height: height * 0.6, radius: 16 };
                        root.openNoteWithMorph(noteData, originCard);
                        event.accepted = true;
                        return;
                    }
                }
            } else if (event.key === Qt.Key_Delete) {
                if (root.keyboardSelectedSlug !== "") {
                    var toDelete = activeList.find(n => (n.key || n.slug || n.id) === root.keyboardSelectedSlug);
                    if (toDelete) {
                        var delKey = toDelete.key || toDelete.slug || toDelete.id;
                        root.requestCardDelete(delKey, toDelete);
                        event.accepted = true;
                        return;
                    }
                }
            } else if (event.key === Qt.Key_Right) {
                _moveSpatialSelection("right");
                event.accepted = true;
                return;
            } else if (event.key === Qt.Key_Left) {
                _moveSpatialSelection("left");
                event.accepted = true;
                return;
            } else if (event.key === Qt.Key_Down) {
                _moveSpatialSelection("down");
                event.accepted = true;
                return;
            } else if (event.key === Qt.Key_Up) {
                _moveSpatialSelection("up");
                event.accepted = true;
                return;
            }
        }
    }

    // ── Fondo de tarjeta con Glow dinámico y Blur ─────────────────────────
    Rectangle {
        id: bgCard
        anchors.fill: parent
        radius: 20
        color: Qt.hsva(Theme.surface.hsvHue,
                       Math.min(1, Theme.surface.hsvSaturation),
                       Math.min(1, Theme.surface.hsvValue + 0.04),
                       GamemodeService.gamemodeActive ? 1.0 : Theme.panelOpacity)
        border.color: Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.08)
        border.width: 1

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor:   "#D0000000"
            shadowBlur:    0.85
            shadowVerticalOffset: 12
            shadowHorizontalOffset: 0
        }

    }

    // ── Contenedor recortado ──────────────────────────────────────────────
    ClippingRectangle {
        id: clippingRoot
        anchors.fill: parent
        radius: 20
        color: "transparent"

        ColumnLayout {
            id: homeViewLayout
            anchors.fill: parent
            spacing: 0
            opacity: morphContainer.isExpanded ? 0.0 : 1.0
            visible: opacity > 0.0

            Behavior on opacity {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
            }

            // ── Barra superior / Header ───────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 64

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 22
                    anchors.rightMargin: 20
                    spacing: 14


                    // Título de la aplicación y contador
                    ColumnLayout {
                        spacing: 0
                        Text {
                            text: I18n.t("notes.header.title", "Notas")
                            color: Theme.text
                            font.family: Theme.fontFamilyDisplay
                            font.pixelSize: Theme.fontSizeTitle + 3
                            font.bold: true
                        }
                        Text {
                            readonly property int total: NotesService.notes.length
                            readonly property int filtered: NotesService.filteredNotes.length
                            text: (NotesService.searchQuery.trim() !== "" || NotesService.activeTagFilter !== "")
                                ? (filtered + " de " + total)
                                : (total === 1 ? "1 nota" : (total + " notas"))
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeCaption
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Selector de ordenación
                    Rectangle {
                        id: sortBtn
                        Layout.preferredHeight: 38
                        Layout.preferredWidth: sortRow.implicitWidth + 20
                        radius: 10
                        color: sortMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)
                        border.color: Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.12)
                        border.width: 1

                        Behavior on color {
                            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                            ColorAnimation { duration: 120 }
                        }

                        RowLayout {
                            id: sortRow
                            anchors.centerIn: parent
                            spacing: 6

                            Image {
                                Layout.preferredWidth: 14
                                Layout.preferredHeight: 14
                                source: Theme.iconsPath + "recent.svg"
                                sourceSize: Qt.size(14, 14)
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: Theme.muted
                                }
                            }

                            SlidingLabel {
                                text: {
                                    if (NotesService.sortBy === "title") return I18n.t("notes.sort.title", "Título");
                                    if (NotesService.sortBy === "created") return I18n.t("notes.sort.created", "Creación");
                                    if (NotesService.sortBy === "lastOpened") return I18n.t("notes.sort.lastOpened", "Apertura");
                                    return I18n.t("notes.sort.modified", "Modificación");
                                }
                                color: Theme.text
                                fontFamily: Theme.fontFamily
                                fontSize: Theme.fontSizeSmall
                            }

                            Image {
                                Layout.preferredWidth: 12
                                Layout.preferredHeight: 12
                                source: Theme.iconsPath + "chevron-down.svg"
                                sourceSize: Qt.size(12, 12)
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: Theme.muted
                                }
                            }
                        }

                        MouseArea {
                            id: sortMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                NotesService.sortBy = SortLogic.nextSort(NotesService.sortBy);
                            }
                        }

                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: I18n.t("notes.sort.title", "Ordenar notas")

                        FocusRing {
                            target: sortBtn
                        }

                        Keys.onReturnPressed: NotesService.sortBy = SortLogic.nextSort(NotesService.sortBy)
                        Keys.onEnterPressed: Keys.onReturnPressed()
                        Keys.onSpacePressed: Keys.onReturnPressed()
                    }

                    // Botón de Configuración
                    Rectangle {
                        id: settingsBtn
                        Layout.preferredHeight: 38
                        Layout.preferredWidth: 38
                        radius: 10
                        opacity: (root.isSettingsOpen && !NotesService.isEditing) ? 0.0 : 1.0
                        color: settingsMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.1) : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)
                        border.color: Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.12)
                        border.width: 1

                        Behavior on color {
                            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                            ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                        }

                        Image {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            source: Theme.iconsPath + "settings.svg"
                            sourceSize: Qt.size(16, 16)
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: settingsMa.containsMouse ? Theme.text : Theme.muted

                                Behavior on colorizationColor {
                                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                    ColorAnimation { duration: 120; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        MouseArea {
                            id: settingsMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var origin = settingsBtn.mapToItem(null, 0, 0);
                                root.openSettingsRequested(Qt.rect(origin.x, origin.y, settingsBtn.width, settingsBtn.height), "");
                            }
                        }

                        activeFocusOnTab: true
                        Accessible.role: Accessible.Button
                        Accessible.name: I18n.t("config.header.title", "Configuración")

                        FocusRing {
                            target: settingsBtn
                        }

                        Keys.onReturnPressed: {
                            var origin = settingsBtn.mapToItem(null, 0, 0);
                            root.openSettingsRequested(Qt.rect(origin.x, origin.y, settingsBtn.width, settingsBtn.height), "");
                        }
                        Keys.onEnterPressed: Keys.onReturnPressed()
                        Keys.onSpacePressed: Keys.onReturnPressed()
                    }

                    // ── Barra de búsqueda rápida (Regla 9 de .instrucciones.md) ──
                    Rectangle {
                        id: searchBox
                        Layout.preferredWidth: Math.min(320, root.width * 0.38)
                        Layout.preferredHeight: 38
                        radius: 10
                        color: Qt.hsva(Theme.surface.hsvHue,
                                       Math.min(1, Theme.surface.hsvSaturation),
                                       Math.min(1, Theme.surface.hsvValue + 0.04), 1)
                        border.color: searchInput.activeFocus
                            ? Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.65)
                            : Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.12)
                        border.width: 1

                        Behavior on border.color {
                            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                            ColorAnimation { duration: 150 }
                        }

                        RowLayout {
                            anchors {
                                fill: parent
                                leftMargin: 12
                                rightMargin: 6
                            }
                            spacing: 8

                            Image {
                                Layout.preferredWidth: 16
                                Layout.preferredHeight: 16
                                source: Theme.iconsPath + "search.svg"
                                sourceSize: Qt.size(16, 16)
                                smooth: true
                                mipmap: true
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: searchInput.activeFocus ? Theme.accent : Theme.muted
                                    Behavior on colorizationColor {
                                        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                        ColorAnimation { duration: 150 }
                                    }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: I18n.t("notes.search.placeholder", "Buscar notas o tareas (Ctrl+F)...")
                                    color: Theme.muted
                                    font {
                                        pixelSize: Theme.fontSizeBody
                                        family: Theme.fontFamily
                                    }
                                    visible: searchInput.text === "" && !searchInput.activeFocus
                                    elide: Text.ElideRight
                                }

                                TextInput {
                                    id: searchInput
                                    anchors.fill: parent
                                    verticalAlignment: TextInput.AlignVCenter
                                    text: NotesService.searchQuery
                                    color: Theme.text
                                    clip: true
                                    font {
                                        pixelSize: Theme.fontSizeBody
                                        family: Theme.fontFamily
                                    }
                                    selectByMouse: true
                                    CustomTextCursor {}

                                    onTextChanged: {
                                        if (NotesService.searchQuery !== text) NotesService.searchQuery = text;
                                    }

                                    Accessible.role: Accessible.EditableText
                                    Accessible.name: I18n.t("search.placeholder", "Buscar notas...")

                                    Keys.onTabPressed: (event) => {
                                        if (root.activeNotesList.length > 0) {
                                            root.keyboardNavActive = true;
                                            var first = root.activeNotesList[0];
                                            root.keyboardSelectedSlug = first ? (first.key || first.slug || first.id || "") : "";
                                            root.forceActiveFocus();
                                        } else {
                                            fab.forceActiveFocus();
                                        }
                                        event.accepted = true;
                                    }

                                    Keys.onDownPressed: (event) => {
                                        if (root.activeNotesList.length > 0) {
                                            root.keyboardNavActive = true;
                                            var firstCard = root.activeNotesList[0];
                                            root.keyboardSelectedSlug = firstCard ? (firstCard.key || firstCard.slug || firstCard.id || "") : "";
                                            root.forceActiveFocus();
                                            event.accepted = true;
                                        }
                                    }

                                    Keys.onReturnPressed: (event) => {
                                        if (root.activeNotesList.length > 0) {
                                            var targetCard = root.activeNotesList[0];
                                            var origin = root._findCurrentCardPosition(targetCard.key || targetCard.slug || targetCard.id);
                                            root.openNoteWithMorph(targetCard, origin);
                                            event.accepted = true;
                                        } else if (text.trim() !== "") {
                                            var originFab = fab.mapToItem(clippingRoot, 0, 0, fab.width, fab.height);
                                            root.createNoteWithMorph("text", originFab);
                                            NotesService.renameNote(NotesService.activeNote.slug, text.trim());
                                            event.accepted = true;
                                        }
                                    }
                                    Keys.onEnterPressed: (event) => Keys.onReturnPressed(event)

                                    Keys.onEscapePressed: {
                                        if (text !== "") {
                                            text = "";
                                            NotesService.searchQuery = "";
                                        } else {
                                            focus = false;
                                        }
                                    }

                                    // Menú contextual personalizado (Regla 9 .instrucciones.md)
                                    MouseArea {
                                        anchors.fill: parent
                                        acceptedButtons: Qt.RightButton
                                        onClicked: (mouse) => {
                                            if (mouse.button === Qt.RightButton) {
                                                searchInput.forceActiveFocus();
                                                sharedContextMenu.open(parent);
                                            }
                                        }
                                    }
                                }
                            }

                            // Botón limpiar búsqueda (✕)
                            Rectangle {
                                visible: searchInput.text !== ""
                                Layout.preferredWidth: 22
                                Layout.preferredHeight: 22
                                radius: 6
                                color: clearHov.hovered
                                    ? Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.12)
                                    : "transparent"
                                HoverHandler { id: clearHov }

                                Image {
                                    anchors.centerIn: parent
                                    width: 14; height: 14
                                    source: Theme.iconsPath + "close.svg"
                                    sourceSize: Qt.size(14, 14)
                                    smooth: true
                                    mipmap: true
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        colorization: 1.0
                                        colorizationColor: clearHov.hovered ? Theme.text : Theme.muted
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        searchInput.text = "";
                                        NotesService.searchQuery = "";
                                        searchInput.forceActiveFocus();
                                    }
                                }
                            }
                        }
                    }
                }

                // Línea separadora sutil del header
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.06)
                }
            }

            // ── Chips de filtro por tag ─────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: NotesService.allTags.length > 0 ? 36 : 0
                visible: NotesService.allTags.length > 0
                clip: true

                Flickable {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    contentWidth: tagsRow.implicitWidth
                    flickableDirection: Flickable.HorizontalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: !root.isSettingsOpen

                    RowLayout {
                        id: tagsRow
                        height: parent.height
                        spacing: 6

                        // Chip "Todos"
                        Rectangle {
                            Layout.preferredHeight: 24
                            Layout.preferredWidth: allText.implicitWidth + 16
                            radius: 12
                            color: NotesService.activeTagFilter === ""
                                ? Theme.accent
                                : (allMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12) : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05))

                            Behavior on color {
                                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                ColorAnimation { duration: 120 }
                            }

                            Text {
                                id: allText
                                anchors.centerIn: parent
                                text: I18n.t("notes.tags.all", "Todos")
                                color: NotesService.activeTagFilter === "" ? Theme.textOn(Theme.accent) : Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeCaption
                                font.bold: NotesService.activeTagFilter === ""
                            }

                            MouseArea {
                                id: allMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: NotesService.activeTagFilter = ""
                            }
                        }

                        // Chips para cada tag
                        Repeater {
                            model: NotesService.allTags
                            Rectangle {
                                readonly property bool isSelected: NotesService.activeTagFilter.toLowerCase() === String(modelData).toLowerCase()
                                Layout.preferredHeight: 24
                                Layout.preferredWidth: tagChipText.implicitWidth + 16
                                radius: 12
                                color: isSelected
                                    ? Theme.accent
                                    : (chipMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12) : Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05))

                                Behavior on color {
                                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                    ColorAnimation { duration: 120 }
                                }

                            Text {
                                    id: tagChipText
                                    anchors.centerIn: parent
                                    text: "#" + modelData
                                    color: isSelected ? Theme.textOn(Theme.accent) : Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeCaption
                                    font.bold: isSelected
                                }

                                MouseArea {
                                    id: chipMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (isSelected) NotesService.activeTagFilter = "";
                                        else NotesService.activeTagFilter = String(modelData);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Contenedor central (Grid de notas o Editor) ───────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Vista de cuadrícula de notas
                Item {
                    id: gridContainer
                    anchors.fill: parent

                    // Blur temporal de la lista mientras se arrastra para
                    // importar (layer solo durante el arrastre: cuesta un FBO)
                    layer.enabled: root.importHintActive
                    layer.effect: MultiEffect {
                        blurEnabled: HyprlandConfig.blurEnabled && !GamemodeService.gamemodeActive
                        blur: 0.8
                        blurMax: HyprlandConfig.quickshellBlurMax
                        saturation: 0.4
                    }

                    // Estado de carga
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 12
                        visible: NotesService.loading

                        Image {
                            Layout.alignment: Qt.AlignHCenter
                            width: 32; height: 32
                            source: Theme.iconsPath + "refresh.svg"
                            sourceSize: Qt.size(32, 32)
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: Theme.accent
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: I18n.t("notes.loading", "Cargando notas...")
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody
                        }
                    }

                    // Estado vacío
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 14
                        visible: !NotesService.loading && NotesService.filteredNotes.length === 0

                        Image {
                            Layout.alignment: Qt.AlignHCenter
                            width: 48; height: 48
                            source: Theme.iconsPath + "sticky-note-2.svg"
                            sourceSize: Qt.size(48, 48)
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: Theme.muted
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: (NotesService.searchQuery === "" && NotesService.activeTagFilter === "")
                                ? I18n.t("notes.empty.title", "No tenés notas todavía")
                                : I18n.t("notes.empty.search", "No se encontraron notas")
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody + 1
                            font.bold: true
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: (NotesService.searchQuery === "" && NotesService.activeTagFilter === "")
                                ? I18n.t("notes.empty.subtitle", "Tocá el botón '+' para crear tu primera nota")
                                : (NotesService.activeTagFilter !== ""
                                    ? ("No hay notas con la etiqueta #" + NotesService.activeTagFilter)
                                    : ("Sin resultados para «" + NotesService.searchQuery + "»"))
                            color: Qt.hsva(Theme.muted.hsvHue, Theme.muted.hsvSaturation, Theme.muted.hsvValue, 0.7)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                        }

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredHeight: 36
                            Layout.preferredWidth: emptyBtnText.implicitWidth + 24
                            radius: 10
                            color: emptyBtnMa.containsMouse ? Qt.darker(Theme.primary, 1.1) : Theme.primary

                            Behavior on color {
                                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                                ColorAnimation { duration: 120 }
                            }

                            Text {
                                id: emptyBtnText
                                anchors.centerIn: parent
                                text: (NotesService.searchQuery.trim() !== "")
                                    ? ("Crear nota «" + NotesService.searchQuery.trim() + "»")
                                    : I18n.t("notes.empty.create", "Crear nota")
                                color: Theme.textOn(Theme.primary)
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeBody - 1
                                font.bold: true
                            }

                            MouseArea {
                                id: emptyBtnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (NotesService.searchQuery.trim() !== "") {
                                        var title = NotesService.searchQuery.trim();
                                        NotesService.searchQuery = "";
                                        root.requestNewNoteWithTitle(title);
                                    } else {
                                        root.requestNewNote();
                                    }
                                }
                            }
                        }
                    }

                    // Cuadrícula dinámica de notas (Masonry por columnas, Fijadas y Otras)
                    Flickable {
                        id: notesScroll
                        anchors.fill: parent
                        anchors.margins: 18
                        clip: true
                        contentWidth: width
                        contentHeight: scrollMainCol.implicitHeight + 96
                        boundsBehavior: Flickable.StopAtBounds
                        enabled: !morphContainer.isVisible && !morphContainer.isExpanded && !root.isSettingsOpen
                        interactive: !root.isSettingsOpen && !morphContainer.isVisible && !morphContainer.isExpanded

                        // Barra de scroll vertical con el estilo global
                        ScrollBar.vertical: CustomScrollBar {}

                        readonly property int cols: Math.max(2, Math.min(NotesConfig.cardsPerRow || 3, Math.floor(width / 260)))
                        readonly property real colWidth: Math.floor((width - (cols - 1) * 14) / cols)

                        Column {
                            id: scrollMainCol
                            width: parent.width
                            spacing: 16

                            // ── Sección Fijadas ─────────────────────────
                            Row {
                                spacing: 6
                                visible: root.pinnedNotesList.length > 0

                                Image {
                                    width: 14
                                    height: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: Theme.iconsPath + "push-pin.svg"
                                    sourceSize: Qt.size(14, 14)
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        colorization: 1.0
                                        colorizationColor: Theme.accent
                                    }
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: I18n.t("notes.section.pinned", "FIJADAS") + " (" + root.pinnedNotesList.length + ")"
                                    color: Theme.accent
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeCaption
                                    font.bold: true
                                }
                            }

                            Row {
                                id: pinnedMasonryRow
                                width: parent.width
                                spacing: 14
                                visible: root.pinnedNotesList.length > 0

                                Repeater {
                                    model: notesScroll.cols

                                    Column {
                                        id: pinnedColContainer
                                        width: notesScroll.colWidth
                                        spacing: 14

                                        readonly property int colIndex: index
                                        readonly property var targetData: root.pinnedColumnsData[colIndex] || []

                                        ListModel {
                                            id: pinnedColModel
                                        }

                                        onTargetDataChanged: root._syncColModel(pinnedColModel, targetData)
                                        Component.onCompleted: root._syncColModel(pinnedColModel, targetData)

                                        Repeater {
                                            model: pinnedColModel

                                            NoteCard {
                                                id: pinnedCardDelegate
                                                width: pinnedColContainer.width
                                                readonly property string cardKey: model.key || ""
                                                readonly property var currentNoteData: NotesService.getNote(cardKey)
                                                noteData: currentNoteData
                                                isCurrent: root.keyboardNavActive && root.keyboardSelectedSlug !== "" && cardKey === root.keyboardSelectedSlug
                                                isMorphing: root.activeMorphSlug !== "" && cardKey === root.activeMorphSlug
                                                onClicked: (cardItem) => {
                                                    root.keyboardNavActive = false;
                                                    root.keyboardSelectedSlug = "";
                                                    var origin = cardItem.mapToItem(clippingRoot, 0, 0, cardItem.width, cardItem.height);
                                                    root.openNoteWithMorph(currentNoteData, origin);
                                                }
                                                onDeleteRequested: root.requestCardDelete(cardKey, currentNoteData)
                                                onPinToggled: NotesService.togglePin(currentNoteData)
                                                onContextMenuRequested: (cardItem, mouse) => root.openCardContextMenu(cardItem, mouse, currentNoteData)

                                                Component.onCompleted: {
                                                    if (cardKey && typeof root !== "undefined" && root._cardRegistry) root._cardRegistry[cardKey] = pinnedCardDelegate;
                                                }
                                                Component.onDestruction: {
                                                    if (cardKey && typeof root !== "undefined" && root._cardRegistry && root._cardRegistry[cardKey] === pinnedCardDelegate) {
                                                        delete root._cardRegistry[cardKey];
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Sección Otras / General ─────────────────
                            Row {
                                spacing: 6
                                visible: root.pinnedNotesList.length > 0 && root.otherNotesList.length > 0

                                Text {
                                    text: I18n.t("notes.section.others", "OTRAS") + " (" + root.otherNotesList.length + ")"
                                    color: Theme.muted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeCaption
                                    font.bold: true
                                }
                            }

                            Row {
                                id: otherMasonryRow
                                width: parent.width
                                spacing: 14
                                visible: root.otherNotesList.length > 0

                                Repeater {
                                    model: notesScroll.cols

                                    Column {
                                        id: otherColContainer
                                        width: notesScroll.colWidth
                                        spacing: 14

                                        readonly property int colIndex: index
                                        readonly property var targetData: root.otherColumnsData[colIndex] || []

                                        ListModel {
                                            id: otherColModel
                                        }

                                        onTargetDataChanged: root._syncColModel(otherColModel, targetData)
                                        Component.onCompleted: root._syncColModel(otherColModel, targetData)

                                        Repeater {
                                            model: otherColModel

                                             NoteCard {
                                                id: otherCardDelegate
                                                width: otherColContainer.width
                                                readonly property string cardKey: model.key || ""
                                                readonly property var currentNoteData: NotesService.getNote(cardKey)
                                                noteData: currentNoteData
                                                isCurrent: root.keyboardNavActive && root.keyboardSelectedSlug !== "" && cardKey === root.keyboardSelectedSlug
                                                isMorphing: root.activeMorphSlug !== "" && cardKey === root.activeMorphSlug
                                                onClicked: (cardItem) => {
                                                    root.keyboardNavActive = false;
                                                    root.keyboardSelectedSlug = "";
                                                    var origin = cardItem.mapToItem(clippingRoot, 0, 0, cardItem.width, cardItem.height);
                                                    root.openNoteWithMorph(currentNoteData, origin);
                                                }
                                                onDeleteRequested: root.requestCardDelete(cardKey, currentNoteData)
                                                onPinToggled: NotesService.togglePin(currentNoteData)
                                                onContextMenuRequested: (cardItem, mouse) => root.openCardContextMenu(cardItem, mouse, currentNoteData)

                                                Component.onCompleted: {
                                                    if (cardKey && typeof root !== "undefined" && root._cardRegistry) root._cardRegistry[cardKey] = otherCardDelegate;
                                                }
                                                Component.onDestruction: {
                                                    if (cardKey && typeof root !== "undefined" && root._cardRegistry && root._cardRegistry[cardKey] === otherCardDelegate) {
                                                        delete root._cardRegistry[cardKey];
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Backdrop transparente para cerrar el FAB si está expandido al hacer clic afuera
                    MouseArea {
                        id: fabBackdrop
                        anchors.fill: parent
                        z: 9
                        visible: fab.expanded
                        onClicked: {
                            fab.expanded = false;
                        }
                    }

                    // FAB expandible con opciones "Importar notas" y "Nueva nota"
                    MorphingFab {
                        id: fab
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 24
                        z: 10
                        onNewNoteRequested: root.requestNewNote()
                        onClipNoteRequested: root.createNoteFromClipboard()
                        onWebClipRequested: webClipModal.open()
                        onImportNotesRequested: root.openImportFilePicker()
                    }
                }

                // Menú contextual compartido (Regla 9 .instrucciones.md)
                ContextMenu {
                    id: sharedContextMenu
                }
            }
        }

        // ── Contenedor morfeado con física SpringAnimation ───────────────────
        ClippingRectangle {
            id: morphContainer
            visible: isVisible || isExpanded
            property bool isVisible: false
            property bool isExpanded: false
            property bool springEnabled: false

            property real startX: 0
            property real startY: 0
            property real startW: 100
            property real startH: 100
            property real startRadius: 16
            property color startColor: root.cardBaseColor
            property color startBorderColor: Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.08)
            property real startBorderWidth: 1

            x: isExpanded ? 0 : startX
            y: isExpanded ? 0 : startY
            width: isExpanded ? clippingRoot.width : startW
            height: isExpanded ? clippingRoot.height : startH
            radius: isExpanded ? 20 : startRadius

            color: isExpanded ? "transparent" : startColor
            border.color: isExpanded ? "transparent" : startBorderColor
            border.width: isExpanded ? 0 : startBorderWidth

            // F18: traslación para el cierre por borrado (no toca la geometría
            // bindeada: se animan scale + este Translate + opacity)
            transform: Translate {
                id: deleteShift
            }

            Behavior on color {
                enabled: morphContainer.springEnabled && Theme.animationsEnabled && !GamemodeService.gamemodeActive
                ColorAnimation { duration: 240; easing.type: Easing.OutCubic }
            }
            Behavior on border.color {
                enabled: morphContainer.springEnabled && Theme.animationsEnabled && !GamemodeService.gamemodeActive
                ColorAnimation { duration: 240; easing.type: Easing.OutCubic }
            }

            Behavior on x {
                enabled: morphContainer.springEnabled && Theme.animationsEnabled && !GamemodeService.gamemodeActive
                SpringAnimation { spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
            }
            Behavior on y {
                enabled: morphContainer.springEnabled && Theme.animationsEnabled && !GamemodeService.gamemodeActive
                SpringAnimation { spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
            }
            Behavior on width {
                enabled: morphContainer.springEnabled && Theme.animationsEnabled && !GamemodeService.gamemodeActive
                SpringAnimation { spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
            }
            Behavior on height {
                enabled: morphContainer.springEnabled && Theme.animationsEnabled && !GamemodeService.gamemodeActive
                SpringAnimation { spring: 3.5; damping: 0.38; mass: 0.85; epsilon: 0.25 }
            }
            Behavior on radius {
                enabled: morphContainer.springEnabled && Theme.animationsEnabled && !GamemodeService.gamemodeActive
                NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
            }

            // ── Instancia única de NoteCard para continuidad 1:1 en el morfismo ──
            NoteCard {
                id: cardContentClone
                anchors.fill: parent
                visible: opacity > 0.0 && root.isCardMorph
                opacity: morphContainer.isExpanded ? 0.0 : 1.0
                noteData: NotesService.activeNote || NotesService.getNote(root.activeMorphSlug) || root.morphingNoteData
                isMorphing: false
                enabled: false

                Behavior on opacity {
                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
            }

            NoteEditorModal {
                id: editorModal
                anchors.fill: parent
                isExpanded: morphContainer.isExpanded
                noteData: NotesService.activeNote
                isSettingsOpen: root.isSettingsOpen
                opacity: morphContainer.isExpanded ? 1.0 : 0.0
                visible: opacity > 0.0

                Behavior on opacity {
                    enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }

                onCloseRequested: root.closeNoteWithMorph()
                onNoteKeyChanged: (oldKey, newKey) => {
                    root.activeMorphSlug = newKey;
                }
                onSaveRequested: (data, cb) => NotesService.saveNote(data, cb)
                onDeleteRequested: (slug) => {
                    // slug ya es clave (slug+ext) desde F6
                    var note = NotesService.getNote(slug) || NotesService.activeNote;
                    if (NotesService.isUntouchedDraft && NotesService.isUntouchedDraft(slug)) {
                        NotesService.queueDelete(slug, note);
                        root.closeNoteWithMorph();
                        return;
                    }
                    NotesService.markPendingDelete(slug, false);
                    root.closeNoteForDelete();
                }
                onPasteImageRequested: (slug, cb) => NotesService.pasteImage(slug, cb)
            }
        }

        // ── Toast flotante de Deshacer borrado ───────────────────────────────
        Rectangle {
            id: undoToast
            readonly property bool active: NotesService.pendingDeleteCount > 0

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            z: 1000

            width: Math.min(380, parent.width - 32)
            height: 48
            radius: 12
            color: Qt.hsva(Theme.surface.hsvHue,
                           Math.min(1, Theme.surface.hsvSaturation),
                           Math.min(1, Theme.surface.hsvValue + 0.04),
                           0.75)
            border.color: Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.14)
            border.width: 1

            opacity: active ? 1.0 : 0.0
            visible: opacity > 0.0

            Behavior on opacity {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#80000000"
                shadowBlur: 0.6
                shadowVerticalOffset: 6
            }

            function showUndo(slug, noteData) {
                NotesService.queueDelete(slug, noteData);
            }

            function commitDelete() {
                NotesService.commitPendingDeletions();
            }

            function undo() {
                NotesService.undoPendingDeletions();
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 12
                spacing: 12

                Image {
                    width: 18
                    height: 18
                    source: Theme.iconsPath + "delete.svg"
                    sourceSize: Qt.size(18, 18)
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: Theme.danger
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: NotesService.pendingDeleteCount <= 1
                        ? I18n.t("notes.toast.deleted", "Nota eliminada")
                        : I18n.t("notes.toast.deleted_multi", "%1 notas eliminadas").arg(NotesService.pendingDeleteCount)
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    elide: Text.ElideRight
                }

                // Botón Deshacer
                Rectangle {
                    width: undoBtnContent.implicitWidth + 18
                    height: 30
                    radius: 8
                    color: undoBtnMa.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)
                    border.width: 1

                    RowLayout {
                        id: undoBtnContent
                        anchors.centerIn: parent
                        spacing: 4

                        Image {
                            width: 14
                            height: 14
                            source: Theme.iconsPath + "undo.svg"
                            sourceSize: Qt.size(14, 14)
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: Theme.accent
                            }
                        }

                        Text {
                            text: I18n.t("notes.toast.undo", "Deshacer")
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeBody - 1
                            font.bold: true
                        }
                    }

                    MouseArea {
                        id: undoBtnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NotesService.undoPendingDeletions()
                    }
                }

                // Botón descartar / cerrar toast (confirma borrado inmediatamente)
                Rectangle {
                    width: 26
                    height: 26
                    radius: 6
                    color: dismissMa.containsMouse ? Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.12) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: Theme.muted
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    MouseArea {
                        id: dismissMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NotesService.commitPendingDeletions()
                    }
                }
            }
        }
    }

    // ── Drop de archivos .md a nivel ventana ─────────────────────────
    // Todas las DropArea superpuestas reciben el evento; esta solo actúa sobre
    // .md (imágenes las maneja el editor) y solo acepta si importó algo.
    DropArea {
        id: importDropArea
        anchors.fill: parent
        property bool hasImportable: false

        onEntered: (drag) => {
            var canImport = root._dropHasImportable(drag);
            importDropArea.hasImportable = canImport;
            if (canImport && root.importCardState === "hidden") {
                root.importCardState = "drop_hint";
            }
        }
        onExited: {
            importDropArea.hasImportable = false;
            if (root.importCardState === "drop_hint") {
                root.importCardState = "hidden";
            }
        }
        onDropped: (drop) => {
            importDropArea.hasImportable = false;
            if (!drop.hasUrls || !drop.urls || drop.urls.length === 0) {
                if (root.importCardState === "drop_hint") root.importCardState = "hidden";
                return;
            }
            var rawUrls = [];
            for (var u = 0; u < drop.urls.length; u++) rawUrls.push(drop.urls[u]);
            root.importFilesFromUrls(rawUrls);
            drop.acceptProposedAction();
        }
    }

    // ── Aviso y Diálogo de importación con morfismo SpringAnimation ──────────
    Rectangle {
        id: importDim
        anchors.fill: parent
        radius: 20
        color: "#000000"
        z: 400
        opacity: root.importHintActive ? 0.35 : 0.0
        visible: opacity > 0.0

        Behavior on opacity {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        MouseArea {
            anchors.fill: parent
            enabled: root.importCardState === "docx_confirm" || root.importCardState === "docx_missing_deps"
            onClicked: {
                root.importCardState = "hidden";
                root.pendingDocxItems = [];
            }
        }
    }

    Rectangle {
        id: importHint
        anchors.centerIn: parent
        z: 500

        readonly property real targetWidth: {
            if (root.importCardState === "docx_confirm") return Math.min(460, parent.width - 48);
            if (root.importCardState === "docx_converting") return Math.min(400, parent.width - 48);
            if (root.importCardState === "docx_missing_deps" || root.importCardState === "deps_installing") return Math.min(440, parent.width - 48);
            return Math.min(340, parent.width - 48);
        }

        readonly property real targetHeight: {
            if (root.importCardState === "docx_confirm") return docxConfirmCol.implicitHeight + 36;
            if (root.importCardState === "docx_converting") return docxConvertingCol.implicitHeight + 36;
            if (root.importCardState === "docx_missing_deps") return docxMissingDepsCol.implicitHeight + 36;
            if (root.importCardState === "deps_installing") return depsInstallingCol.implicitHeight + 36;
            return importHintCol.implicitHeight + 32;
        }

        readonly property real targetRadius: {
            if (root.importCardState === "hidden" || root.importCardState === "drop_hint") return 16;
            return 18;
        }

        width: targetWidth
        height: targetHeight
        radius: targetRadius

        color: Qt.hsva(Theme.surface.hsvHue,
                       Math.min(1, Theme.surface.hsvSaturation),
                       Math.min(1, Theme.surface.hsvValue + 0.05),
                       0.96)
        border.color: (root.importCardState === "docx_missing_deps")
            ? Qt.hsva(Theme.warning.hsvHue, Theme.warning.hsvSaturation, Theme.warning.hsvValue, 0.6)
            : Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.5)
        border.width: 1

        opacity: root.importHintActive ? 1.0 : 0.0
        visible: opacity > 0.0

        Behavior on opacity {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }

        Behavior on width {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            SpringAnimation { spring: 3.8; damping: 0.32; mass: 0.75; epsilon: 0.25 }
        }
        Behavior on height {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            SpringAnimation { spring: 3.8; damping: 0.32; mass: 0.75; epsilon: 0.25 }
        }
        Behavior on radius {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            SpringAnimation { spring: 3.8; damping: 0.32; mass: 0.75; epsilon: 0.25 }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#80000000"
            shadowBlur: 0.6
            shadowVerticalOffset: 6
        }

        // 1. Vista Drag Drop estándar
        ColumnLayout {
            id: importHintCol
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 20
                rightMargin: 20
            }
            spacing: 8
            visible: opacity > 0.0
            opacity: (root.importCardState === "drop_hint" || root.importCardState === "hidden") ? 1.0 : 0.0
            Behavior on opacity {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            Image {
                Layout.alignment: Qt.AlignHCenter
                width: 28; height: 28
                source: Theme.iconsPath + "download.svg"
                sourceSize: Qt.size(28, 28)
                smooth: true
                mipmap: true
                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: Theme.accent
                }
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: I18n.t("notes.import.drop_title", "Soltá para agregar")
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeBody + 1
                font.bold: true
            }

            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: NotesConfig.effectiveImportMode() === "move"
                    ? I18n.t("notes.import.drop_move", "Se moverá a tu carpeta de notas")
                    : I18n.t("notes.import.drop_copy", "Se copiará a tu carpeta de notas")
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeCaption
            }
        }

        // 2. Vista Confirmación Conversión .docx
        ColumnLayout {
            id: docxConfirmCol
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 20
                rightMargin: 20
            }
            spacing: 12
            visible: opacity > 0.0
            opacity: root.importCardState === "docx_confirm" ? 1.0 : 0.0
            Behavior on opacity {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            RowLayout {
                spacing: 10
                Image {
                    width: 26; height: 26
                    source: Theme.iconsPath + "download.svg"
                    sourceSize: Qt.size(26, 26)
                    smooth: true
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: Theme.accent
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: I18n.t("notes.import.convert_confirm_title", "¿Querés convertir este documento a Markdown?")
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody + 1
                        font.bold: true
                        wrapMode: Text.Wrap
                    }
                    Text {
                        Layout.fillWidth: true
                        text: root.pendingDocxName
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeCaption
                        font.bold: true
                        elide: Text.ElideMiddle
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: NotesConfig.effectiveImportMode() === "move"
                    ? I18n.t("notes.import.convert_confirm_sub_move", "Se convertirá a Markdown con sus imágenes y se quitará el archivo original")
                    : I18n.t("notes.import.convert_confirm_sub_copy", "Se extraerán el formato y las imágenes en una nota nueva")
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeCaption
                wrapMode: Text.Wrap
            }

            // Fila de botones según configuración
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Layout.topMargin: 4

                // Botón Cancelar (Secundario Outline)
                Rectangle {
                    implicitWidth: docxCancelLbl.implicitWidth + 24
                    implicitHeight: 32
                    radius: 8
                    color: docxCancelHov.containsMouse ? Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.10) : "transparent"
                    border.color: Qt.hsva(Theme.muted.hsvHue, Theme.muted.hsvSaturation, Theme.muted.hsvValue, 0.35)
                    border.width: 1
                    HoverHandler { id: docxCancelHov }
                    Text {
                        id: docxCancelLbl
                        anchors.centerIn: parent
                        text: I18n.t("common.actions.cancel", "Cancelar")
                        color: docxCancelHov.containsMouse ? Theme.text : Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.importCardState = "hidden";
                            root.pendingDocxItems = [];
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Botón "Copiar y convertir" (solo en modo mover)
                Rectangle {
                    visible: NotesConfig.effectiveImportMode() === "move"
                    implicitWidth: copyConvLbl.implicitWidth + 20
                    implicitHeight: 32
                    radius: 8
                    scale: copyConvMa.pressed ? 0.94 : 1
                    Behavior on scale {
                        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                        NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
                    }
                    color: copyConvMa.pressed
                        ? Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Math.min(1, Theme.accent.hsvValue + 0.15), 0.50)
                        : (copyConvHov.containsMouse
                            ? Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.22)
                            : Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.12))
                    border.color: Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.45)
                    border.width: 1
                    HoverHandler { id: copyConvHov }
                    Text {
                        id: copyConvLbl
                        anchors.centerIn: parent
                        text: I18n.t("notes.import.copy_convert", I18n.t("notes.import.docx_copy_convert", "Copiar y convertir"))
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: copyConvMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.importCardState = "docx_converting";
                            NotesService.convertDocuments(root.pendingDocxItems, "copy");
                        }
                    }
                }

                // Botón Convertir (Primario)
                Rectangle {
                    implicitWidth: docxConvLbl.implicitWidth + 24
                    implicitHeight: 32
                    radius: 8
                    scale: docxConvMa.pressed ? 0.94 : 1
                    Behavior on scale {
                        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                        NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
                    }
                    color: docxConvMa.pressed
                        ? Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Math.min(1, Theme.accent.hsvValue + 0.18), 0.65)
                        : (docxConvHov.containsMouse
                            ? Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.42)
                            : Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.28))
                    border.color: Theme.accent
                    HoverHandler { id: docxConvHov }
                    Text {
                        id: docxConvLbl
                        anchors.centerIn: parent
                        text: I18n.t("notes.import.convert", I18n.t("notes.import.docx_convert", "Convertir"))
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                    }
                    MouseArea {
                        id: docxConvMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var m = NotesConfig.effectiveImportMode();
                            root.importCardState = "docx_converting";
                            NotesService.convertDocuments(root.pendingDocxItems, m);
                        }
                    }
                }
            }
        }

        // 3. Vista Convirtiendo con Barra de Progreso (estilo Designs)
        ColumnLayout {
            id: docxConvertingCol
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 20
                rightMargin: 20
            }
            spacing: 12
            visible: opacity > 0.0
            opacity: root.importCardState === "docx_converting" ? 1.0 : 0.0
            Behavior on opacity {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            RowLayout {
                spacing: 10
                Image {
                    width: 24; height: 24
                    source: Theme.iconsPath + "download.svg"
                    sourceSize: Qt.size(24, 24)
                    layer.enabled: true
                    layer.effect: MultiEffect { colorization: 1.0; colorizationColor: Theme.accent }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        text: I18n.t("notes.import.converting", I18n.t("notes.import.docx_converting", "Convirtiendo documento…"))
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeBody
                        font.bold: true
                    }
                    Text {
                        Layout.fillWidth: true
                        text: NotesService.docxCurrentFile || root.pendingDocxName
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeCaption
                        elide: Text.ElideMiddle
                    }
                }
            }

            // Barra de progreso determinada con gradiente horizontal (sin números)
            Rectangle {
                Layout.fillWidth: true
                height: 6
                radius: 3
                color: Qt.hsva(Theme.muted.hsvHue, Theme.muted.hsvSaturation, Theme.muted.hsvValue, 0.20)
                Rectangle {
                    width: Math.max(6, parent.width * Math.max(0.04, NotesService.docxConversionProgress))
                    height: parent.height
                    radius: 3
                    Behavior on width {
                        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: Theme.accent }
                        GradientStop { position: 1.0; color: Theme.success }
                    }
                }
            }
        }

        // 4. Vista Faltan Dependencias
        ColumnLayout {
            id: docxMissingDepsCol
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 20
                rightMargin: 20
            }
            spacing: 12
            visible: opacity > 0.0
            opacity: root.importCardState === "docx_missing_deps" ? 1.0 : 0.0
            Behavior on opacity {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            RowLayout {
                spacing: 10
                Image {
                    width: 24; height: 24
                    source: Theme.iconsPath + "alert.svg"
                    sourceSize: Qt.size(24, 24)
                    layer.enabled: true
                    layer.effect: MultiEffect { colorization: 1.0; colorizationColor: Theme.warning }
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.t("notes.deps.rejected_title", I18n.t("notes.deps.docx_rejected_title", "Se requieren dependencias para convertir este archivo"))
                    color: Theme.warning
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                }
            }

            Text {
                Layout.fillWidth: true
                text: {
                    var needed = NotesService.missingDepsFor(root.pendingDocxItems);
                    var list = (needed.length > 0) ? needed.join(", ") : (NotesService.missingDeps.join(", ") || "python-docx");
                    return I18n.t("notes.deps.missing_desc_generic", "Para convertir este archivo se requiere instalar: ") + list;
                }
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeCaption
                wrapMode: Text.Wrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Layout.topMargin: 4

                Rectangle {
                    implicitWidth: depsCancelLbl.implicitWidth + 24
                    implicitHeight: 32
                    radius: 8
                    color: depsCancelHov.containsMouse ? Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.10) : "transparent"
                    border.color: Qt.hsva(Theme.muted.hsvHue, Theme.muted.hsvSaturation, Theme.muted.hsvValue, 0.35)
                    border.width: 1
                    HoverHandler { id: depsCancelHov }
                    Text {
                        id: depsCancelLbl
                        anchors.centerIn: parent
                        text: I18n.t("common.actions.cancel", "Cancelar")
                        color: depsCancelHov.containsMouse ? Theme.text : Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.importCardState = "hidden";
                            root.pendingDocxItems = [];
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: depsInstallLbl.implicitWidth + 24
                    implicitHeight: 32
                    radius: 8
                    scale: depsInstallMa.pressed ? 0.94 : 1
                    Behavior on scale {
                        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                        NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
                    }
                    color: depsInstallMa.pressed
                        ? Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Math.min(1, Theme.accent.hsvValue + 0.18), 0.65)
                        : (depsInstallHov.containsMouse
                            ? Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.42)
                            : Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.28))
                    border.color: Theme.accent
                    HoverHandler { id: depsInstallHov }
                    Text {
                        id: depsInstallLbl
                        anchors.centerIn: parent
                        text: I18n.t("notes.deps.install_btn", "Instalar dependencias")
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                    }
                    MouseArea {
                        id: depsInstallMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.importCardState = "deps_installing";
                            var needed = NotesService.missingDepsFor(root.pendingDocxItems);
                            NotesService.installMissingDeps(needed);
                        }
                    }
                }
            }
        }

        // 5. Vista Instalando dependencias
        ColumnLayout {
            id: depsInstallingCol
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 20
                rightMargin: 20
            }
            spacing: 12
            visible: opacity > 0.0
            opacity: root.importCardState === "deps_installing" ? 1.0 : 0.0
            Behavior on opacity {
                enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            RowLayout {
                spacing: 10
                Image {
                    width: 24; height: 24
                    source: Theme.iconsPath + "download.svg"
                    sourceSize: Qt.size(24, 24)
                    layer.enabled: true
                    layer.effect: MultiEffect { colorization: 1.0; colorizationColor: Theme.accent }
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.t("notes.deps.installing", "Instalando dependencias…")
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody
                    font.bold: true
                }
            }

            ClippingRectangle {
                Layout.fillWidth: true
                height: 6
                radius: 3
                color: Qt.hsva(Theme.muted.hsvHue, Theme.muted.hsvSaturation, Theme.muted.hsvValue, 0.20)
                Rectangle {
                    id: indBar
                    height: parent.height
                    width: parent.width * 0.35
                    radius: 3
                    color: Theme.accent
                    x: -width
                    SequentialAnimation on x {
                        loops: (root.importCardState === "deps_installing" && !GamemodeService.gamemodeActive) ? Animation.Infinite : 0
                        running: root.importCardState === "deps_installing"
                        NumberAnimation { to: indBar.parent.width; duration: 1400; easing.type: Easing.InOutCubic }
                        NumberAnimation { to: -indBar.width; duration: 0 }
                    }
                }
            }
        }
    }

    // ── Popup estilizado al abrir la app si faltan dependencias ─────────
    Rectangle {
        id: startupDepsDim
        anchors.fill: parent
        radius: 20
        color: "#000000"
        z: 600
        opacity: root.startupDepsDialogVisible ? 0.45 : 0.0
        visible: opacity > 0.0
        Behavior on opacity {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
        MouseArea {
            anchors.fill: parent
            enabled: root.startupDepsDialogVisible && !NotesService.depsInstalling
            onClicked: root.startupDepsDialogVisible = false
        }
    }

    Rectangle {
        id: startupDepsModal
        anchors.centerIn: parent
        z: 650
        width: Math.min(420, parent.width - 48)
        implicitHeight: startupDepsCol.implicitHeight + 36
        radius: 18
        color: Qt.hsva(Theme.surface.hsvHue,
                       Math.min(1, Theme.surface.hsvSaturation),
                       Math.min(1, Theme.surface.hsvValue + 0.05),
                       0.96)
        border.color: Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.45)
        border.width: 1
        opacity: root.startupDepsDialogVisible ? 1.0 : 0.0
        visible: opacity > 0.0

        Behavior on opacity {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#80000000"
            shadowBlur: 0.6
            shadowVerticalOffset: 6
        }

        ColumnLayout {
            id: startupDepsCol
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 20
                rightMargin: 20
            }
            spacing: 12

            RowLayout {
                spacing: 10
                Image {
                    width: 24; height: 24
                    source: Theme.iconsPath + "alert.svg"
                    sourceSize: Qt.size(24, 24)
                    layer.enabled: true
                    layer.effect: MultiEffect { colorization: 1.0; colorizationColor: Theme.accent }
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.t("notes.deps.missing_title", "Faltan dependencias para Notas")
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeBody + 1
                    font.bold: true
                }
            }

            Text {
                Layout.fillWidth: true
                text: I18n.t("notes.deps.missing_desc", "Para convertir documentos .docx con imágenes se requiere instalar: ") + (NotesService.missingDeps.join(", ") || "python-docx")
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeCaption
                wrapMode: Text.Wrap
            }

            ClippingRectangle {
                Layout.fillWidth: true
                height: 6
                radius: 3
                visible: NotesService.depsInstalling
                color: Qt.hsva(Theme.muted.hsvHue, Theme.muted.hsvSaturation, Theme.muted.hsvValue, 0.20)
                Rectangle {
                    id: startupIndBar
                    height: parent.height
                    width: parent.width * 0.35
                    radius: 3
                    color: Theme.accent
                    x: -width
                    SequentialAnimation on x {
                        loops: (NotesService.depsInstalling && !GamemodeService.gamemodeActive) ? Animation.Infinite : 0
                        running: NotesService.depsInstalling
                        NumberAnimation { to: startupIndBar.parent.width; duration: 1400; easing.type: Easing.InOutCubic }
                        NumberAnimation { to: -startupIndBar.width; duration: 0 }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Layout.topMargin: 4

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: laterLbl.implicitWidth + 24
                    implicitHeight: 32
                    radius: 8
                    enabled: !NotesService.depsInstalling
                    opacity: enabled ? 1.0 : 0.4
                    color: laterHov.containsMouse ? Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.10) : "transparent"
                    border.color: Qt.hsva(Theme.muted.hsvHue, Theme.muted.hsvSaturation, Theme.muted.hsvValue, 0.35)
                    border.width: 1
                    HoverHandler { id: laterHov }
                    Text {
                        id: laterLbl
                        anchors.centerIn: parent
                        text: I18n.t("notes.deps.later", "Ahora no")
                        color: laterHov.containsMouse ? Theme.text : Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.startupDepsDialogVisible = false
                    }
                }

                Rectangle {
                    implicitWidth: installLbl.implicitWidth + 24
                    implicitHeight: 32
                    radius: 8
                    enabled: !NotesService.depsInstalling
                    opacity: enabled ? 1.0 : 0.6
                    scale: installMa.pressed ? 0.94 : 1
                    Behavior on scale {
                        enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
                        NumberAnimation { duration: 80; easing.type: Easing.OutCubic }
                    }
                    color: installMa.pressed
                        ? Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Math.min(1, Theme.accent.hsvValue + 0.18), 0.65)
                        : (installHov.containsMouse
                            ? Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.42)
                            : Qt.hsva(Theme.accent.hsvHue, Theme.accent.hsvSaturation, Theme.accent.hsvValue, 0.28))
                    border.color: Theme.accent
                    HoverHandler { id: installHov }
                    Text {
                        id: installLbl
                        anchors.centerIn: parent
                        text: NotesService.depsInstalling ? I18n.t("notes.deps.installing", "Instalando dependencias…") : I18n.t("notes.deps.install_btn", "Instalar dependencias")
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.bold: true
                    }
                    MouseArea {
                        id: installMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NotesService.installMissingDeps()
                    }
                }
            }
        }
    }

    // ── Toast de resumen de importación ────────────────────────────────
    Rectangle {
        id: importToast
        property string toastText: ""

        function showText(msg) {
            importToast.toastText = msg;
            importToastTimer.restart();
        }

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 84
        z: 1000

        width: Math.min(420, parent.width - 32)
        height: 44
        radius: 12
        color: Qt.hsva(Theme.surface.hsvHue,
                       Math.min(1, Theme.surface.hsvSaturation),
                       Math.min(1, Theme.surface.hsvValue + 0.04),
                       0.92)
        border.color: Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.14)
        border.width: 1

        opacity: importToastTimer.running ? 1.0 : 0.0
        visible: opacity > 0.0

        Behavior on opacity {
            enabled: Theme.animationsEnabled && !GamemodeService.gamemodeActive
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }

        Text {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: importToast.toastText
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeBody - 1
            elide: Text.ElideRight
            maximumLineCount: 2
            wrapMode: Text.Wrap
        }

        Timer {
            id: importToastTimer
            interval: 4000
            repeat: false
        }
    }

    Connections {
        target: NotesService
        function onImportFinished(summary) { root._showImportSummary(summary); }
        function onDeletePartial(slug) {
            importToast.showText(I18n.t("notes.toast.kept_folder", "Carpeta conservada: tiene otros archivos"));
        }
        function onDepsCheckedFinished(ok) {
            if (!ok && NotesService.activeNote === null) {
                root.startupDepsDialogVisible = true;
            }
        }
        function onDocxConverted(filePath, success) {
            if (root.importCardState === "docx_converting") {
                root.importCardState = "hidden";
                root.pendingDocxItems = [];
                if (success) {
                    importToast.showText(I18n.t("notes.import.imported", "Nota importada"));
                } else {
                    importToast.showText(I18n.t("notes.import.failed", "No se pudo importar"));
                }
            }
        }
        function onDepsInstalled(success) {
            if (success) {
                if (root.importCardState === "deps_installing") {
                    if (root.pendingDocxItems.length > 0) {
                        root.importCardState = "docx_confirm";
                    } else {
                        root.importCardState = "hidden";
                    }
                }
                root.startupDepsDialogVisible = false;
                importToast.showText(I18n.t("common.states.active", "Activo") + ": dependencias listas");
            } else {
                if (root.importCardState === "deps_installing") {
                    root.importCardState = "docx_missing_deps";
                }
                importToast.showText(I18n.t("notes.deps.install_error", "No se pudieron instalar las dependencias"));
            }
        }
    }

    WebClipModal {
        id: webClipModal
        anchors.fill: parent
        onNoteClipped: (res) => {
            if (!res || !res.slug) return;
            var origin = fab.mapToItem(clippingRoot, 0, 0, fab.width, fab.height);
            var note = NotesService.getNote(res.slug) || {
                slug: res.slug,
                key: res.slug + ".md",
                title: res.title || res.slug,
                filePath: res.path,
                fullPath: res.path,
                tags: ["web"],
                body: ""
            };
            root.openNoteWithMorph(note, origin);
            importToast.showText(I18n.t("notes.toast.clipped_success", "Artículo web guardado en notas"));
        }
    }

    function openWebClipper(initialUrl) {
        if (webClipModal) {
            webClipModal.open(initialUrl);
        }
    }

    function openShortcutsSheet() {
        var rect = getSettingsButtonRect();
        root.openSettingsRequested(rect, "shortcuts");
    }

    // ── Funciones de animación y ciclo de vida de morfismo ──────────────────
    function openNoteWithMorph(noteData, origin) {
        if (!noteData) return;
        root.commitUndoToast();
        if (NotesService.debug) console.log("[NotesContent - morph] Abriendo nota con morfismo:", noteData.slug || noteData.title);

        var isRemoteLocked = (typeof Sys !== "undefined" && typeof Sys.isNoteBeingEditedElsewhere === "function" && noteData.filePath) 
            ? Sys.isNoteBeingEditedElsewhere(noteData.filePath) : false;
        if (isRemoteLocked) {
            noteData.readOnly = true;
            editorModal.remoteLocked = true;
        } else {
            editorModal.remoteLocked = false;
        }

        var orig = origin || _findCurrentCardPosition(noteData.key || noteData.slug || noteData.id, true) || {
            x: width * 0.2,
            y: height * 0.2,
            width: width * 0.6,
            height: height * 0.6,
            radius: 16
        };

        root._morphTransitioning = true;
        root.keyboardNavActive = false;
        root.keyboardSelectedSlug = "";
        root.isCardMorph = true;
        root.activeMorphSlug = noteData.key || noteData.slug || noteData.id || "";
        root.morphingNoteData = noteData;

        morphContainer.springEnabled = false;
        morphContainer.isExpanded = false;
        morphContainer.startX = orig.x;
        morphContainer.startY = orig.y;
        morphContainer.startW = orig.width;
        morphContainer.startH = orig.height;
        morphContainer.startRadius = orig.radius !== undefined ? orig.radius : 16;
        morphContainer.startColor = root.cardBaseColor;
        morphContainer.startBorderColor = Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.08);
        morphContainer.startBorderWidth = 1;
        morphContainer.isVisible = true;

        // Estado limpio del morph (por si un borrado anterior dejó transform)
        morphContainer.scale = 1;
        morphContainer.opacity = 1;
        deleteShift.x = 0;
        deleteShift.y = 0;
        root._deleteAnimActive = false;

        // Carga diferida de bloques (solo apertura fresca, no re-entradas
        // con el editor ya expandido). Debe ir antes de openNote: el modal lee
        // morphReady al recibir la nota.
        var freshOpen = !morphContainer.isExpanded;
        if (freshOpen) {
            editorModal.morphReady = false;
            if (Theme.animationsEnabled && !GamemodeService.gamemodeActive) {
                morphOpenTimer.restart();
            } else {
                editorModal.morphReady = true;
            }
        } else if (!editorModal.morphReady) {
            editorModal.morphReady = true;
        }

        NotesService.openNote(noteData);

        Qt.callLater(function() {
            morphContainer.springEnabled = true;
            morphContainer.isExpanded = true;
            root._morphTransitioning = false;
        });
    }

    function createNoteWithMorph(type, origin, initialTitle, initialBody) {
        root.commitUndoToast();
        if (NotesService.debug) console.log("[NotesContent - morph] Creando nota con morfismo tipo:", type);
        var orig = origin || {
            x: fab.x,
            y: fab.y,
            width: fab.width,
            height: fab.height,
            radius: fab.radius
        };

        root._morphTransitioning = true;
        root.isCardMorph = false;
        root.activeMorphSlug = "";
        root.morphingNoteData = null;

        morphContainer.springEnabled = false;
        morphContainer.isExpanded = false;
        morphContainer.startX = orig.x;
        morphContainer.startY = orig.y;
        morphContainer.startW = orig.width;
        morphContainer.startH = orig.height;
        morphContainer.startRadius = orig.radius !== undefined ? orig.radius : 16;
        morphContainer.startColor = Theme.primary;
        morphContainer.startBorderColor = "transparent";
        morphContainer.startBorderWidth = 0;
        morphContainer.isVisible = true;

        NotesService.createNote(type, initialTitle, initialBody);

        Qt.callLater(function() {
            morphContainer.springEnabled = true;
            morphContainer.isExpanded = true;
            root._morphTransitioning = false;
        });
    }

    function createNoteFromClipboard() {
        if (root._morphTransitioning || morphContainer.isVisible || NotesService.isEditing) return;
        var clip = (typeof Sys !== "undefined" && typeof Sys.clipboardText === "string" && Sys.clipboardText !== "")
            ? Sys.clipboardText
            : ((typeof Quickshell !== "undefined" && typeof Quickshell.clipboardText === "string") ? Quickshell.clipboardText : "");
        if (!clip || clip.trim() === "") {
            importToast.showText(I18n.t("notes.toast.clipboard_empty", "El portapapeles está vacío"));
            return;
        }

        var lines = clip.trim().split("\n");
        var firstLine = (lines[0] || "").trim();
        var initialTitle = "";
        var initialBody = "";

        var isUrl = /^https?:\/\//i.test(firstLine);
        if (isUrl) {
            initialTitle = firstLine.length > 50 ? firstLine.substring(0, 47) + "..." : firstLine;
            initialBody = "[" + firstLine + "](" + firstLine + ")\n";
        } else {
            if (firstLine.startsWith("# ")) {
                initialTitle = firstLine.substring(2).trim();
                initialBody = lines.slice(1).join("\n").trim();
            } else {
                initialTitle = firstLine.length > 45 ? firstLine.substring(0, 42) + "..." : firstLine;
                initialBody = clip.trim();
            }
        }

        var origin = fab.mapToItem(clippingRoot, 0, 0, fab.width, fab.height);
        root.createNoteWithMorph("text", origin, initialTitle, initialBody);
        importToast.showText(I18n.t("notes.toast.note_from_clipboard", "Nota creada desde portapapeles"));
    }

    function openCardContextMenu(cardItem, mouse, noteData) {
        if (!cardItem || !noteData) return;
        var filePath = noteData.filePath || "";
        var slug = noteData.slug || "";
        var fileName = noteData.fileName || (slug + ".md");
        var baseDir = NotesService.resolveNoteBaseDir(noteData);
        var isPinned = !!noteData.pinned;

        var items = [
            {
                label: I18n.t("notes.menu.copy_abs_path", "Copiar ruta absoluta"),
                icon: Theme.iconsPath + "content-copy.svg",
                onTriggered: function() {
                    Quickshell.clipboardText = filePath;
                    importToast.showText(I18n.t("notes.toast.path_copied", "Ruta copiada al portapapeles"));
                }
            },
            {
                label: I18n.t("notes.menu.copy_rel_path", "Copiar nombre / ruta relativa"),
                icon: Theme.iconsPath + "content-copy.svg",
                onTriggered: function() {
                    Quickshell.clipboardText = fileName;
                    importToast.showText(I18n.t("notes.toast.rel_path_copied", "Nombre copiado al portapapeles"));
                }
            },
            {
                label: I18n.t("notes.menu.open_folder", "Abrir carpeta contenedora"),
                icon: Theme.iconsPath + "folder.svg",
                onTriggered: function() {
                    Quickshell.execDetached(["xdg-open", baseDir]);
                }
            },
            { kind: "separator" },
            {
                label: isPinned ? I18n.t("notes.menu.unpin", "Desfijar nota") : I18n.t("notes.menu.pin", "Fijar nota"),
                icon: Theme.iconsPath + "push-pin.svg",
                onTriggered: function() {
                    NotesService.togglePin(noteData);
                }
            },
            {
                label: I18n.t("notes.menu.delete", "Eliminar nota"),
                icon: Theme.iconsPath + "delete.svg",
                danger: true,
                onTriggered: function() {
                    root.requestCardDelete(noteData.key || slug, noteData);
                }
            }
        ];

        var clickX = (mouse && typeof mouse.x === "number") ? mouse.x : (cardItem.width / 2);
        var clickY = (mouse && typeof mouse.y === "number") ? mouse.y : (cardItem.height / 2);
        sharedContextMenu.openAt(cardItem, clickX, clickY, items);
    }

    function openNoteImmediate(noteData) {
        if (!noteData) return;
        root.commitUndoToast();

        var isRemoteLocked = (typeof Sys !== "undefined" && typeof Sys.isNoteBeingEditedElsewhere === "function" && noteData.filePath) 
            ? Sys.isNoteBeingEditedElsewhere(noteData.filePath) : false;
        if (isRemoteLocked) {
            noteData.readOnly = true;
            editorModal.remoteLocked = true;
        } else {
            editorModal.remoteLocked = false;
        }

        root.keyboardNavActive = false;
        root.keyboardSelectedSlug = "";
        root.isCardMorph = true;
        root.activeMorphSlug = noteData.key || noteData.slug || noteData.id || "";
        root.morphingNoteData = noteData;

        // Calcular posición de origen en el menú de inicio para tener geometría válida de cierre
        var cardPos = _findCurrentCardPosition(root.activeMorphSlug, true);
        if (cardPos) {
            morphContainer.startX = cardPos.x;
            morphContainer.startY = cardPos.y;
            morphContainer.startW = cardPos.width;
            morphContainer.startH = cardPos.height;
            morphContainer.startRadius = cardPos.radius !== undefined ? cardPos.radius : 16;
        } else {
            morphContainer.startX = Math.round((clippingRoot.width - 280) / 2);
            morphContainer.startY = Math.round((clippingRoot.height - 200) / 2);
            morphContainer.startW = 280;
            morphContainer.startH = 200;
            morphContainer.startRadius = 16;
        }

        morphContainer.startColor = root.cardBaseColor;
        morphContainer.startBorderColor = Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.08);
        morphContainer.startBorderWidth = 1;

        // Apertura en frío instantánea a pantalla completa (sin animación de apertura)
        morphContainer.springEnabled = false;
        morphContainer.isVisible = true;
        morphContainer.isExpanded = true;
        morphContainer.scale = 1;
        morphContainer.opacity = 1;

        editorModal.morphReady = true;
        NotesService.openNote(noteData);

        // Habilitar física de resorte tras montar el modal para que el cierre anime fluidamente hacia la card
        Qt.callLater(function() {
            morphContainer.springEnabled = true;
            var refreshedPos = _findCurrentCardPosition(root.activeMorphSlug, true);
            if (refreshedPos) {
                morphContainer.startX = refreshedPos.x;
                morphContainer.startY = refreshedPos.y;
                morphContainer.startW = refreshedPos.width;
                morphContainer.startH = refreshedPos.height;
                morphContainer.startRadius = refreshedPos.radius !== undefined ? refreshedPos.radius : 16;
            }
        });
    }

    function handleIpcAction(act, tgt) {
        if (!act) return;
        if (act === "close") {
            if (morphContainer.isExpanded) {
                root.closeNoteWithMorph();
            } else {
                root.closeRequested();
            }
            return;
        }
        if (act === "open" || act === "openPath" || act === "edit") {
            if (!tgt || tgt === "") return;
            var isOutside = !ImportLogic.isInsideDir(tgt, NotesService.notesDir);
            var remoteLocked = (typeof Sys !== "undefined" && typeof Sys.isNoteBeingEditedElsewhere === "function") 
                ? Sys.isNoteBeingEditedElsewhere(tgt) : false;
            var shouldPreview = remoteLocked || ((act !== "edit") && isOutside && (NotesConfig.externalFileOpenMode !== "edit"));
            NotesService.openPath(tgt, shouldPreview, function(note) {
                if (note) {
                    if (note.isExternal) root.launchedForExternal = true;
                    if (morphContainer.isExpanded) {
                        NotesService.openNote(note);
                    } else {
                        root.openNoteImmediate(note);
                    }
                }
                Qt.callLater(function() {
                    root.isReadyToShow = true;
                });
            });
            return;
        }
        if (act === "preview" || act === "previewFile") {
            if (!tgt || tgt === "") return;
            NotesService.openPath(tgt, true, function(pNote) {
                if (pNote) {
                    if (pNote.isExternal) root.launchedForExternal = true;
                    if (morphContainer.isExpanded) {
                        NotesService.openNote(pNote);
                    } else {
                        root.openNoteImmediate(pNote);
                    }
                }
                Qt.callLater(function() {
                    root.isReadyToShow = true;
                });
            });
            return;
        }
        if (act === "new" || act === "createNote") {
            if (morphContainer.isExpanded) {
                root.closeNoteWithMorph();
            }
            var origin = fab.mapToItem(clippingRoot, 0, 0, fab.width, fab.height);
            root.createNoteWithMorph("text", origin);
            if (tgt) {
                NotesService.renameNote(NotesService.activeNote.slug, tgt);
            }
            Qt.callLater(function() {
                root.isReadyToShow = true;
            });
            return;
        }
        if (act === "find") {
            if (morphContainer.isExpanded) {
                root.closeNoteWithMorph();
            }
            if (searchInput) {
                searchInput.text = tgt || "";
                searchInput.forceActiveFocus();
                if (typeof NotesService !== "undefined") {
                    NotesService.searchQuery = tgt || "";
                }
            }
            Qt.callLater(function() {
                root.isReadyToShow = true;
            });
            return;
        }
        if (act === "reload") {
            if (typeof NotesService !== "undefined") {
                NotesService.reloadNotes();
            }
            return;
        }
    }

    function requestNewNote() {
        if (root._morphTransitioning || morphContainer.isVisible || NotesService.isEditing) return; // evita doble clic
        var origin = fab.mapToItem(clippingRoot, 0, 0, fab.width, fab.height);
        root.createNoteWithMorph("text", origin);
    }

    property var _pickedImportPaths: []

    function _resolvePortalPickerPath() {
        return (typeof Sys !== "undefined" && Sys.appExecutable) ? Sys.appExecutable : "criperto.notes";
    }

    function openImportFilePicker() {
        if (importFilePickerProc.running) return;
        root._pickedImportPaths = [];
        var filterSpecs = ImportLogic.getFilterSpecs(I18n.t);
        var cmd = [
            root._resolvePortalPickerPath(),
            "file-picker",
            "--title", I18n.t("notes.import.picker_title", "Importar notas")
        ];
        for (var i = 0; i < filterSpecs.length; i++) {
            cmd.push("--filter");
            cmd.push(filterSpecs[i]);
        }
        cmd.push("--multiple");
        importFilePickerProc.command = cmd;
        importFilePickerProc.running = true;
    }

    function importFilesFromUrls(urls) {
        if (!urls || urls.length === 0) return;
        var partitioned = ImportLogic.partitionDroppedUrls(urls);

        if (partitioned.normalUrls.length > 0) {
            NotesService.importDroppedUrls(partitioned.normalUrls);
        }

        var toConvert = (partitioned.convertItems && partitioned.convertItems.length > 0)
            ? partitioned.convertItems
            : (partitioned.docxItems || []);

        if (toConvert.length > 0) {
            root.pendingDocxItems = toConvert;
            var bName = ImportLogic.baseName(toConvert[0].localPath);
            if (toConvert.length > 1) {
                bName += " (+" + (toConvert.length - 1) + ")";
            }
            root.pendingDocxName = bName;

            var missing = NotesService.missingDepsFor(toConvert);
            if (missing.length > 0) {
                root.importCardState = "docx_missing_deps";
            } else {
                root.importCardState = "docx_confirm";
            }
        } else {
            root.importCardState = "hidden";
        }
    }

    function closeNoteWithMorph() {
        if (root._previewCloseAnimActive && !previewCloseAnim.running) {
            root._previewCloseAnimActive = false;
        }
        if (root._deleteAnimActive || root._previewCloseAnimActive) {
            return;
        }

        var curNote = NotesService.activeNote || root.morphingNoteData;
        var isExternalOrPreview = Boolean(
            (curNote && (curNote.isExternal || curNote.readOnly)) ||
            (editorModal && editorModal.isPreviewMode) ||
            (root.activeMorphSlug && root.activeMorphSlug.indexOf("__external__:") === 0)
        );

        if (isExternalOrPreview) {
            root.closeExternalPreview();
            return;
        }

        root.keyboardNavActive = false;
        root.keyboardSelectedSlug = "";
        if (editorModal && editorModal.loadedSlug) {
            root.activeMorphSlug = editorModal.loadedSlug;
        }
        var curSlug = root.activeMorphSlug || (editorModal.loadedSlug || "");
        if (NotesService.isUntouchedDraft && NotesService.isUntouchedDraft(curSlug)) {
            NotesService.deleteNote(curSlug);
            NotesService.clearDraft(curSlug);
        } else {
            if (editorModal.blockEditor && editorModal.blockEditor.activeBlockBid !== -1) {
                editorModal.blockEditor.confirmActiveBlock();
            }
            if (!NotesService.isPendingDelete(curSlug)) {
                editorModal.performSave();
                NotesService.flushPendingSave();
            }
        }

        // Actualizar la posición destino del cierre con la posición ACTUAL de la card
        // en el grid (puede haber cambiado si la lista se reordenó al abrir la nota o al redimensionar)
        if (root.activeMorphSlug !== "") {
            var foundPos = _findCurrentCardPosition(root.activeMorphSlug, true);
            if (foundPos) {
                morphContainer.startX = foundPos.x;
                morphContainer.startY = foundPos.y;
                morphContainer.startW = foundPos.width;
                morphContainer.startH = foundPos.height;
                morphContainer.startRadius = foundPos.radius !== undefined ? foundPos.radius : 16;
            } else {
                morphContainer.startX = Math.round((clippingRoot.width - 280) / 2);
                morphContainer.startY = Math.round((clippingRoot.height - 200) / 2);
                morphContainer.startW = 280;
                morphContainer.startH = 200;
                morphContainer.startRadius = 16;
            }
        }

        morphContainer.startColor = root.cardBaseColor;
        morphContainer.startBorderColor = Qt.hsva(Theme.text.hsvHue, Theme.text.hsvSaturation, Theme.text.hsvValue, 0.08);
        morphContainer.startBorderWidth = 1;
        morphContainer.springEnabled = true;

        if (!morphContainer.isExpanded) {
            morphContainer.isVisible = false;
            morphContainer.springEnabled = false;
            root.activeMorphSlug = "";
            root.morphingNoteData = null;
            root.isCardMorph = false;
            NotesService.closeNote();
            if (root.launchedForExternal && (NotesConfig.previewCloseAction !== "home")) {
                root.closeRequested();
            } else {
                root.launchedForExternal = false;
                if ((!NotesService.notes || NotesService.notes.length === 0) && !NotesService.loading) {
                    NotesService.refresh();
                }
            }
            return;
        }

        morphContainer.isExpanded = false;
        settleCloseTimer.restart();
    }

    function closeExternalPreview() {
        if (root._previewCloseAnimActive && !previewCloseAnim.running) {
            root._previewCloseAnimActive = false;
        }
        if (root._previewCloseAnimActive) return;
        if (NotesService.debug) console.log("[NotesContent - preview] Cerrando preview con animación invertida hacia arriba");
        root.keyboardNavActive = false;
        root.keyboardSelectedSlug = "";

        var useAnim = Theme.animationsEnabled && !GamemodeService.gamemodeActive && morphContainer.isExpanded;
        if (!useAnim) {
            morphContainer.springEnabled = false;
            morphContainer.isExpanded = false;
            morphContainer.isVisible = false;
            root.activeMorphSlug = "";
            root.morphingNoteData = null;
            root.isCardMorph = false;
            editorModal.clearClosedNote();
            NotesService.closeNote();
            var shouldCloseApp = (NotesConfig.previewCloseAction !== "home") && (root.launchedForExternal || (editorModal.noteData && editorModal.noteData.isExternal));
            if (shouldCloseApp) {
                root.closeRequested();
            } else {
                root.launchedForExternal = false;
                if ((!NotesService.notes || NotesService.notes.length === 0) && !NotesService.loading) {
                    NotesService.refresh();
                }
            }
            return;
        }

        var tgt = PreviewLogic.deleteMorphTarget(clippingRoot.width, clippingRoot.height,
            morphContainer.width, morphContainer.height);
        root._previewCloseScale = tgt.scale;
        root._previewCloseDy = -Math.abs(tgt.dy);
        root._previewCloseAnimActive = true;
        previewCloseAnim.restart();
    }

    // F18: cierre por borrado. La lista NO se toca hasta el final (la tarjeta
    // sigue en su lugar durante la animación); el único rebuild lo hace
    // closeNote() al terminar. Sin animaciones: mismo estado final directo.
    function closeNoteForDelete() {
        if (root._deleteAnimActive) return;
        var curKey = root.activeMorphSlug || (editorModal.loadedSlug || "");
        if (curKey === "") return;
        if (editorModal.blockEditor && editorModal.blockEditor.activeBlockBid !== -1) {
            editorModal.blockEditor.confirmActiveBlock();
        }
        root.keyboardNavActive = false;
        root.keyboardSelectedSlug = "";

        var useAnim = Theme.animationsEnabled && !GamemodeService.gamemodeActive && morphContainer.isExpanded;
        if (!useAnim) {
            morphContainer.springEnabled = false;
            morphContainer.isExpanded = false;
            morphContainer.isVisible = false;
            root.activeMorphSlug = "";
            root.morphingNoteData = null;
            root.isCardMorph = false;
            NotesService._rebuildPending = false;
            NotesService.closeNote();
            root.showUndoToast(curKey, NotesService.getNote(curKey) || NotesService.activeNote);
            return;
        }

        var tgt = PreviewLogic.deleteMorphTarget(clippingRoot.width, clippingRoot.height,
            morphContainer.width, morphContainer.height);
        root._delKey = curKey;
        root._delNote = NotesService.getNote(curKey) || NotesService.activeNote;
        root._delScale = tgt.scale;
        root._delDy = tgt.dy;
        root._deleteAnimActive = true;
        deleteAnim.restart();
    }

    function _dropHasImportable(drag) {
        if (!drag || !drag.hasUrls || !drag.urls) return false;
        for (var u = 0; u < drag.urls.length; u++) {
            var raw = (drag.urls[u] && drag.urls[u].toString) ? drag.urls[u].toString() : String(drag.urls[u]);
            var local = ImportLogic.decodeDropUrl(raw);
            if (!local) continue;
            if (ImportLogic.isImportable(local)) return true;
        }
        return false;
    }

    function _showImportSummary(s) {
        if (!s) return;
        // Silencio si fue un solo archivo que ya se abrió en el editor
        if (s.total === 1 && s.opened && (s.errors || 0) === 0 && (s.skipped || 0) === 0) return;
        var parts = [];
        if (s.copied > 0) parts.push(I18n.t("notes.import.copied", "Copiadas") + ": " + s.copied);
        if (s.moved > 0) parts.push(I18n.t("notes.import.moved", "Movidas") + ": " + s.moved);
        if (s.already > 0) parts.push(I18n.t("notes.import.already", "Ya está en tu carpeta") + ": " + s.already);
        if (s.skipped > 0) parts.push(I18n.t("notes.import.skipped", "Omitidas") + ": " + s.skipped);
        if (s.errors > 0) parts.push(I18n.t("notes.import.errored", "Con errores") + ": " + s.errors);
        var msg = parts.join(" · ");
        if (s.total === 1 && s.issueName) {
            msg = I18n.t("notes.import.failed", "No se pudo importar") + ": " + s.issueName;
            if (s.issueReason === "size") msg += " (" + I18n.t("notes.import.too_large", "Muy grande (máx. 5 MB)") + ")";
            else if (s.issueReason === "type") msg += " (" + I18n.t("notes.import.not_file", "No es un archivo regular") + ")";
        }
        if (s.srcKept > 0) msg += " (" + I18n.t("notes.import.kept_source", "Se conservó el original") + ")";
        if (!msg) return;
        importToast.showText(msg);
    }

    // Aviso de importación solo sin nota abierta (con blur+atenuación)
    readonly property bool importHintActive: (root.importCardState !== "hidden" || (importDropArea.hasImportable && NotesService.activeNote === null)) && NotesService.activeNote === null

    function _findCardInRegistry(slug) {
        if (!slug || !root._cardRegistry) return null;
        var card = root._cardRegistry[slug];
        if (card) return card;

        // Probar slug con extensiones comunes
        if (root._cardRegistry[slug + "\0md"]) return root._cardRegistry[slug + "\0md"];
        if (root._cardRegistry[slug + "\0txt"]) return root._cardRegistry[slug + "\0txt"];

        // Probar slug limpio si slug tiene \0 o extensión
        var clean = NotesService.slugOfKey ? NotesService.slugOfKey(slug) : slug.replace(/\0.*$/, "").replace(/\.(md|txt)$/, "");
        if (clean !== slug) {
            if (root._cardRegistry[clean]) return root._cardRegistry[clean];
            if (root._cardRegistry[clean + "\0md"]) return root._cardRegistry[clean + "\0md"];
            if (root._cardRegistry[clean + "\0txt"]) return root._cardRegistry[clean + "\0txt"];
        }

        // Búsqueda lineal como fallback si las keys difieren
        for (var k in root._cardRegistry) {
            var c = root._cardRegistry[k];
            if (!c) continue;
            var cKey = c.cardKey || "";
            var cSlug = c.noteData ? (c.noteData.slug || c.noteData.key || c.noteData.id || "") : "";
            if (cKey === slug || cSlug === slug || cKey === clean || cSlug === clean) {
                return c;
            }
            if (NotesService.slugOfKey) {
                if (NotesService.slugOfKey(cKey) === clean || NotesService.slugOfKey(cSlug) === clean) {
                    return c;
                }
            }
        }
        return null;
    }

    function _estimateCardPositionInGrid(slug) {
        if (!slug || !notesScroll) return null;
        var clean = NotesService.slugOfKey ? NotesService.slugOfKey(slug) : slug.replace(/\0.*$/, "").replace(/\.(md|txt)$/, "");

        var note = NotesService.getNote ? (NotesService.getNote(slug) || NotesService.getNote(clean)) : null;
        var isPinned = note ? !!note.pinned : false;

        var colsData = isPinned ? root.pinnedColumnsData : root.otherColumnsData;
        var targetCol = -1;
        var targetRow = -1;

        if (colsData && colsData.length > 0) {
            for (var c = 0; c < colsData.length; c++) {
                var colArr = colsData[c] || [];
                for (var r = 0; r < colArr.length; r++) {
                    var item = colArr[r];
                    if (!item) continue;
                    var k = item.key || item.slug || item.id || "";
                    var kClean = NotesService.slugOfKey ? NotesService.slugOfKey(k) : k.replace(/\0.*$/, "");
                    if (k === slug || k === clean || kClean === clean) {
                        targetCol = c;
                        targetRow = r;
                        break;
                    }
                }
                if (targetCol !== -1) break;
            }
        }

        if (targetCol === -1) {
            var altData = isPinned ? root.otherColumnsData : root.pinnedColumnsData;
            if (altData && altData.length > 0) {
                for (var c2 = 0; c2 < altData.length; c2++) {
                    var colArr2 = altData[c2] || [];
                    for (var r2 = 0; r2 < colArr2.length; r2++) {
                        var item2 = colArr2[r2];
                        if (!item2) continue;
                        var k2 = item2.key || item2.slug || item2.id || "";
                        var k2Clean = NotesService.slugOfKey ? NotesService.slugOfKey(k2) : k2.replace(/\0.*$/, "");
                        if (k2 === slug || k2 === clean || k2Clean === clean) {
                            targetCol = c2;
                            targetRow = r2;
                            isPinned = !isPinned;
                            break;
                        }
                    }
                    if (targetCol !== -1) break;
                }
            }
        }

        if (targetCol === -1) return null;

        var numCols = notesScroll.cols || 3;
        var colW = notesScroll.colWidth || 260;
        var colSpacing = 14;
        var cardSpacing = 14;
        var estCardH = 180;

        var targetRowItem = isPinned ? pinnedMasonryRow : otherMasonryRow;
        try {
            if (targetRowItem && typeof targetRowItem.mapToItem === "function") {
                var rowMapped = targetRowItem.mapToItem(clippingRoot, 0, 0);
                var estX = rowMapped.x + targetCol * (colW + colSpacing);
                var estY = rowMapped.y + targetRow * (estCardH + cardSpacing);

                if (notesScroll && typeof notesScroll.mapToItem === "function") {
                    var scrollMapped = notesScroll.mapToItem(clippingRoot, 0, 0);
                    var viewY = scrollMapped.y;
                    var viewH = notesScroll.height;
                    if (estY < viewY || estY + estCardH > viewY + viewH) {
                        var cardContentY = estY - rowMapped.y;
                        notesScroll.contentY = Math.max(0, cardContentY - 20);
                        rowMapped = targetRowItem.mapToItem(clippingRoot, 0, 0);
                        estY = rowMapped.y + targetRow * (estCardH + cardSpacing);
                    }
                }

                return {
                    x: Math.round(estX),
                    y: Math.round(estY),
                    width: Math.round(colW),
                    height: Math.round(estCardH),
                    radius: 16
                };
            }
        } catch (e) {
            if (NotesService.debug) console.warn("[NotesContent] Falló cálculo estimado de grid:", e);
        }
        return null;
    }

    // Busca la posición actual de la card con el slug dado en las columnas de masonry
    // Retorna { x, y, width, height, radius } relativo a clippingRoot, o null si no se encuentra.
    function _findCurrentCardPosition(slug, ensureVisible) {
        if (!slug) return null;
        var card = _findCardInRegistry(slug);
        if (card) {
            try {
                if (card.parent && typeof card.mapToItem === "function") {
                    if (ensureVisible !== false) {
                        _ensureCardVisible(card);
                    }
                    var mapped = card.mapToItem(clippingRoot, 0, 0, card.width, card.height);
                    if (NotesService.debug) console.log("[NotesContent] Posición actual de card", slug, "→", mapped.x, mapped.y, mapped.width, mapped.height);
                    return {
                        x: Math.round(mapped.x),
                        y: Math.round(mapped.y),
                        width: Math.round(mapped.width),
                        height: Math.round(mapped.height),
                        radius: 16
                    };
                }
            } catch (e) {
                if (root._cardRegistry && root._cardRegistry[slug] === card) {
                    delete root._cardRegistry[slug];
                }
            }
        }

        var estimated = _estimateCardPositionInGrid(slug);
        if (estimated) {
            if (NotesService.debug) console.log("[NotesContent] Posición estimada en grid para", slug, "→", estimated.x, estimated.y, estimated.width, estimated.height);
            return estimated;
        }

        if (NotesService.debug) console.log("[NotesContent] No se encontró card para slug:", slug, "— usando fallback centrado");
        return null;
    }


    Timer {
        id: settleCloseTimer
        interval: (Theme.animationsEnabled && !GamemodeService.gamemodeActive) ? 340 : 10
        repeat: false
        onTriggered: {
            if (NotesService.debug) console.log("[NotesContent - morph] Contracción completada, restaurando vista de tarjetas");
            morphContainer.isVisible = false;
            morphContainer.springEnabled = false;
            root.activeMorphSlug = "";
            root.morphingNoteData = null;
            root.isCardMorph = false;
            editorModal.clearClosedNote();
            NotesService.closeNote();
            if (root.launchedForExternal && (NotesConfig.previewCloseAction !== "home")) {
                root.closeRequested();
            } else {
                root.launchedForExternal = false;
                if ((!NotesService.notes || NotesService.notes.length === 0) && !NotesService.loading) {
                    NotesService.refresh();
                }
            }
        }
    }

    // Fin del morph de apertura → el editor construye los bloques
    Timer {
        id: morphOpenTimer
        interval: 420
        repeat: false
        onTriggered: {
            editorModal.morphReady = true;
        }
    }

    // F18: cierre por borrado hacia el toast. Solo transform (scale + este
    // Translate + opacity): la geometría bindeada no se toca, no hay relayout
    // por frame. El fin real (onFinished) dispara toast + rebuild único.
    ParallelAnimation {
        id: deleteAnim
        NumberAnimation { target: morphContainer; property: "scale"; to: root._delScale; duration: root.deleteAnimMs; easing.type: Easing.InOutCubic }
        NumberAnimation { target: deleteShift; property: "y"; to: root._delDy; duration: root.deleteAnimMs; easing.type: Easing.InOutCubic }
        SequentialAnimation {
            PauseAnimation { duration: root.deleteAnimMs * 0.6 }
            NumberAnimation { target: morphContainer; property: "opacity"; from: 1.0; to: 0.0; duration: root.deleteAnimMs * 0.4; easing.type: Easing.OutCubic }
        }
        onFinished: {
            root._deleteAnimActive = false;
            morphContainer.springEnabled = false;
            morphContainer.isExpanded = false;
            morphContainer.isVisible = false;
            morphContainer.scale = 1;
            morphContainer.opacity = 1;
            deleteShift.x = 0;
            deleteShift.y = 0;
            root.activeMorphSlug = "";
            root.morphingNoteData = null;
            root.isCardMorph = false;
            NotesService._rebuildPending = false;
            NotesService.closeNote();
            root.showUndoToast(root._delKey, root._delNote);
            root._delKey = "";
            root._delNote = null;
        }
    }

    // Cierre invertido de preview hacia arriba (animación idéntica a borrado pero hacia arriba)
    ParallelAnimation {
        id: previewCloseAnim
        NumberAnimation { target: morphContainer; property: "scale"; to: root._previewCloseScale; duration: root.deleteAnimMs; easing.type: Easing.InOutCubic }
        NumberAnimation { target: deleteShift; property: "y"; to: root._previewCloseDy; duration: root.deleteAnimMs; easing.type: Easing.InOutCubic }
        SequentialAnimation {
            PauseAnimation { duration: root.deleteAnimMs * 0.55 }
            NumberAnimation { target: morphContainer; property: "opacity"; from: 1.0; to: 0.0; duration: root.deleteAnimMs * 0.45; easing.type: Easing.OutCubic }
        }
        onFinished: {
            root._previewCloseAnimActive = false;
            morphContainer.springEnabled = false;
            morphContainer.isExpanded = false;
            morphContainer.isVisible = false;
            morphContainer.scale = 1;
            morphContainer.opacity = 1;
            deleteShift.x = 0;
            deleteShift.y = 0;
            root.activeMorphSlug = "";
            root.morphingNoteData = null;
            root.isCardMorph = false;
            var wasExternal = root.launchedForExternal || (editorModal.noteData && editorModal.noteData.isExternal);
            editorModal.clearClosedNote();
            NotesService.closeNote();
            var shouldCloseApp = (NotesConfig.previewCloseAction !== "home") && wasExternal;
            if (shouldCloseApp) {
                root.closeRequested();
            } else {
                root.launchedForExternal = false;
                if ((!NotesService.notes || NotesService.notes.length === 0) && !NotesService.loading) {
                    NotesService.refresh();
                }
            }
        }
    }

    Connections {
        target: NotesService
        function onNoteImported(parsed) {
            root.launchedForExternal = false;
            if (parsed) {
                root.activeMorphSlug = parsed.key || parsed.slug;
                root.morphingNoteData = parsed;
                root.isCardMorph = true;
                var foundPos = root._findCurrentCardPosition(root.activeMorphSlug, false);
                if (foundPos) {
                    morphContainer.startX = foundPos.x;
                    morphContainer.startY = foundPos.y;
                    morphContainer.startW = foundPos.width;
                    morphContainer.startH = foundPos.height;
                    morphContainer.startRadius = foundPos.radius !== undefined ? foundPos.radius : 16;
                } else {
                    morphContainer.startX = Math.round((clippingRoot.width - 280) / 2);
                    morphContainer.startY = Math.round((clippingRoot.height - 200) / 2);
                    morphContainer.startW = 280;
                    morphContainer.startH = 200;
                    morphContainer.startRadius = 16;
                }
            }
        }
        function onIsEditingChanged() {
            if (root._morphTransitioning || root._deleteAnimActive || root._previewCloseAnimActive) return;
            if (NotesService.isEditing && !morphContainer.isExpanded) {
                root.openNoteWithMorph(NotesService.activeNote, null);
            } else if (!NotesService.isEditing && morphContainer.isExpanded) {
                root.closeNoteWithMorph();
            }
        }
        // F26 (FLIP): First antes de reasignar, Last cuando el layout asentó.
        function onNotesAboutToChange() {
            root._flipSnapshot();
        }
        function onNotesRefreshed() {
            if (root._flipArmed) flipSettleTimer.restart();
            if (morphContainer.isExpanded && root.activeMorphSlug !== "") {
                var refreshedPos = root._findCurrentCardPosition(root.activeMorphSlug, false);
                if (refreshedPos) {
                    morphContainer.startX = refreshedPos.x;
                    morphContainer.startY = refreshedPos.y;
                    morphContainer.startW = refreshedPos.width;
                    morphContainer.startH = refreshedPos.height;
                    morphContainer.startRadius = refreshedPos.radius !== undefined ? refreshedPos.radius : 16;
                }
            }
        }
    }

    // Proceso para seleccionar archivos vía xdg-desktop-portal (qs-helper file-picker)
    Process {
        id: importFilePickerProc
        stdout: SplitParser {
            onRead: (line) => {
                var p = line.trim();
                if (p !== "") {
                    root._pickedImportPaths.push(p);
                }
            }
        }

        onExited: exitCode => {
            if (exitCode === 0 && root._pickedImportPaths.length > 0) {
                root.importFilesFromUrls(root._pickedImportPaths);
            }
            root._pickedImportPaths = [];
        }

        Component.onDestruction: {
            running = false;
        }
    }

    Component.onCompleted: {
        if (root.initialAction !== "" && !root._initialActionHandled) {
            root._initialActionHandled = true;
            Qt.callLater(function() {
                root.handleIpcAction(root.initialAction, root.initialTarget);
            });
        }
    }

    function handleRemoteEditLockClaimed(notePath, newOwnerPid) {
        if (NotesService.activeNote && NotesService.activeNote.filePath === notePath) {
            if (editorModal && !editorModal.isPreviewMode) {
                editorModal.performSave(null, true);
            }
            editorModal.remoteLocked = true;
            if (NotesService.activeNote) {
                NotesService.activeNote.readOnly = true;
            }
            editorModal.readOnly = true;
            importToast.showText(I18n.t("notes.toast.remote_editing_transferred", "Edición transferida a otra ventana (modo lectura activo)"));
        }
    }

    function handleRemoteNoteSaved(notePath) {
        if (NotesService.activeNote && NotesService.activeNote.filePath === notePath) {
            if (editorModal && editorModal.isPreviewMode) {
                importToast.showText(I18n.t("notes.toast.remote_note_updated", "Actualizado desde otra ventana"));
            }
        }
    }

    function handleRemoteNoteDeleted(notePath) {
        if (NotesService.activeNote && NotesService.activeNote.filePath === notePath) {
            if (morphContainer.isExpanded) {
                root.closeNoteWithMorph();
            } else {
                NotesService.closeNote();
            }
            importToast.showText(I18n.t("notes.toast.remote_note_deleted", "La nota fue eliminada en otra ventana"));
        }
        if (typeof NotesService.refresh === "function") {
            NotesService.refresh();
        }
    }

    Connections {
        target: NotesService
        function onActiveNoteChanged() {
            if (typeof Sys !== "undefined" && typeof Sys.updateInstanceStatus === "function") {
                Sys.updateInstanceStatus(NotesService.activeNote ? (NotesService.activeNote.filePath || "") : "", NotesService.isEditing);
            }
        }
        function onIsEditingChanged() {
            if (typeof Sys !== "undefined" && typeof Sys.updateInstanceStatus === "function") {
                Sys.updateInstanceStatus(NotesService.activeNote ? (NotesService.activeNote.filePath || "") : "", NotesService.isEditing);
            }
        }
    }

    Component.onDestruction: {
        root.commitUndoToast();
    }
}
