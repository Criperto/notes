mod cli_ops;
mod notes_cli;
mod spell_cli;
mod file_picker_cli;
mod sync_cli;
mod history_cli;
mod math_cli;
mod clipper_cli;
pub mod instance_hub;
pub mod diff_core;
pub mod lang_detect;

use clap::Parser;
use cxx_qt_lib::{QGuiApplication, QQmlApplicationEngine, QUrl};
use std::path::Path;

extern "C" {
    fn notas_init_qt();
}

#[derive(Parser, Debug)]
#[command(
    name = "criperto-notes",
    version = env!("CARGO_PKG_VERSION"),
    about = "Aplicación nativa de notas en Markdown con editor de bloques y diagramas Mermaid"
)]
struct Cli {
    /// Archivo Markdown (.md) o carpeta con nota a abrir o previsualizar
    path: Option<String>,

    /// Crear y abrir una nueva nota
    #[arg(short = 'n', long = "new")]
    new_note: Option<Option<String>>,

    /// Alternar visibilidad de la ventana (toggle)
    #[arg(short = 't', long = "toggle")]
    toggle: bool,

    /// Abrir una nueva ventana independiente
    #[arg(short = 'w', long = "new-window")]
    new_window: bool,

    /// Cerrar la aplicación
    #[arg(short = 'c', long = "close")]
    close: bool,

    /// Abrir en modo previsualización únicamente
    #[arg(short = 'p', long = "preview")]
    preview: bool,

    /// Forzar apertura en modo edición directa
    #[arg(short = 'e', long = "edit")]
    edit: bool,

    /// Buscar notas por texto (modo headless sin abrir GUI)
    #[arg(short = 's', long = "search")]
    search: Option<String>,

    /// Filtrar búsqueda por etiqueta (usado con --search)
    #[arg(long = "tag")]
    tag: Option<String>,

    /// Límite de resultados de búsqueda
    #[arg(long = "limit", default_value = "20")]
    limit: usize,

    /// Mostrar solo rutas de archivos en búsqueda
    #[arg(long = "paths")]
    paths: bool,

    /// Salida en formato JSON estructurado
    #[arg(long = "json")]
    json: bool,

    /// Abrir la aplicación con el buscador del inicio relleno
    #[arg(short = 'f', long = "find")]
    find: Option<String>,

    /// Agregar texto al final de una nota (usar '-' para leer de stdin)
    #[arg(short = 'a', long = "append")]
    append: Option<String>,

    /// Nota de destino para --append o --clip (por defecto: 'inbox')
    #[arg(long = "to")]
    to_note: Option<String>,

    /// Anteponer encabezado con fecha y hora al agregar
    #[arg(long = "stamp")]
    stamp: bool,

    /// Crear nota o agregar a --to desde el contenido del portapapeles
    #[arg(long = "clip")]
    clip: bool,

    /// Imprimir la ruta absoluta del archivo Markdown de una nota
    #[arg(long = "path-of")]
    path_of: Option<String>,

    /// Operaciones de historial de versiones (snapshot, list, show, restore, purge, move)
    #[arg(long = "history", num_args = 1..)]
    history: Option<Vec<String>>,

    /// Renderizar fórmula LaTeX a SVG (modo headless)
    #[arg(long = "math", num_args = 1..)]
    math: Option<Vec<String>>,

    /// Desactivar sincronización con Quickshell (modo standalone para testing)
    #[arg(long = "no-sync", alias = "standalone")]
    no_sync: bool,

    /// Forzar o configurar controles de ventana CSD (- [] X): 'always', 'never', 'auto' (alias rápido: --csd)
    #[arg(long = "window-controls", alias = "csd", num_args = 0..=1, default_missing_value = "always")]
    window_controls: Option<String>,

    /// Posición de controles de ventana CSD ('left', 'right', 'auto')
    #[arg(long = "window-controls-side", alias = "csd-side")]
    window_controls_side: Option<String>,

    /// Atajo para forzar controles de ventana CSD a la izquierda
    #[arg(long = "csd-left")]
    csd_left: bool,

    /// Atajo para forzar controles de ventana CSD a la derecha
    #[arg(long = "csd-right")]
    csd_right: bool,

    /// Verificar carga y salir (para tests y headless CI)
    #[arg(long = "check")]
    check_only: bool,
}

