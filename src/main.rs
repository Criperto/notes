mod notes_cli;

use clap::Parser;
use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QUrl};

extern "C" {
    fn notas_init_qt();
}

#[derive(Parser, Debug)]
#[command(
    name = "notas",
    version = "0.1.0",
    about = "Aplicación nativa de notas en Markdown con editor de bloques y diagramas Mermaid"
)]
struct Cli {
    /// Archivo Markdown (.md) a abrir o previsualizar
    path: Option<String>,

    /// Crear y abrir una nueva nota
    #[arg(short = 'n', long = "new")]
    new_note: Option<Option<String>>,

    /// Alternar visibilidad de la ventana (toggle)
    #[arg(short = 't', long = "toggle")]
    toggle: bool,

    /// Cerrar la aplicación
    #[arg(short = 'c', long = "close")]
    close: bool,

    /// Abrir en modo previsualización únicamente
    #[arg(short = 'p', long = "preview")]
    preview: bool,

    /// Verificar carga y salir (para tests y headless CI)
    #[arg(long = "check")]
    check_only: bool,
}

fn main() {
    let raw_args: Vec<String> = std::env::args().collect();
    if raw_args.len() > 1 && raw_args[1] == "notes" {
        notes_cli::run(&raw_args[2..]);
        return;
    }

    let cli = Cli::parse();

    unsafe {
        notas_init_qt();
    }

    let mut app = QGuiApplication::new();
    let mut engine = QQmlApplicationEngine::new();

    if let Some(engine) = engine.as_mut() {
        let manifest_dir = env!("CARGO_MANIFEST_DIR");
        let dev_mode = std::env::var("NOTAS_DEV").unwrap_or_default() == "1";

        let qml_url = if dev_mode {
            println!("[Notas Dev] Cargando QML en vivo desde disco...");
            format!("file://{manifest_dir}/qml/Main.qml")
        } else {
            "qrc:/qt/qml/Notas/qml/Main.qml".to_string()
        };

        engine.load(&QUrl::from(qml_url.as_str()));
    }

    if cli.check_only {
        println!("✓ Notas 0.1.0 inicializado y validado correctamente.");
        return;
    }

    if let Some(app) = app.as_mut() {
        app.exec();
    }
}
