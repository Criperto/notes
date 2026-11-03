use std::fs;
use std::io::Write;
use std::os::unix::net::UnixStream;
use std::path::PathBuf;

fn get_config_path() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".config").join("notas").join("config.json")
}

fn has_quickshell_installed() -> bool {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    let h = PathBuf::from(home);
    h.join(".config").join("quickshell").join("config").join("general.conf").exists()
        || h.join(".config").join("quickshell").join("config").join("theme.conf").exists()
}

fn try_send_ipc(action: &str, target: &str) -> bool {
    let runtime_dir = std::env::var("XDG_RUNTIME_DIR").unwrap_or_else(|_| "/tmp".to_string());
    let sock_path = format!("{}/notas.sock", runtime_dir);

    if let Ok(mut stream) = UnixStream::connect(&sock_path) {
        let escaped_action = action.replace('\\', "\\\\").replace('"', "\\\"");
        let escaped_target = target.replace('\\', "\\\\").replace('"', "\\\"");
        let payload = format!("{{\"action\":\"{escaped_action}\",\"target\":\"{escaped_target}\"}}\n");
        if stream.write_all(payload.as_bytes()).is_ok() && stream.flush().is_ok() {
            return true;
        }
    }
    false
}

fn read_config_json() -> serde_json::Value {
    let p = get_config_path();
    if p.exists() {
        if let Ok(content) = fs::read_to_string(&p) {
            if let Ok(val) = serde_json::from_str::<serde_json::Value>(&content) {
                return val;
            }
        }
    }
    serde_json::json!({})
}

fn write_config_json(val: &serde_json::Value) -> Result<(), std::io::Error> {
    let p = get_config_path();
    if let Some(parent) = p.parent() {
        fs::create_dir_all(parent)?;
    }
    let content = serde_json::to_string_pretty(val)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e.to_string()))?;
    fs::write(&p, content)?;
    Ok(())
}

pub fn is_forced_no_sync() -> bool {
    if std::env::var("NOTAS_NO_SYNC").unwrap_or_default() == "1"
        || std::env::var("NOTAS_STANDALONE").unwrap_or_default() == "1"
    {
        return true;
    }
    let root = read_config_json();
    if let Some(v) = root.get("noSync").and_then(|v| v.as_bool()) {
        if v { return true; }
    }
    if let Some(v) = root.get("no_sync").and_then(|v| v.as_bool()) {
        if v { return true; }
    }
    if let Some(v) = root.get("sync").and_then(|v| v.as_bool()) {
        if !v { return true; }
    }
    if let Some(v) = root.get("syncWithQuickshell").and_then(|v| v.as_bool()) {
        if !v { return true; }
    }

    let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
    let extra_files = [
        format!("{}/.config/notas/config.conf", home),
        format!("{}/.config/notas/notas.conf", home),
        format!("{}/.config/notas/config.toml", home),
        format!("{}/.config/notas/notas.toml", home),
        format!("{}/.config/quickshell/config/notes.conf", home),
    ];
    for ef in extra_files {
        if let Ok(content) = fs::read_to_string(&ef) {
            for line in content.lines() {
                let trimmed = line.trim();
                if trimmed.is_empty() || trimmed.starts_with('#') || trimmed.starts_with(';') {
                    continue;
                }
                if let Some((k, v)) = trimmed.split_once('=') {
                    let k = k.trim().to_lowercase();
                    let v = v.trim().to_lowercase();
                    if (k == "nosync" || k == "no_sync") && (v == "true" || v == "1") {
                        return true;
                    }
                    if (k == "sync" || k == "syncwithquickshell") && (v == "false" || v == "0") {
                        return true;
                    }
                }
            }
        }
    }
    false
}

fn get_sync_state() -> bool {
    if is_forced_no_sync() {
        return false;
    }
    let root = read_config_json();
    root.get("syncWithQuickshell")
        .and_then(|v| v.as_bool())
        .unwrap_or(true)
}