fn decode_percent(s: &str) -> String {
    let mut bytes = Vec::new();
    let mut iter = s.as_bytes().iter();
    while let Some(&b) = iter.next() {
        if b == b'%' {
            if let (Some(&h1), Some(&h2)) = (iter.next(), iter.next()) {
                let hex = [h1, h2];
                if let Ok(val) = u8::from_str_radix(std::str::from_utf8(&hex).unwrap_or(""), 16) {
                    bytes.push(val);
                    continue;
                }
            }
        }
        bytes.push(b);
    }
    String::from_utf8_lossy(&bytes).into_owned()
}

fn resolve_target_path(path_str: &str) -> String {
    let clean = if let Some(stripped) = path_str.strip_prefix("file://localhost/") {
        decode_percent(stripped)
    } else if let Some(stripped) = path_str.strip_prefix("file://") {
        decode_percent(stripped)
    } else {
        path_str.to_string()
    };

    let expanded = if clean.starts_with("~/") {
        if let Ok(home) = std::env::var("HOME") {
            format!("{}{}", home, &clean[1..])
        } else {
            clean
        }
    } else {
        clean
    };

    let p = Path::new(&expanded);
    let abs_p = if p.is_relative() {
        match std::env::current_dir() {
            Ok(cwd) => cwd.join(p),
            Err(_) => p.to_path_buf(),
        }
    } else {
        p.to_path_buf()
    };

    if abs_p.is_dir() {
        let dir_name = abs_p.file_name().and_then(|n| n.to_str()).unwrap_or("");
        // 1. Check <dir>/<dirname>.md
        let note_named = abs_p.join(format!("{}.md", dir_name));
        if note_named.is_file() {
            return note_named.to_string_lossy().to_string();
        }
        // 2. Check <dir>/index.md
        let index_md = abs_p.join("index.md");
        if index_md.is_file() {
            return index_md.to_string_lossy().to_string();
        }
        // 3. Check <dir>/README.md
        let readme_md = abs_p.join("README.md");
        if readme_md.is_file() {
            return readme_md.to_string_lossy().to_string();
        }
        // 4. Any .md file directly in the folder
        if let Ok(entries) = std::fs::read_dir(&abs_p) {
            let mut md_files = Vec::new();
            for entry in entries.flatten() {
                let ep = entry.path();
                if ep.is_file() && ep.extension().and_then(|e| e.to_str()) == Some("md") {
                    md_files.push(ep);
                }
            }
            md_files.sort();
            if let Some(first_md) = md_files.first() {
                return first_md.to_string_lossy().to_string();
            }
        }
        abs_p.to_string_lossy().to_string()
    } else {
        abs_p.to_string_lossy().to_string()
    }
}

pub fn try_send_ipc(action: &str, target: &str) -> bool {
    instance_hub::send_to_focused_instance(action, target)
}

