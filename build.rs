use cxx_qt_build::{CppFile, CxxQtBuilder, QmlFile, QmlModule};
use std::fs;

fn main() {
    let mut resources = Vec::new();
    if let Ok(entries) = fs::read_dir("assets/icons") {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|s| s.to_str()) == Some("svg") {
                resources.push(path.to_string_lossy().into_owned());
            }
        }
    }

    if let Ok(entries) = fs::read_dir("qml") {
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|s| s.to_str()) == Some("js") {
                resources.push(path.to_string_lossy().into_owned());
            }
        }
    }

    let singletons = [
        "qml/Theme.qml",
        "qml/I18n.qml",
        "qml/NotesConfig.qml",
        "qml/Quickshell.qml",
        "qml/NotesService.qml",
        "qml/SpellService.qml",
        "qml/SpellConfig.qml",
        "qml/EditorMetrics.qml",
        "qml/GamemodeService.qml",
        "qml/HyprlandConfig.qml",
    ];

    let components = [
        "qml/Main.qml",
        "qml/NotesContent.qml",
        "qml/NoteCard.qml",
        "qml/MorphingFab.qml",
        "qml/SlidingLabel.qml",
        "qml/NoteEditorModal.qml",
        "qml/ContextMenu.qml",
        "qml/NotesSettingsModal.qml",
        "qml/EditorToolTip.qml",
        "qml/ToolbarButton.qml",
        "qml/EditorTooltipLayer.qml",
        "qml/CustomTextCursor.qml",
        "qml/CustomScrollBar.qml",
        "qml/ClippingRectangle.qml",
        "qml/SettingsTextField.qml",
        "qml/SlashMenu.qml",
        "qml/BlockEditor.qml",
        "qml/BlockParagraph.qml",
        "qml/BlockHeading.qml",
        "qml/BlockQuote.qml",
        "qml/BlockHr.qml",
        "qml/BlockCode.qml",
        "qml/BlockList.qml",
        "qml/BlockTable.qml",
        "qml/BlockImage.qml",
        "qml/BlockMermaid.qml",
        "qml/MermaidView.qml",
        "qml/BlockRaw.qml",
        "qml/SpellOverlay.qml",
        "qml/DiffView.qml",
        "qml/HistoryPanel.qml",
    ];

    let mut module = QmlModule::new("Notas");
    for s in singletons {
        module = module.qml_file(QmlFile::from(s).singleton(true));
    }
    for c in components {
        module = module.qml_file(c);
    }

    CxxQtBuilder::new_qml_module(module)
        .qt_module("Gui")
        .qt_module("Qml")
        .qt_module("Quick")
        .qt_module("QuickControls2")
        .qt_module("Network")
        .qrc_resources(resources)
        .cpp_file(CppFile::from("src/native/native_bridge.h").moc(true))
        .cpp_file("src/native/native_bridge.cpp")
        .cpp_file("src/cpp_init.cpp")
        .build();
}