fn set_sync_state(enabled: bool) {
    let mut root = read_config_json();
    if !root.is_object() {
        root = serde_json::json!({});
    }
    root["syncWithQuickshell"] = serde_json::Value::Bool(enabled);
    if let Some(obj) = root.as_object_mut() {
        if enabled {
            obj.remove("noSync");
            obj.remove("no_sync");
            if let Some(s) = obj.get_mut("sync") {
                *s = serde_json::Value::Bool(true);
            }
        } else {
            obj.insert("noSync".to_string(), serde_json::Value::Bool(true));
        }
    }

    if let Err(e) = write_config_json(&root) {
        eprintln!("❌ Error al guardar configuración en {:?}: {}", get_config_path(), e);
        std::process::exit(1);
    }

    let ipc_target = if enabled { "true" } else { "false" };
    let ipc_sent = try_send_ipc("sync", ipc_target);

    if enabled {
        println!("✓ Sincronización con Quickshell ACTIVADA.");
        println!("  • Colores, desenfoque, animaciones, scrollbars, opacidad y tipografía sincronizados automáticamente.");
        println!("  • La pestaña 'Apariencia' se oculta de Notas.");
    } else {
        println!("✓ Sincronización con Quickshell DESACTIVADA (Modo Standalone activado para testing).");
        println!("  • La pestaña 'Apariencia' y los controles manuales ahora están habilitados en Notas.");
    }

    if ipc_sent {
        println!("  • Instancia activa de Notas notificada en tiempo real vía IPC.");
    }
}

pub fn run(args: &[String]) {
    let cmd = args.first().map(|s| s.as_str()).unwrap_or("status");

    match cmd {
        "status" => {
            let forced = is_forced_no_sync();
            let active = get_sync_state();
            let qs_found = has_quickshell_installed();
            let config_path = get_config_path();

            let sync_status_str = if active {
                "ACTIVADA"
            } else if forced {
                "DESACTIVADA (Config noSync / .conf)"
            } else {
                "DESACTIVADA (Modo Standalone)"
            };

            println!("\n╭─────────────────────────────────────────────────────────────────────────────╮");
            println!("│ 🔄 Estado de Sincronización con Quickshell (dev.criperto.Notas)             │");
            println!("├─────────────────────────────────────────────────────────────────────────────┤");
            println!(
                "│ • Sincronización con Quickshell : {:<43} │",
                sync_status_str
            );
            println!(
                "│ • Pestaña 'Apariencia' en UI    : {:<43} │",
                if active { "OCULTA (Gestionada por Quickshell)" } else { "VISIBLE (Controles manuales habilitados)" }
            );
            println!("│ • Ajustes sincronizados         : Colores, blur, animaciones, scrollbars,   │");
            println!("│                                   opacidad y escala tipográfica             │");
            println!(
                "│ • Quickshell detectado          : {:<43} │",
                if qs_found { "Sí (~/.config/quickshell)" } else { "No detectado" }
            );
            println!("│ • Archivo de configuración      : {:<43} │", config_path.to_string_lossy());
            println!("╰─────────────────────────────────────────────────────────────────────────────╯");
            println!("\nUso:");
            println!("  notas sync off | disable   Desactiva sincronización (Modo Standalone para testing)");
            println!("  notas sync on  | enable    Activa sincronización automática con Quickshell");
            println!("  notas sync toggle          Alterna entre activado y desactivado");
            println!("  notas --no-sync            Ejecuta puntualmente sin sincronización\n");
        }
        "off" | "disable" | "false" | "0" => {
            set_sync_state(false);
        }
        "on" | "enable" | "true" | "1" => {
            set_sync_state(true);
        }
        "toggle" => {
            let current = get_sync_state();
            set_sync_state(!current);
        }
        other => {
            eprintln!("Comando desconocido 'notas sync {}'. Comandos válidos: status, off, on, toggle", other);
            std::process::exit(1);
        }
    }
}
