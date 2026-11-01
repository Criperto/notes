use cxx_qt_build::{CxxQtBuilder, QmlFile, QmlModule};
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
    resources.push("qml/I18nCatalogs.js".to_string());

    let module = QmlModule::new("Notas")
        .qml_file("qml/Main.qml")
        .qml_file(QmlFile::from("qml/Theme.qml").singleton(true))
        .qml_file(QmlFile::from("qml/I18n.qml").singleton(true));

    CxxQtBuilder::new_qml_module(module)
        .qt_module("Gui")
        .qt_module("Quick")
        .qt_module("QuickControls2")
        .qrc_resources(resources)
        .cpp_file("src/cpp_init.cpp")
        .build();
}
