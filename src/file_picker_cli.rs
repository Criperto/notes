use std::collections::HashMap;
use std::process;
use std::time::Duration;
use zbus::blocking::Connection;
use zbus::zvariant::{Array, ObjectPath, OwnedValue, Signature, StructureBuilder, Value};

fn parse_filter_spec(spec: &str) -> (String, Vec<String>) {
    if let Some((label, patterns_str)) = spec.split_once(':') {
        let label = label.trim().to_string();
        let mut patterns = Vec::new();
        for p in patterns_str.split(|c| c == ':' || c == ';' || c == ',') {
            let trimmed = p.trim();
            if !trimmed.is_empty() {
                patterns.push(trimmed.to_string());
            }
        }
        if patterns.is_empty() {
            patterns.push("*".to_string());
        }
        (label, patterns)
    } else {
        let mut patterns = Vec::new();
        for p in spec.split(|c| c == ';' || c == ',' || c == ' ') {
            let trimmed = p.trim();
            if !trimmed.is_empty() {
                patterns.push(trimmed.to_string());
            }
        }
        if patterns.is_empty() {
            patterns.push("*".to_string());
        }
        let label = format!("Archivos ({})", patterns.join(", "));
        (label, patterns)
    }
}

pub fn run(args: &[String]) {
    let mut title = "Seleccionar archivo".to_string();
    let mut accept_label = "Elegir".to_string();
    let mut multiple = false;
    let mut directory = false;
    let mut save = false;
    let mut current_name: Option<String> = None;
    let mut filters: Vec<String> = Vec::new();

    let mut i = 0;
    while i < args.len() {
        let a = &args[i];
        if a == "--title" && i + 1 < args.len() {
            title = args[i + 1].clone();
            i += 2;
        } else if a == "--accept-label" && i + 1 < args.len() {
            accept_label = args[i + 1].clone();
            i += 2;
        } else if a == "--filter" && i + 1 < args.len() {
            filters.push(args[i + 1].clone());
            i += 2;
        } else if a == "--current-name" && i + 1 < args.len() {
            current_name = Some(args[i + 1].clone());
            i += 2;
        } else if a == "--multiple" {
            multiple = true;
            i += 1;
        } else if a == "--directory" {
            directory = true;
            i += 1;
        } else if a == "--save" {
            save = true;
            i += 1;
        } else if !a.starts_with("--") && i == 0 {
            title = a.clone();
            i += 1;
        } else {
            i += 1;
        }
    }

    let conn = match Connection::session() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Error conectando a sesión D-Bus: {}", e);
            return;
        }
    };

    let token = format!(
        "notas_{}_{}",
        process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0)
    );
    let unique_name = conn.unique_name().map(|n| n.as_str()).unwrap_or("");
    let sender_token = unique_name.trim_start_matches(':').replace('.', "_");
    let request_path = format!("/org/freedesktop/portal/desktop/request/{}/{}", sender_token, token);

    let mut options: HashMap<&str, Value> = HashMap::new();
    options.insert("handle_token", Value::from(token.as_str()));
    options.insert("accept_label", Value::from(accept_label.as_str()));
    if multiple {
        options.insert("multiple", Value::from(true));
    }
    if directory {
        options.insert("directory", Value::from(true));
    }
    if let Some(ref cname) = current_name {
        options.insert("current_name", Value::from(cname.as_str()));
    }

    if !filters.is_empty() {
        let sig_filters = Signature::try_from("(sa(us))").unwrap();
        let sig_pattern = Signature::try_from("(us)").unwrap();
        let mut filters_array = Array::new(&sig_filters);
        for f in &filters {
            let (label, patterns) = parse_filter_spec(f);
            let mut pattern_array = Array::new(&sig_pattern);
            for pat in patterns {
                let rule = StructureBuilder::new()
                    .append_field(Value::U32(0))
                    .append_field(Value::from(pat))
                    .build();
                if let Ok(st) = rule {
                    let _ = pattern_array.append(Value::Structure(st));
                }
            }

            let filter_struct = StructureBuilder::new()
                .append_field(Value::from(label))
                .append_field(Value::Array(pattern_array))
                .build();

            if let Ok(st) = filter_struct {
                let _ = filters_array.append(Value::Structure(st));
            }
        }
        options.insert("filters", Value::Array(filters_array));
    }

    let method = if directory {
        "OpenFile"
    } else if save {
        "SaveFile"
    } else {
        "OpenFile"
    };

    let parent_window = "";
    let call_args = (parent_window, title.as_str(), options);

    let pre_rule = format!(
        "type='signal',sender='org.freedesktop.portal.Desktop',interface='org.freedesktop.portal.Request',member='Response',path='{}'",
        request_path
    );
    if let Err(e) = conn.call_method(
        Some("org.freedesktop.DBus"),
        "/org/freedesktop/DBus",
        Some("org.freedesktop.DBus"),
        "AddMatch",
        &(pre_rule.as_str(),),
    ) {
        eprintln!("Error registrando AddMatch preventivo en D-Bus: {}", e);
    }

    let reply_msg = conn.call_method(
        Some("org.freedesktop.portal.Desktop"),
        "/org/freedesktop/portal/desktop",
        Some("org.freedesktop.portal.FileChooser"),
        method,
        &call_args,
    );

    let actual_path = match reply_msg {
        Ok(m) => match m.body().deserialize::<ObjectPath<'_>>() {
            Ok(p) => p.to_string(),
            Err(_) => request_path.clone(),
        },
        Err(e) => {
            eprintln!("Error al invocar FileChooser del portal ({}): {}", method, e);
            process::exit(1);
        }
    };

    if actual_path != request_path {
        let rule = format!(
            "type='signal',sender='org.freedesktop.portal.Desktop',interface='org.freedesktop.portal.Request',member='Response',path='{}'",
            actual_path
        );
        if let Err(e) = conn.call_method(
            Some("org.freedesktop.DBus"),
            "/org/freedesktop/DBus",
            Some("org.freedesktop.DBus"),
            "AddMatch",
            &(rule.as_str(),),
        ) {
            eprintln!("Error registrando AddMatch en D-Bus: {}", e);
        }
    }

    let timeout = Duration::from_secs(300);
    let start = std::time::Instant::now();

    for msg in zbus::blocking::MessageIterator::from(&conn) {
        if start.elapsed() > timeout {
            break;
        }
        if let Ok(m) = msg {
            let header = m.header();
            if let Some(member) = header.member() {
                if member.as_str() == "Response" {
                    if let Some(path) = header.path() {
                        if path.as_str() == actual_path {
                            if let Ok((resp_code, results)) =
                                m.body().deserialize::<(u32, HashMap<String, OwnedValue>)>()
                            {
                                if resp_code == 0 {
                                    if let Some(uris_val) = results.get("uris") {
                                        if let Value::Array(arr) = &**uris_val {
                                            for v in arr.iter() {
                                                if let Value::Str(s) = v {
                                                    let uri = s.as_str();
                                                    let p = if let Some(rest) = uri.strip_prefix("file://") {
                                                        urlencoding_decode(rest)
                                                    } else {
                                                        uri.to_string()
                                                    };
                                                    println!("{}", p);
                                                }
                                            }
                                        }
                                    }
                                }
                                break;
                            }
                        }
                    }
                }
            }
        }
    }
}

fn urlencoding_decode(s: &str) -> String {
    let mut bytes = Vec::new();
    let in_bytes = s.as_bytes();
    let mut i = 0;
    while i < in_bytes.len() {
        if in_bytes[i] == b'%' && i + 2 < in_bytes.len() {
            if let Ok(hex) = std::str::from_utf8(&in_bytes[i + 1..i + 3]) {
                if let Ok(b) = u8::from_str_radix(hex, 16) {
                    bytes.push(b);
                    i += 3;
                    continue;
                }
            }
        }
        bytes.push(in_bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&bytes).to_string()
}