fn main() {
    let raw_args: Vec<String> = std::env::args().collect();
    if raw_args.len() > 1 {
        match raw_args[1].as_str() {
            "notes" => {
                notes_cli::run(&raw_args[2..]);
                return;
            }
            "spell" => {
                spell_cli::run(&raw_args[2..]);
                return;
            }
            "file-picker" => {
                file_picker_cli::run(&raw_args[2..]);
                return;
            }
            "sync" => {
                sync_cli::run(&raw_args[2..]);
                return;
            }
            "history" => {
                match history_cli::handle_history_command(&raw_args[2..]) {
                    Ok(msg) => {
                        if !msg.is_empty() {
                            println!("{}", msg);
                        }
                        return;
                    }
                    Err(e) => {
                        eprintln!("Error en historial: {}", e);
                        std::process::exit(1);
                    }
                }
            }
            "math" => {
                math_cli::run(&raw_args[2..]);
                return;
            }
            "clip" | "webclip" => {
                clipper_cli::run(&raw_args[2..]);
                return;
            }
            _ => {}
        }
    }

    let cli = Cli::parse();

    // ── Despacho de operaciones headless en Rust puro (sin inicializar Qt) ───
    if let Some(ref q) = cli.search {
        cli_ops::cmd_search(q, cli.tag.as_deref(), cli.limit, cli.paths, cli.json);
        return;
    }

    if let Some(ref note_q) = cli.path_of {
        cli_ops::cmd_path_of(note_q);
        return;
    }

    if let Some(ref text) = cli.append {
        let to = cli.to_note.as_deref().unwrap_or("inbox");
        cli_ops::cmd_append(text, to, cli.stamp);
        return;
    }

    let mut clip_target: Option<String> = None;
    if cli.clip {
        if let Some(created_path) = cli_ops::cmd_clip(cli.to_note.as_deref(), cli.stamp) {
            let instances = instance_hub::list_active_instances();
            if let Some(idle_inst) = instances.iter().find(|i| !i.is_editing) {
                if instance_hub::send_ipc_to_instance(&idle_inst.sock_path(), "open", &created_path) {
                    return;
                }
            }
            clip_target = Some(created_path);
        } else {
            return;
        }
    }

    if let Some(ref h_args) = cli.history {
        match history_cli::handle_history_command(h_args) {
            Ok(msg) => {
                if !msg.is_empty() {
                    println!("{}", msg);
                }
                return;
            }
            Err(e) => {
                eprintln!("Error en historial: {}", e);
                std::process::exit(1);
            }
        }
    }

    if let Some(ref m_args) = cli.math {
        math_cli::run(m_args);
        return;
    }

    let (mut action, target) = if let Some(ref find_q) = cli.find {
        ("find".to_string(), find_q.clone())
    } else if cli.close {
        ("close".to_string(), String::new())
    } else if cli.toggle {
        ("toggle".to_string(), String::new())
    } else if let Some(ref new_val) = cli.new_note {
        ("new".to_string(), new_val.clone().unwrap_or_default())
    } else if let Some(ref p) = cli.path {
        let resolved = resolve_target_path(p);
        let act = if cli.preview {
            "preview"
        } else if cli.edit {
            "edit"
        } else {
            "open"
        };
        (act.to_string(), resolved)
    } else if let Some(ref cp) = clip_target {
        ("open".to_string(), cp.clone())
    } else {
        ("raise".to_string(), String::new())
    };

    if !cli.check_only && !cli.new_window && !cli.clip {
        let instances = instance_hub::list_active_instances();
        if !instances.is_empty() {
            if cli.close {
                instance_hub::broadcast_to_all("close", "", None);
                return;
            }
            if cli.toggle {
                let _ = instance_hub::send_to_focused_instance("toggle", "");
                return;
            }
            if let Some(ref find_q) = cli.find {
                if let Some(idle_inst) = instances.iter().find(|i| !i.is_editing) {
                    if instance_hub::send_ipc_to_instance(&idle_inst.sock_path(), "find", find_q) {
                        return;
                    }
                }
            }
            if cli.path.is_some() {
                // Si la instancia con foco NO está editando otra nota, abrir allí
                if let Some(focused) = instances.first() {
                    if !focused.is_editing {
                        if instance_hub::send_ipc_to_instance(&focused.sock_path(), &action, &target) {
                            return;
                        }
                    }
                }
                // Si la instancia enfocada SÍ está editando otra nota, no interrumpirla:
                // Se procede a abrir una nueva ventana en modo preview (salvo si se pidió --edit explícito)
                if !cli.edit {
                    action = "preview".to_string();
                }
            } else if cli.new_note.is_some() {
                if let Some(idle_inst) = instances.iter().find(|i| !i.is_editing) {
                    if instance_hub::send_ipc_to_instance(&idle_inst.sock_path(), "new", &target) {
                        return;
                    }
                }
            } else if action == "raise" {
                if let Some(idle_inst) = instances.iter().find(|i| !i.is_editing) {
                    if instance_hub::send_ipc_to_instance(&idle_inst.sock_path(), "raise", "") {
                        return;
                    }
                }
            }
        }
    }

    if cli.close {
        return;
    }

    if cli.no_sync || sync_cli::is_forced_no_sync() {
        std::env::set_var("NOTAS_NO_SYNC", "1");
    }

    if let Some(ref wc) = cli.window_controls {
        std::env::set_var("NOTAS_WINDOW_CONTROLS", wc);
    }

    if cli.csd_left {
        std::env::set_var("NOTAS_WINDOW_CONTROLS_SIDE", "left");
    } else if cli.csd_right {
        std::env::set_var("NOTAS_WINDOW_CONTROLS_SIDE", "right");
    } else if let Some(ref wcs) = cli.window_controls_side {
        std::env::set_var("NOTAS_WINDOW_CONTROLS_SIDE", wcs);
    }

    std::env::set_var("NOTAS_APP_VERSION", env!("CARGO_PKG_VERSION"));
    std::env::set_var("NOTAS_INITIAL_ACTION", &action);
    std::env::set_var("NOTAS_INITIAL_TARGET", &target);

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
        println!("✓ Notas {} inicializado y validado correctamente.", env!("CARGO_PKG_VERSION"));
        return;
    }

    if let Some(app) = app.as_mut() {
        app.exec();
    }
}
