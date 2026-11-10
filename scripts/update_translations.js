#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const rootDir = path.resolve(__dirname, '..');
const i18nDir = path.join(rootDir, 'assets/i18n');
const metaPath = path.join(i18nDir, 'meta.json');
const catalogsPath = path.join(rootDir, 'qml/I18nCatalogs.js');

const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
const langCodes = meta.languages.map(l => l.code); // ['es_es', 'es_ar', 'en', 'pt', 'ja', 'zh', 'de', 'fr', 'ru']

// Translations definition
// Each entry has key (as queried in I18n.t), and translations for all 9 codes:
// es_ar, es_es, en, pt, de, fr, ja, ru, zh
const translations = {
  // ── Tables & Alignment ─────────────────────────────
  "notes.table_col1": {
    es_ar: "Columna 1", es_es: "Columna 1", en: "Column 1", pt: "Coluna 1",
    de: "Spalte 1", fr: "Colonne 1", ja: "列 1", ru: "Столбец 1", zh: "列 1"
  },
  "notes.table_col2": {
    es_ar: "Columna 2", es_es: "Columna 2", en: "Column 2", pt: "Coluna 2",
    de: "Spalte 2", fr: "Colonne 2", ja: "列 2", ru: "Столбец 2", zh: "列 2"
  },
  "notes.table_column": {
    es_ar: "Columna", es_es: "Columna", en: "Column", pt: "Coluna",
    de: "Spalte", fr: "Colonne", ja: "列", ru: "Столбец", zh: "列"
  },
  "notes.delete_table": {
    es_ar: "Eliminar tabla", es_es: "Eliminar tabla", en: "Delete table", pt: "Excluir tabela",
    de: "Tabelle löschen", fr: "Supprimer le tableau", ja: "表を削除", ru: "Удалить таблицу", zh: "删除表格"
  },
  "notes.align_center": {
    es_ar: "Alineación: centro", es_es: "Alineación: centro", en: "Alignment: center", pt: "Alinhamento: centro",
    de: "Ausrichtung: zentriert", fr: "Alignement : centre", ja: "配置: 中央", ru: "Выравнивание: по центру", zh: "对齐: 居中"
  },
  "notes.align_right": {
    es_ar: "Alineación: derecha", es_es: "Alineación: derecha", en: "Alignment: right", pt: "Alinhamento: direita",
    de: "Ausrichtung: rechts", fr: "Alignement : droite", ja: "配置: 右", ru: "Выравнивание: по правому краю", zh: "对齐: 右对齐"
  },
  "notes.align_left": {
    es_ar: "Alineación: izquierda", es_es: "Alineación: izquierda", en: "Alignment: left", pt: "Alinhamento: esquerda",
    de: "Ausrichtung: links", fr: "Alignement : gauche", ja: "配置: 左", ru: "Выравнивание: по левому краю", zh: "对齐: 左对齐"
  },
  "notes.align_none": {
    es_ar: "Alineación: predeterminada", es_es: "Alineación: predeterminada", en: "Alignment: default", pt: "Alinhamento: padrão",
    de: "Ausrichtung: standard", fr: "Alignement : par défaut", ja: "配置: デフォルト", ru: "Выравнивание: по умолчанию", zh: "对齐: 默认"
  },
  "notes.table_dots_hint": {
    es_ar: "Click: agregar · Click derecho: quitar", es_es: "Clic: añadir · Clic derecho: eliminar",
    en: "Click: add · Right click: remove", pt: "Clique: adicionar · Clique direito: remover",
    de: "Klick: hinzufügen · Rechtsklick: entfernen", fr: "Clic : ajouter · Clic droit : supprimer",
    ja: "クリック: 追加 · 右クリック: 削除", ru: "ЛКМ: добавить · ПКМ: удалить", zh: "左键: 添加 · 右键: 移除"
  },

  // ── Links & Math & Mermaid ──────────────────────────
  "notes.editor.link_text": {
    es_ar: "texto", es_es: "texto", en: "text", pt: "texto",
    de: "Text", fr: "texte", ja: "テキスト", ru: "текст", zh: "文本"
  },
  "notes.link.not_found": {
    es_ar: "Nota no encontrada: ", es_es: "Nota no encontrada: ", en: "Note not found: ", pt: "Nota não encontrada: ",
    de: "Notiz nicht gefunden: ", fr: "Note introuvable : ", ja: "ノートが見つかりません: ", ru: "Заметка не найдена: ", zh: "未找到笔记: "
  },
  "notes.create": {
    es_ar: "Crear", es_es: "Crear", en: "Create", pt: "Criar",
    de: "Erstellen", fr: "Créer", ja: "作成", ru: "Создать", zh: "创建"
  },
  "notes.math.done": {
    es_ar: "Listo", es_es: "Listo", en: "Done", pt: "Concluído",
    de: "Fertig", fr: "Terminé", ja: "完了", ru: "Готово", zh: "完成"
  },
  "notes.math.syntax_error": {
    es_ar: "Error de sintaxis en fórmula LaTeX", es_es: "Error de sintaxis en fórmula LaTeX",
    en: "LaTeX syntax error", pt: "Erro de sintaxe na fórmula LaTeX",
    de: "LaTeX-Syntaxfehler", fr: "Erreur de syntaxe dans la formule LaTeX",
    ja: "LaTeX 構文エラー", ru: "Синтаксическая ошибка LaTeX", zh: "LaTeX 语法错误"
  },
  "notes.mermaid.done": {
    es_ar: "Listo", es_es: "Listo", en: "Done", pt: "Concluído",
    de: "Fertig", fr: "Terminé", ja: "完了", ru: "Готово", zh: "完成"
  },
  "notes.mermaid.edit": {
    es_ar: "Editar", es_es: "Editar", en: "Edit", pt: "Editar",
    de: "Bearbeiten", fr: "Modifier", ja: "編集", ru: "Редактировать", zh: "编辑"
  },
  "notes.mermaid.copy_code": {
    es_ar: "Copiar código", es_es: "Copiar código", en: "Copy code", pt: "Copiar código",
    de: "Code kopieren", fr: "Copier le code", ja: "コードをコピー", ru: "Копировать код", zh: "复制代码"
  },
  "notes.mermaid.delete": {
    es_ar: "Eliminar diagrama", es_es: "Eliminar diagrama", en: "Delete diagram", pt: "Excluir diagrama",
    de: "Diagramm löschen", fr: "Supprimer le diagramme", ja: "図を削除", ru: "Удалить диаграмму", zh: "删除图表"
  },
  "notes.mermaid.unsupported": {
    es_ar: "Diagrama en desarrollo para próximas fases", es_es: "Diagrama en desarrollo para próximas fases",
    en: "Diagram type under development", pt: "Diagrama em desenvolvimento para fases futuras",
    de: "Diagrammtyp in Entwicklung", fr: "Type de diagramme en cours de développement",
    ja: "今後のフェーズで対応予定の図", ru: "Тип диаграммы находится в разработке", zh: "图表类型正在开发中"
  },
  "notes.mermaid.syntax_error": {
    es_ar: "Error de sintaxis en diagrama Mermaid", es_es: "Error de sintaxis en diagrama Mermaid",
    en: "Mermaid diagram syntax error", pt: "Erro de sintaxe no diagrama Mermaid",
    de: "Syntaxfehler im Mermaid-Diagramm", fr: "Erreur de syntaxe dans le diagramme Mermaid",
    ja: "Mermaid 図の構文エラー", ru: "Синтаксическая ошибка в диаграмме Mermaid", zh: "Mermaid 图表语法错误"
  },

  // ── Spellcheck in Editor ─────────────────────────────
  "notes.spell.suggestions": {
    es_ar: "Sugerencias", es_es: "Sugerencias", en: "Suggestions", pt: "Sugestões",
    de: "Vorschläge", fr: "Suggestions", ja: "修正候補", ru: "Предложения", zh: "建议"
  },
  "notes.spell.no_suggestions": {
    es_ar: "Sin sugerencias", es_es: "Sin sugerencias", en: "No suggestions", pt: "Sem sugestões",
    de: "Keine Vorschläge", fr: "Aucune suggestion", ja: "修正候補なし", ru: "Нет предложений", zh: "无建议"
  },
  "notes.spell.ignore": {
    es_ar: "Ignorar palabra", es_es: "Ignorar palabra", en: "Ignore word", pt: "Ignorar palavra",
    de: "Wort ignorieren", fr: "Ignorer le mot", ja: "単語を無視", ru: "Пропустить слово", zh: "忽略单词"
  },
  "notes.spell.add_to_dict": {
    es_ar: "Agregar al diccionario", es_es: "Añadir al diccionario", en: "Add to dictionary", pt: "Adicionar ao dicionário",
    de: "Zum Wörterbuch hinzufügen", fr: "Ajouter au dictionnaire", ja: "辞書に追加", ru: "Добавить в словарь", zh: "添加到词典"
  },

  // ── Images & Clipboard & Paste ──────────────────────
  "notes.image_load_error": {
    es_ar: "No se pudo cargar la imagen", es_es: "No se pudo cargar la imagen", en: "Could not load image", pt: "Não foi possível carregar a imagem",
    de: "Bild konnte nicht geladen werden", fr: "Impossible de charger l'image", ja: "画像を読み込めませんでした", ru: "Не удалось загрузить изображение", zh: "无法加载图片"
  },
  "notes.paste_img.none": {
    es_ar: "No hay imagen en el portapapeles", es_es: "No hay imagen en el portapapeles", en: "No image in clipboard", pt: "Nenhuma imagem na área de transferência",
    de: "Kein Bild in der Zwischenablage", fr: "Aucune image dans le presse-papiers", ja: "クリップボードに画像がありません", ru: "В буфере обмена нет изображения", zh: "剪贴板中没有图片"
  },
  "notes.image_url_placeholder": {
    es_ar: "Pegar URL de imagen (https://...)", es_es: "Pegar URL de imagen (https://...)", en: "Paste image URL (https://...)", pt: "Colar URL da imagem (https://...)",
    de: "Bild-URL einfügen (https://...)", fr: "Coller l'URL de l'image (https://...)", ja: "画像URLを貼り付け (https://...)", ru: "Вставьте URL изображения (https://...)", zh: "粘贴图片网址 (https://...)"
  },
  "notes.image_from_local": {
    es_ar: "Desde archivo local", es_es: "Desde archivo local", en: "From local file", pt: "Do arquivo local",
    de: "Aus lokaler Datei", fr: "Depuis un fichier local", ja: "ローカルファイルから", ru: "Из локального файла", zh: "来自本地文件"
  },
  "notes.image_from_web": {
    es_ar: "Desde enlace web", es_es: "Desde enlace web", en: "From web link", pt: "Do link da web",
    de: "Aus Weblink", fr: "Depuis un lien web", ja: "ウェブリンクから", ru: "По веб-ссылке", zh: "来自网络链接"
  },

  // ── Preview & Remote Editing & Conflict ──────────────
  "notes.preview.action_import_desc": {
    es_ar: "Importar esta nota externa a tu carpeta de notas", es_es: "Importar esta nota externa a tu carpeta de notas",
    en: "Import this external note into your notes folder", pt: "Importar esta nota externa para sua pasta de notas",
    de: "Diese externe Notiz in Ihren Notizenordner importieren", fr: "Importer cette note externe dans votre dossier de notes",
    ja: "この外部ノートをノートフォルダーにインポート", ru: "Импортировать эту внешнюю заметку в папку заметок", zh: "将此外部笔记导入您的笔记文件夹"
  },
  "notes.preview.remote_locked": {
    es_ar: "Esta nota se está editando en otra ventana.", es_es: "Esta nota se está editando en otra ventana.",
    en: "This note is being edited in another window.", pt: "Esta nota está sendo editada em outra janela.",
    de: "Diese Notiz wird in einem anderen Fenster bearbeitet.", fr: "Cette note est en cours d'édition dans une autre fenêtre.",
    ja: "このノートは別のウィンドウで編集中です。", ru: "Эта заметка редактируется в другом окне.", zh: "此笔记正在另一个窗口中编辑。"
  },
  "notes.editor.remote_editing": {
    es_ar: "Editando en otra ventana", es_es: "Editando en otra ventana", en: "Editing in another window", pt: "Editando em outra janela",
    de: "Wird in anderem Fenster bearbeitet", fr: "Modification dans une autre fenêtre", ja: "別ウィンドウで編集中", ru: "Редактируется в другом окне", zh: "在另一窗口中编辑"
  },
  "notes.editor.error": {
    es_ar: "Error al guardar", es_es: "Error al guardar", en: "Save error", pt: "Erro ao salvar",
    de: "Fehler beim Speichern", fr: "Erreur d'enregistrement", ja: "保存エラー", ru: "Ошибка сохранения", zh: "保存错误"
  },
  "notes.editor.conflict": {
    es_ar: "Conflicto", es_es: "Conflicto", en: "Conflict", pt: "Conflito",
    de: "Konflikt", fr: "Conflit", ja: "競合", ru: "Конфликт", zh: "冲突"
  },
  "notes.editor.editing": {
    es_ar: "Sin guardar", es_es: "Sin guardar", en: "Unsaved", pt: "Não salvo",
    de: "Nicht gespeichert", fr: "Non enregistré", ja: "未保存", ru: "Не сохранено", zh: "未保存"
  },
  "notes.editor.retry": {
    es_ar: "Reintentar guardado", es_es: "Reintentar guardado", en: "Retry save", pt: "Repetir salvamento",
    de: "Speichern wiederholen", fr: "Réessayer l'enregistrement", ja: "再試行", ru: "Повторить сохранение", zh: "重试保存"
  },
  "notes.editor.conflict_detected": {
    es_ar: "El archivo fue modificado externamente.", es_es: "El archivo fue modificado externamente.",
    en: "The file was modified externally.", pt: "O arquivo foi modificado externamente.",
    de: "Die Datei wurde extern geändert.", fr: "Le fichier a été modifié en externe.",
    ja: "ファイルが外部で変更されました。", ru: "Файл был изменен извне.", zh: "文件在外部被修改。"
  },
  "notes.editor.reload_disk": {
    es_ar: "Recargar disco", es_es: "Recargar disco", en: "Reload from disk", pt: "Recarregar do disco",
    de: "Von Festplatte neu laden", fr: "Recharger depuis le disque", ja: "ディスクから再読み込み", ru: "Перезагрузить с диска", zh: "从磁盘重载"
  },
  "notes.editor.keep_both": {
    es_ar: "Conservar ambas", es_es: "Conservar ambas", en: "Keep both", pt: "Manter ambos",
    de: "Beide behalten", fr: "Conserver les deux", ja: "両方を保持", ru: "Сохранить оба", zh: "保留两者"
  },
  "notes.editor.overwrite_disk": {
    es_ar: "Sobrescribir", es_es: "Sobrescribir", en: "Overwrite", pt: "Sobrescrever",
    de: "Überschreiben", fr: "Écraser", ja: "上書き", ru: "Перезаписать", zh: "覆盖"
  },
  "notes.editor.find_placeholder": {
    es_ar: "Buscar en la nota...", es_es: "Buscar en la nota...", en: "Find in note...", pt: "Buscar na nota...",
    de: "In Notiz suchen...", fr: "Rechercher dans la note...", ja: "ノート内を検索...", ru: "Поиск в заметке...", zh: "在笔记中查找..."
  },
  "notes.editor.no_matches": {
    es_ar: "Sin coincidencias", es_es: "Sin coincidencias", en: "No matches", pt: "Nenhuma correspondência",
    de: "Keine Treffer", fr: "Aucune correspondance", ja: "一致なし", ru: "Совпадений нет", zh: "无匹配"
  },
  "notes.editor.reset_zoom": {
    es_ar: "Restablecer zoom", es_es: "Restablecer zoom", en: "Reset zoom", pt: "Redefinir zoom",
    de: "Zoom zurücksetzen", fr: "Réinitialiser le zoom", ja: "ズームをリセット", ru: "Сбросить масштаб", zh: "重置缩放"
  },

  // ── Sorting & Sections & UI States ───────────────────
  "notes.sort.title": {
    es_ar: "Ordenar notas", es_es: "Ordenar notas", en: "Sort notes", pt: "Ordenar notas",
    de: "Notizen sortieren", fr: "Trier les notes", ja: "ノートを並べ替え", ru: "Сортировать заметки", zh: "排序笔记"
  },
  "notes.sort.created": {
    es_ar: "Creación", es_es: "Creación", en: "Creation", pt: "Criação",
    de: "Erstellung", fr: "Création", ja: "作成日時", ru: "Создание", zh: "创建时间"
  },
  "notes.sort.lastOpened": {
    es_ar: "Apertura", es_es: "Apertura", en: "Last opened", pt: "Abertura",
    de: "Zuletzt geöffnet", fr: "Dernière ouverture", ja: "閲覧日時", ru: "Открытие", zh: "打开时间"
  },
  "notes.sort.modified": {
    es_ar: "Modificación", es_es: "Modificación", en: "Modification", pt: "Modificação",
    de: "Änderung", fr: "Modification", ja: "更新日時", ru: "Изменение", zh: "修改时间"
  },
  "notes.tags.all": {
    es_ar: "Todos", es_es: "Todos", en: "All", pt: "Todos",
    de: "Alle", fr: "Tous", ja: "すべて", ru: "Все", zh: "全部"
  },
  "notes.loading": {
    es_ar: "Cargando notas...", es_es: "Cargando notas...", en: "Loading notes...", pt: "Carregando notas...",
    de: "Notizen werden geladen...", fr: "Chargement des notes...", ja: "ノートを読み込み中...", ru: "Загрузка заметок...", zh: "正在加载笔记..."
  },
  "notes.empty.search": {
    es_ar: "No se encontraron notas", es_es: "No se encontraron notas", en: "No notes found", pt: "Nenhuma nota encontrada",
    de: "Keine Notizen gefunden", fr: "Aucune note trouvée", ja: "ノートが見つかりません", ru: "Заметки не найдены", zh: "未找到笔记"
  },
  "notes.empty.create": {
    es_ar: "Crear nota", es_es: "Crear nota", en: "Create note", pt: "Criar nota",
    de: "Notiz erstellen", fr: "Créer une note", ja: "ノートを作成", ru: "Создать заметку", zh: "创建笔记"
  },
  "notes.section.pinned": {
    es_ar: "FIJADAS", es_es: "FIJADAS", en: "PINNED", pt: "FIXADAS",
    de: "ANGEHEFTET", fr: "ÉPINGLÉES", ja: "ピン留め", ru: "ЗАКРЕПЛЕННЫЕ", zh: "已置顶"
  },
  "notes.section.others": {
    es_ar: "OTRAS", es_es: "OTRAS", en: "OTHERS", pt: "OUTRAS",
    de: "ANDERE", fr: "AUTRES", ja: "その他", ru: "ДРУГИЕ", zh: "其他"
  },

  // ── Remote Toast Events ──────────────────────────────
  "notes.toast.remote_editing_transferred": {
    es_ar: "Edición transferida a otra ventana (modo lectura activo)",
    es_es: "Edición transferida a otra ventana (modo lectura activo)",
    en: "Editing transferred to another window (read-only mode active)",
    pt: "Edição transferida para outra janela (modo de leitura ativo)",
    de: "Bearbeitung an ein anderes Fenster übertragen (Nur-Lese-Modus aktiv)",
    fr: "Édition transférée à une autre fenêtre (mode lecture actif)",
    ja: "編集が別のウィンドウに移行しました (読み取り専用モード)",
    ru: "Редактирование перенесено в другое окно (активен режим чтения)",
    zh: "编辑已转移到另一窗口（只读模式处于活动状态）"
  },
  "notes.toast.remote_note_updated": {
    es_ar: "Actualizado desde otra ventana", es_es: "Actualizado desde otra ventana",
    en: "Updated from another window", pt: "Atualizado a partir de outra janela",
    de: "Aus anderem Fenster aktualisiert", fr: "Mis à jour depuis une autre fenêtre",
    ja: "別のウィンドウから更新されました", ru: "Обновлено из другого окна", zh: "已从另一个窗口更新"
  },
  "notes.toast.remote_note_deleted": {
    es_ar: "La nota fue eliminada en otra ventana", es_es: "La nota fue eliminada en otra ventana",
    en: "Note was deleted in another window", pt: "A nota foi excluída em outra janela",
    de: "Die Notiz wurde in einem anderen Fenster gelöscht", fr: "La note a été supprimée dans une autre fenêtre",
    ja: "ノートが別のウィンドウで削除されました", ru: "Заметка была удалена в другом окне", zh: "笔记已在另一窗口中被删除"
  },

  // ── Common Actions ───────────────────────────────────
  "common.actions.undo": {
    es_ar: "Deshacer", es_es: "Deshacer", en: "Undo", pt: "Desfazer",
    de: "Rückgängig", fr: "Annuler", ja: "元に戻す", ru: "Отменить", zh: "撤消"
  },
  "common.actions.redo": {
    es_ar: "Rehacer", es_es: "Rehacer", en: "Redo", pt: "Refazer",
    de: "Wiederholen", fr: "Rétablir", ja: "やり直し", ru: "Повторить", zh: "重做"
  },
  "common.actions.cut": {
    es_ar: "Cortar", es_es: "Cortar", en: "Cut", pt: "Recortar",
    de: "Ausschneiden", fr: "Couper", ja: "切り取り", ru: "Вырезать", zh: "剪切"
  },
  "common.actions.copy": {
    es_ar: "Copiar", es_es: "Copiar", en: "Copy", pt: "Copiar",
    de: "Kopieren", fr: "Copier", ja: "コピー", ru: "Копировать", zh: "复制"
  },
  "common.actions.paste": {
    es_ar: "Pegar", es_es: "Pegar", en: "Paste", pt: "Colar",
    de: "Einfügen", fr: "Coller", ja: "貼り付け", ru: "Вставить", zh: "粘贴"
  },
  "common.actions.delete": {
    es_ar: "Borrar", es_es: "Eliminar", en: "Delete", pt: "Excluir",
    de: "Löschen", fr: "Supprimer", ja: "削除", ru: "Удалить", zh: "删除"
  },
  "common.actions.select_all": {
    es_ar: "Seleccionar todo", es_es: "Seleccionar todo", en: "Select all", pt: "Selecionar tudo",
    de: "Alles auswählen", fr: "Tout sélectionner", ja: "すべて選択", ru: "Выбрать все", zh: "全选"
  },

  // ── Config Modal & Tabs & Themes ─────────────────────
  "config.notes.version_history_enabled": {
    es_ar: "Historial de versiones y snapshots", es_es: "Historial de versiones y snapshots",
    en: "Version history and snapshots", pt: "Histórico de versões e instantâneos",
    de: "Versionsverlauf und Snapshots", fr: "Historique des versions et instantanés",
    ja: "バージョン履歴とスナップショット", ru: "История версий и снимки", zh: "版本历史与快照"
  },
  "config.notes.version_history_comment": {
    es_ar: "Guarda snapshots automáticos periódicos para comparar diferencias y restaurar versiones previas.",
    es_es: "Guarda snapshots automáticos periódicos para comparar diferencias y restaurar versiones previas.",
    en: "Saves periodic automatic snapshots to compare diffs and restore previous versions.",
    pt: "Salva instantâneos automáticos periódicos para comparar diferenças e restaurar versões anteriores.",
    de: "Speichert regelmäßige automatische Snapshots zum Vergleichen von Diffs und Wiederherstellen früherer Versionen.",
    fr: "Enregistre des instantanés automatiques périodiques pour comparer les différences et restaurer les versions antérieures.",
    ja: "定期的な自動スナップショットを保存し、差分を比較して以前のバージョンを復元します。",
    ru: "Сохраняет периодические автоматические снимки для сравнения различий и восстановления предыдущих версий.",
    zh: "保存定期的自动快照以比较差异并还原先前版本。"
  },
  "config.notes.version_history_max": {
    es_ar: "Máximo de versiones", es_es: "Máximo de versiones", en: "Maximum versions", pt: "Máximo de versões",
    de: "Maximale Versionen", fr: "Nombre maximal de versions", ja: "最大バージョン数", ru: "Максимум версий", zh: "最大版本数"
  },
  "config.notes.version_history_max_comment": {
    es_ar: "Cantidad máxima de snapshots automáticos conservados por nota antes de podar.",
    es_es: "Cantidad máxima de snapshots automáticos conservados por nota antes de podar.",
    en: "Maximum number of automatic snapshots kept per note before pruning.",
    pt: "Número máximo de instantâneos automáticos mantidos por nota antes da remoção.",
    de: "Maximale Anzahl automatischer Snapshots pro Notiz vor dem Bereinigen.",
    fr: "Nombre maximal d'instantanés automatiques conservés par note avant purge.",
    ja: "古いものを削除する前にノートごとに保持される自動スナップショットの最大数。",
    ru: "Максимальное количество автоматических снимков на заметку перед очисткой.",
    zh: "修剪前每篇笔记保留的自动快照的最大数量。"
  },
  "config.notes.version_history_max_mb": {
    es_ar: "Límite de almacenamiento de snapshots", es_es: "Límite de almacenamiento de snapshots",
    en: "Snapshot storage limit", pt: "Limite de armazenamento de instantâneos",
    de: "Speicherlimit für Snapshots", fr: "Limite de stockage des instantanés",
    ja: "スナップショット容量制限", ru: "Лимит хранилища снимков", zh: "快照存储空间限制"
  },
  "config.notes.version_history_max_mb_comment": {
    es_ar: "Espacio máximo en megabytes para snapshots automáticos por nota antes de podar los más antiguos.",
    es_es: "Espacio máximo en megabytes para snapshots automáticos por nota antes de podar los más antiguos.",
    en: "Maximum storage space in megabytes for automatic snapshots per note before pruning older ones.",
    pt: "Espaço máximo em megabytes para instantâneos automáticos por nota antes de remover os mais antigos.",
    de: "Maximaler Speicherplatz in Megabyte für automatische Snapshots pro Notiz vor der Bereinigung älterer.",
    fr: "Espace maximal en mégaoctets pour les instantanés automatiques par note avant suppression des plus anciens.",
    ja: "古いものを削除する前の、ノートごとの自動スナップショットの最大ストレージ容量 (MB)。",
    ru: "Максимальный объем в мегабайтах для автоматических снимков на заметку перед удалением старых.",
    zh: "修剪旧快照前每篇笔记自动快照的最大空间（MB）。"
  },
  "config.notes.persist_undo": {
    es_ar: "Deshacer persistente (Ctrl+Z)", es_es: "Deshacer persistente (Ctrl+Z)",
    en: "Persistent undo (Ctrl+Z)", pt: "Desfazer persistente (Ctrl+Z)",
    de: "Dauerhaftes Rückgängigmachen (Strg+Z)", fr: "Annulation persistante (Ctrl+Z)",
    ja: "永続的な「元に戻す」(Ctrl+Z)", ru: "Постоянная отмена (Ctrl+Z)", zh: "持久撤消 (Ctrl+Z)"
  },
  "config.notes.persist_undo_comment": {
    es_ar: "Conserva la pila de deshacer/rehacer entre aperturas de la nota.",
    es_es: "Conserva la pila de deshacer/rehacer entre aperturas de la nota.",
    en: "Retains the undo/redo stack across note reopenings.",
    pt: "Mantém a pilha de desfazer/refazer entre reaberturas da nota.",
    de: "Behält den Rückgängig-/Wiederholen-Verlauf auch nach dem Schließen der Notiz bei.",
    fr: "Conserve la pile d'annulation/rétablissement entre les réouvertures de note.",
    ja: "ノートを再度開いたときにも「元に戻す/やり直し」スタックを保持します。",
    ru: "Сохраняет историю отмены и повтора между открытиями заметки.",
    zh: "在重新打开笔记时保留撤消/重做栈。"
  },
  "config.notes.show_source_mode_button": {
    es_ar: "Mostrar botón de código fuente", es_es: "Mostrar botón de código fuente",
    en: "Show source code button", pt: "Mostrar botão de código-fonte",
    de: "Quellcode-Schaltfläche anzeigen", fr: "Afficher le bouton de code source",
    ja: "ソースコードボタンを表示", ru: "Показывать кнопку исходного кода", zh: "显示源代码按钮"
  },
  "config.notes.show_source_mode_button_comment": {
    es_ar: "Muestra el botón de alternar código fuente en la barra de herramientas del editor.",
    es_es: "Muestra el botón de alternar código fuente en la barra de herramientas del editor.",
    en: "Displays the source code toggle button in the editor toolbar.",
    pt: "Exibe o botão de alternância de código-fonte na barra de ferramentas do editor.",
    de: "Zeigt die Quellcode-Schaltfläche in der Editor-Symbolleiste an.",
    fr: "Affiche le bouton de bascule vers le code source dans la barre d'outils de l'éditeur.",
    ja: "エディターツールバーにソースコード切り替えボタンを表示します。",
    ru: "Отображает кнопку переключения исходного кода на панели инструментов редактора.",
    zh: "在编辑器工具栏中显示源代码切换按钮。"
  },
  "config.header.title": {
    es_ar: "Configuración", es_es: "Configuración", en: "Settings", pt: "Configurações",
    de: "Einstellungen", fr: "Paramètres", ja: "設定", ru: "Настройки", zh: "设置"
  },
  "config.tabs.editor": {
    es_ar: "Editor", es_es: "Editor", en: "Editor", pt: "Editor",
    de: "Editor", fr: "Éditeur", ja: "エディター", ru: "Редактор", zh: "编辑器"
  },
  "config.tabs.appearance": {
    es_ar: "Apariencia", es_es: "Apariencia", en: "Appearance", pt: "Aparência",
    de: "Erscheinungsbild", fr: "Apparence", ja: "外観", ru: "Внешний вид", zh: "外观"
  },
  "config.tabs.language": {
    es_ar: "Idioma y Corrección", es_es: "Idioma y Corrección", en: "Language & Spelling", pt: "Idioma e Correção",
    de: "Sprache & Rechtschreibung", fr: "Langue et Orthographe", ja: "言語と校正", ru: "Язык и проверка", zh: "语言与拼写"
  },
  "config.tabs.about": {
    es_ar: "Acerca de", es_es: "Acerca de", en: "About", pt: "Sobre",
    de: "Über", fr: "À propos", ja: "情報", ru: "О программе", zh: "关于"
  },
  "config.language.spell_installed": {
    es_ar: "Instalado", es_es: "Instalado", en: "Installed", pt: "Instalado",
    de: "Installiert", fr: "Installé", ja: "インストール済み", ru: "Установлен", zh: "已安装"
  },
  "config.language.spell_removed": {
    es_ar: "Diccionario quitado", es_es: "Diccionario eliminado", en: "Dictionary removed", pt: "Dicionário removido",
    de: "Wörterbuch entfernt", fr: "Dictionnaire supprimé", ja: "辞書を削除しました", ru: "Словарь удален", zh: "词典已移除"
  },
  "config.modal.title": {
    es_ar: "Configuración de Notas", es_es: "Configuración de Notas", en: "Notes Settings", pt: "Configurações do Notas",
    de: "Notizen-Einstellungen", fr: "Paramètres de Notes", ja: "Notes の設定", ru: "Настройки Заметок", zh: "笔记设置"
  },
  "config.theme.source_section": {
    es_ar: "Origen de Colores y Tema", es_es: "Origen de Colores y Tema", en: "Color & Theme Source", pt: "Origem de Cores e Tema",
    de: "Farb- und Themenquelle", fr: "Source des couleurs et du thème", ja: "配色とテーマの取得元", ru: "Источник цветов и тем", zh: "颜色和主题来源"
  },
  "config.theme.qs_synced_title": {
    es_ar: "Esquema y Colores sincronizados", es_es: "Esquema y Colores sincronizados",
    en: "Synchronized Scheme & Colors", pt: "Esquema e Cores sincronizados",
    de: "Synchronisiertes Farbschema", fr: "Schéma et Couleurs synchronisés",
    ja: "同期されたカラースキーム", ru: "Синхронизированная схема цветов", zh: "同步配色方案"
  },
  "config.theme.qs_synced_desc": {
    es_ar: "El tema de color, la opacidad y las preferencias se sincronizan automáticamente con tu configuración de Quickshell.",
    es_es: "El tema de color, la opacidad y las preferencias se sincronizan automáticamente con tu configuración de Quickshell.",
    en: "Color theme, opacity and preferences automatically sync with your Quickshell setup.",
    pt: "O tema de cores, opacidade e preferências sincronizam-se automaticamente com o Quickshell.",
    de: "Farbthema, Deckkraft und Einstellungen synchronisieren sich automatisch mit Quickshell.",
    fr: "Le thème de couleur, l'opacité et les préférences se synchronisent automatiquement avec Quickshell.",
    ja: "カラーテーマ、不透明度、環境設定は Quickshell 設定と自動同期されます。",
    ru: "Цветовая тема, прозрачность и настройки автоматически синхронизируются с Quickshell.",
    zh: "颜色主题、不透明度和首选项会自动与您的 Quickshell 配置同步。"
  },
  "config.theme.color_source": {
    es_ar: "Esquema de color activo", es_es: "Esquema de color activo", en: "Active color scheme", pt: "Esquema de cores ativo",
    de: "Aktives Farbschema", fr: "Schéma de couleurs actif", ja: "有効なカラースキーム", ru: "Активная цветовая схема", zh: "当前配色方案"
  },
  "config.theme.pywal": {
    es_ar: "Pywal (Fondo)", es_es: "Pywal (Fondo)", en: "Pywal (Wallpaper)", pt: "Pywal (Papel de parede)",
    de: "Pywal (Hintergrund)", fr: "Pywal (Fond d'écran)", ja: "Pywal (壁紙)", ru: "Pywal (Обои)", zh: "Pywal (壁纸)"
  },
  "config.theme.qt": {
    es_ar: "Qt (Sistema)", es_es: "Qt (Sistema)", en: "Qt (System)", pt: "Qt (Sistema)",
    de: "Qt (System)", fr: "Qt (Système)", ja: "Qt (システム)", ru: "Qt (Система)", zh: "Qt (系统)"
  },
  "config.theme.custom": {
    es_ar: "Personalizado", es_es: "Personalizado", en: "Custom", pt: "Personalizado",
    de: "Benutzerdefiniert", fr: "Personnalisé", ja: "カスタム", ru: "Пользовательская", zh: "自定义"
  },
  "config.theme.pywal_active_hint": {
    es_ar: "Sincronizando paleta dinámicamente desde ~/.cache/wal/colors.json",
    es_es: "Sincronizando paleta dinámicamente desde ~/.cache/wal/colors.json",
    en: "Dynamically synchronizing palette from ~/.cache/wal/colors.json",
    pt: "Sincronizando paleta dinamicamente de ~/.cache/wal/colors.json",
    de: "Palette wird dynamisch aus ~/.cache/wal/colors.json synchronisiert",
    fr: "Synchronisation dynamique de la palette depuis ~/.cache/wal/colors.json",
    ja: "~/.cache/wal/colors.json からパレットを動的に同期中",
    ru: "Динамическая синхронизация палитры из ~/.cache/wal/colors.json",
    zh: "正在从 ~/.cache/wal/colors.json 动态同步调色板"
  },
  "config.theme.pywal_missing_hint": {
    es_ar: "No se detectó ~/.cache/wal/colors.json; usando colores de respaldo de Qt.",
    es_es: "No se detectó ~/.cache/wal/colors.json; usando colores de respaldo de Qt.",
    en: "~/.cache/wal/colors.json not detected; using Qt fallback colors.",
    pt: "Não foi detectado ~/.cache/wal/colors.json; usando cores de reserva do Qt.",
    de: "~/.cache/wal/colors.json nicht gefunden; Fallback-Qt-Farben werden genutzt.",
    fr: "~/.cache/wal/colors.json non détecté ; utilisation des couleurs de secours Qt.",
    ja: "~/.cache/wal/colors.json が見つかりません。Qtフォールバックカラーを使用します。",
    ru: "~/.cache/wal/colors.json не найден; используются резервные цвета Qt.",
    zh: "未检测到 ~/.cache/wal/colors.json；正在使用 Qt 后备颜色。"
  },
  "config.theme.qt_active_hint": {
    es_ar: "Extrayendo paleta activa de Kvantum / qt6ct / Qt SystemPalette.",
    es_es: "Extrayendo paleta activa de Kvantum / qt6ct / Qt SystemPalette.",
    en: "Extracting active palette from Kvantum / qt6ct / Qt SystemPalette.",
    pt: "Extraindo paleta ativa de Kvantum / qt6ct / Qt SystemPalette.",
    de: "Aktive Palette wird aus Kvantum / qt6ct / Qt SystemPalette extrahiert.",
    fr: "Extraction de la palette active depuis Kvantum / qt6ct / Qt SystemPalette.",
    ja: "Kvantum / qt6ct / Qt SystemPalette からアクティブなパレットを抽出中。",
    ru: "Извлечение палитры из Kvantum / qt6ct / Qt SystemPalette.",
    zh: "正在从 Kvantum / qt6ct / Qt SystemPalette 提取当前调色板。"
  },
  "config.theme.custom_active_hint": {
    es_ar: "Usando paleta predefinida personalizada de Quickshell.",
    es_es: "Usando paleta predefinida personalizada de Quickshell.",
    en: "Using Quickshell custom predefined palette.",
    pt: "Usando paleta predefinida personalizada do Quickshell.",
    de: "Benutzerdefinierte Quickshell-Farbpalette wird verwendet.",
    fr: "Utilisation de la palette prédéfinie personnalisée de Quickshell.",
    ja: "Quickshell のカスタム定義済みパレットを使用中。",
    ru: "Используется предустановленная палитра Quickshell.",
    zh: "正在使用 Quickshell 自定义预设调色板。"
  },
  "config.theme.light_mode": {
    es_ar: "Modo claro", es_es: "Modo claro", en: "Light mode", pt: "Modo claro",
    de: "Heller Modus", fr: "Mode clair", ja: "ライトモード", ru: "Светлый режим", zh: "浅色模式"
  },
  "config.theme.light_mode_comment": {
    es_ar: "Alterna entre variante oscura y clara para los temas predefinidos.",
    es_es: "Alterna entre variante oscura y clara para los temas predefinidos.",
    en: "Toggle between dark and light variants for predefined themes.",
    pt: "Alterna entre temas escuros e claros predefinidos.",
    de: "Wechselt zwischen dunklen und hellen Varianten vordefinierter Themen.",
    fr: "Bascule entre les variantes sombre et claire pour les thèmes prédéfinis.",
    ja: "定義済みテーマのダークとライトのバリエーションを切り替えます。",
    ru: "Переключение между темной и светлой темами.",
    zh: "在预设主题的深色和浅色变体之间切换。"
  },
  "config.theme.predefined_title": {
    es_ar: "Temas predefinidos", es_es: "Temas predefinidos", en: "Predefined themes", pt: "Temas predefinidos",
    de: "Vordefinierte Themen", fr: "Thèmes prédéfinis", ja: "定義済みテーマ", ru: "Предустановленные темы", zh: "预设主题"
  },
  "config.theme.interface_section": {
    es_ar: "Interfaz, Escala y Efectos", es_es: "Interfaz, Escala y Efectos", en: "Interface, Scale & Effects", pt: "Interface, Escala e Efeitos",
    de: "Oberfläche, Skalierung & Effekte", fr: "Interface, Échelle et Effets", ja: "インターフェース、拡大縮小、エフェクト", ru: "Интерфейс, масштаб и эффекты", zh: "界面、缩放与效果"
  },
  "config.general.panel_opacity": {
    es_ar: "Opacidad del fondo", es_es: "Opacidad del fondo", en: "Background opacity", pt: "Opacidade do fundo",
    de: "Hintergrund-Deckkraft", fr: "Opacité de l'arrière-plan", ja: "背景の不透明度", ru: "Непрозрачность фона", zh: "背景不透明度"
  },
  "config.general.panel_opacity_comment": {
    es_ar: "Nivel de opacidad de la ventana principal de Notas.",
    es_es: "Nivel de opacidad de la ventana principal de Notas.",
    en: "Opacity level of the main Notes window.",
    pt: "Nível de opacidade da janela principal de Notas.",
    de: "Deckkraft des Notizen-Hauptfensters.",
    fr: "Niveau d'opacité de la fenêtre principale de Notes.",
    ja: "Notes メインウィンドウの不透明度レベル。",
    ru: "Уровень прозрачности главного окна Заметок.",
    zh: "笔记主窗口的不透明度级别。"
  },
  "config.font.scale": {
    es_ar: "Escala tipográfica de interfaz", es_es: "Escala tipográfica de interfaz", en: "UI font scale", pt: "Escala tipográfica da interface",
    de: "Schriftgröße der Benutzeroberfläche", fr: "Échelle de police de l'interface", ja: "UIフォント倍率", ru: "Масштаб шрифта интерфейса", zh: "界面字体缩放"
  },
  "config.font.scale_comment": {
    es_ar: "Ajusta el tamaño global de textos y controles.",
    es_es: "Ajusta el tamaño global de textos y controles.",
    en: "Adjusts global text and control sizing.",
    pt: "Ajusta o tamanho global de textos e controles.",
    de: "Passt die globale Text- und Steuerelementgröße an.",
    fr: "Ajuste la taille globale du texte et des commandes.",
    ja: "テキストとコントロール全体のサイズを調整します。",
    ru: "Настройка глобального размера текста и элементов интерфейса.",
    zh: "调整全局文本和控件大小。"
  },
  "config.hyprland.animations": {
    es_ar: "Animaciones fluidas", es_es: "Animaciones fluidas", en: "Fluid animations", pt: "Animações fluidas",
    de: "Flüssige Animationen", fr: "Animations fluides", ja: "なめらかなアニメーション", ru: "Плавные анимации", zh: "流畅动画"
  },
  "config.hyprland.animations_comment": {
    es_ar: "Habilita transiciones elásticas y animaciones de interfaz.",
    es_es: "Habilita transiciones elásticas y animaciones de interfaz.",
    en: "Enables spring transitions and smooth interface animations.",
    pt: "Habilita transições elásticas e animações de interface.",
    de: "Aktiviert federnde Übergänge und flüssige Animationen.",
    fr: "Active les transitions dynamiques et les animations fluides.",
    ja: "スプリングトランジションとなめらかなインターフェースアニメーションを有効にします。",
    ru: "Включает плавные переходы и анимации интерфейса.",
    zh: "启用弹性过渡和平滑界面动画。"
  },
  "config.hyprland.blur": {
    es_ar: "Efectos de desenfoque", es_es: "Efectos de desenfoque", en: "Blur effects", pt: "Efeitos de desfoque",
    de: "Weichzeichner-Effekte", fr: "Effets de flou", ja: "ぼかし効果", ru: "Эффекты размытия", zh: "模糊效果"
  },
  "config.hyprland.blur_comment": {
    es_ar: "Habilita desenfoque y sombras suaves cuando el sistema lo soporta.",
    es_es: "Habilita desenfoque y sombras suaves cuando el sistema lo soporta.",
    en: "Enables blur and soft shadows when supported by the compositor.",
    pt: "Habilita desfoque e sombras suaves quando o sistema suportar.",
    de: "Aktiviert Weichzeichnung und weiche Schatten, wenn vom System unterstützt.",
    fr: "Active le flou et les ombres douces si pris en charge par le système.",
    ja: "システムがサポートしている場合に、ぼかしとソフトシャドウを有効にします。",
    ru: "Включает размытие и мягкие тени при поддержке системы.",
    zh: "在系统支持时启用模糊和柔和阴影。"
  },
  "config.general.hide_scrollbars": {
    es_ar: "Ocultar barras de desplazamiento", es_es: "Ocultar barras de desplazamiento", en: "Hide scrollbars", pt: "Ocultar barras de rolagem",
    de: "Bildlaufleisten ausblenden", fr: "Masquer les barres de défilement", ja: "スクロールバーを非表示", ru: "Скрыть полосы прокрутки", zh: "隐藏滚动条"
  },
  "config.general.hide_scrollbars_comment": {
    es_ar: "Mantiene el desplazamiento con rueda o gestos ocultando las barras visuales.",
    es_es: "Mantiene el desplazamiento con rueda o gestos ocultando las barras visuales.",
    en: "Maintains wheel/touchpad scrolling while hiding visual scrollbars.",
    pt: "Mantém a rolagem por roda/gestos ocultando as barras visuais.",
    de: "Behält Scrollen per Mausrad/Touchpad bei, blendet aber Leisten aus.",
    fr: "Conserve le défilement à la molette tout en masquant les barres.",
    ja: "視覚的なバーを非表示にしながらホイールやジェスチャーによるスクロールを維持します。",
    ru: "Сохраняет прокрутку колесом или жестами, скрывая полосы.",
    zh: "在使用滚轮/手势滚动的同时隐藏视觉滚动条。"
  },
  "config.window.controls_title": {
    es_ar: "Botones de ventana (CSD)", es_es: "Botones de ventana (CSD)", en: "Window buttons (CSD)", pt: "Botões de janela (CSD)",
    de: "Fenster-Schaltflächen (CSD)", fr: "Boutons de fenêtre (CSD)", ja: "ウィンドウボタン (CSD)", ru: "Кнопки окна (CSD)", zh: "窗口按钮 (CSD)"
  },
  "config.window.controls_comment": {
    es_ar: "Muestra los botones de minimizar, maximizar y cerrar en la barra superior.",
    es_es: "Muestra los botones de minimizar, maximizar y cerrar en la barra superior.",
    en: "Show minimize, maximize and close buttons in the top bar.",
    pt: "Exibe os botões de minimizar, maximizar e fechar na barra superior.",
    de: "Minimieren-, Maximieren- und Schließen-Schaltflächen anzeigen.",
    fr: "Affiche les boutons de réduction, agrandissement et fermeture dans la barre supérieure.",
    ja: "上部バーに最小化、最大化、閉じるボタンを表示します。",
    ru: "Показывать кнопки свернуть, развернуть и закрыть в верхней панели.",
    zh: "在顶部栏显示最小化、最大化和关闭按钮。"
  },
  "config.window.controls_auto": {
    es_ar: "Automático (según WM)", es_es: "Automático (según WM)", en: "Automatic (by WM)", pt: "Automático (por WM)",
    de: "Automatisch (nach WM)", fr: "Automatique (selon le WM)", ja: "自動 (WM に合わせる)", ru: "Автоматически (по WM)", zh: "自动（根据 WM）"
  },
  "config.window.controls_always": {
    es_ar: "Siempre", es_es: "Siempre", en: "Always", pt: "Sempre",
    de: "Immer", fr: "Toujours", ja: "常に表示", ru: "Всегда", zh: "总是"
  },
  "config.window.controls_never": {
    es_ar: "Nunca", es_es: "Nunca", en: "Never", pt: "Nunca",
    de: "Nie", fr: "Jamais", ja: "表示しない", ru: "Никогда", zh: "从不"
  },
  "config.language.ui_title": {
    es_ar: "Idioma de la Interfaz", es_es: "Idioma de la Interfaz", en: "Interface Language", pt: "Idioma da Interface",
    de: "Oberflächensprache", fr: "Langue de l'interface", ja: "UIの言語", ru: "Язык интерфейса", zh: "界面语言"
  },
  "config.language.ui_subtitle": {
    es_ar: "Selecciona el idioma de menús, etiquetas y controles de Notas.",
    es_es: "Selecciona el idioma de menús, etiquetas y controles de Notas.",
    en: "Select language for menus, labels and controls in Notes.",
    pt: "Selecione o idioma dos menus, rótulos e controles de Notas.",
    de: "Wählen Sie die Sprache für Menüs, Beschriftungen und Steuerelemente.",
    fr: "Sélectionnez la langue des menus, libellés et commandes dans Notes.",
    ja: "Notes のメニュー、ラベル、コントロールの言語を選択します。",
    ru: "Выберите язык меню, надписей и элементов Заметок.",
    zh: "选择笔记中菜单、标签和控件的语言。"
  },
  "config.language.auto_system": {
    es_ar: "Automático (Sistema)", es_es: "Automático (Sistema)", en: "Automatic (System)", pt: "Automático (Sistema)",
    de: "Automatisch (System)", fr: "Automatique (Système)", ja: "自動 (システム)", ru: "Автоматически (Система)", zh: "自动（系统）"
  },
  "config.language.spell_title": {
    es_ar: "Corrector Ortográfico", es_es: "Corrector Ortográfico", en: "Spell Checker", pt: "Corretor Ortográfico",
    de: "Rechtschreibprüfung", fr: "Correcteur orthographique", ja: "スペルチェッカー", ru: "Проверка правописания", zh: "拼写检查器"
  },
  "config.language.spell_primary": {
    es_ar: "Principal", es_es: "Principal", en: "Primary", pt: "Principal",
    de: "Primär", fr: "Principal", ja: "メイン", ru: "Основной", zh: "主要"
  },
  "config.language.spell_search_placeholder": {
    es_ar: "Buscar diccionario o código (ej. es_AR, en_US)...",
    es_es: "Buscar diccionario o código (ej. es_ES, en_US)...",
    en: "Search dictionary or code (e.g. en_US, es_ES)...",
    pt: "Buscar dicionário ou código (ex. pt_BR, en_US)...",
    de: "Wörterbuch oder Code suchen (z.B. de_DE, en_US)...",
    fr: "Rechercher un dictionnaire ou un code (ex. fr_FR, en_US)...",
    ja: "辞書またはコードを検索 (例: ja_JP, en_US)...",
    ru: "Поиск словаря или кода (напр. ru_RU, en_US)...",
    zh: "搜索词典或代码（例如 zh_CN、en_US）..."
  },
  "config.language.spell_import_btn": {
    es_ar: "Importar archivo", es_es: "Importar archivo", en: "Import file", pt: "Importar arquivo",
    de: "Datei importieren", fr: "Importer un fichier", ja: "ファイルをインポート", ru: "Импорт файла", zh: "导入文件"
  },
  "config.language.spell_results": {
    es_ar: "Resultados de búsqueda:", es_es: "Resultados de búsqueda:", en: "Search results:", pt: "Resultados da pesquisa:",
    de: "Suchergebnisse:", fr: "Résultats de recherche :", ja: "検索結果:", ru: "Результаты поиска:", zh: "搜索结果:"
  },
  "config.language.spell_recommended_hint": {
    es_ar: "Idiomas instalados y recomendados (escribe en el buscador para ver más de 30 idiomas)",
    es_es: "Idiomas instalados y recomendados (escribe en el buscador para ver más de 30 idiomas)",
    en: "Installed and recommended languages (type in search box to see 30+ languages)",
    pt: "Idiomas instalados e recomendados (digite na busca para ver mais de 30 idiomas)",
    de: "Installierte und empfohlene Sprachen (im Suchfeld eingeben, um 30+ Sprachen zu sehen)",
    fr: "Langues installées et recommandées (tapez pour voir plus de 30 langues)",
    ja: "インストール済みおよび推奨言語 (検索で30以上の言語を表示)",
    ru: "Установленные и рекомендуемые языки (введите для поиска более 30 языков)",
    zh: "已安装和推荐语言（输入搜索以查看 30 多种语言）"
  },
  "config.language.spell_no_match": {
    es_ar: "No se encontraron diccionarios", es_es: "No se encontraron diccionarios", en: "No dictionaries found", pt: "Nenhum dicionário encontrado",
    de: "Keine Wörterbücher gefunden", fr: "Aucun dictionnaire trouvé", ja: "辞書が見つかりませんでした", ru: "Словари не найдены", zh: "未找到词典"
  },
  "config.language.spell_no_match_hint": {
    es_ar: "Puedes importar manualmente archivos .dic / .aff o .oxt",
    es_es: "Puedes importar manualmente archivos .dic / .aff o .oxt",
    en: "You can manually import .dic / .aff or .oxt files",
    pt: "Você pode importar manualmente arquivos .dic / .aff ou .oxt",
    de: "Sie können .dic / .aff oder .oxt-Dateien manuell importieren",
    fr: "Vous pouvez importer manuellement des fichiers .dic / .aff ou .oxt",
    ja: ".dic / .aff または .oxt ファイルを手動でインポートできます",
    ru: "Вы можете вручную импортировать файлы .dic / .aff или .oxt",
    zh: "您可以手动导入 .dic / .aff 或 .oxt 文件"
  },
  "config.language.spell_system": {
    es_ar: "Sistema", es_es: "Sistema", en: "System", pt: "Sistema",
    de: "System", fr: "Système", ja: "システム", ru: "Система", zh: "系统"
  },
  "config.language.spell_active": {
    es_ar: "Activo", es_es: "Activo", en: "Active", pt: "Ativo",
    de: "Aktiv", fr: "Actif", ja: "有効", ru: "Активен", zh: "已启用"
  },
  "config.language.spell_paused": {
    es_ar: "Pausado", es_es: "Pausado", en: "Paused", pt: "Pausado",
    de: "Pausiert", fr: "En pause", ja: "一時停止中", ru: "Приостановлен", zh: "已暂停"
  },
  "config.language.spell_remove": {
    es_ar: "Quitar", es_es: "Eliminar", en: "Remove", pt: "Remover",
    de: "Entfernen", fr: "Supprimer", ja: "削除", ru: "Удалить", zh: "移除"
  },
  "config.language.spell_install": {
    es_ar: "Instalar", es_es: "Instalar", en: "Install", pt: "Instalar",
    de: "Installieren", fr: "Installer", ja: "インストール", ru: "Установить", zh: "安装"
  },
  "config.spellcheck.personal_dict": {
    es_ar: "Diccionario personal", es_es: "Diccionario personal", en: "Personal dictionary", pt: "Dicionário pessoal",
    de: "Persönliches Wörterbuch", fr: "Dictionnaire personnel", ja: "個人用辞書", ru: "Пользовательский словарь", zh: "个人词典"
  },
  "config.spellcheck.clear_personal": {
    es_ar: "Vaciar", es_es: "Vaciar", en: "Clear", pt: "Limpar",
    de: "Leeren", fr: "Effacer", ja: "クリア", ru: "Очистить", zh: "清空"
  },
  "notes.slash.link": {
    es_ar: "Enlace web o externo", es_es: "Enlace web o externo", en: "Web or external link", pt: "Link web ou externo",
    de: "Web- oder externer Link", fr: "Lien web ou externe", ja: "ウェブまたは外部リンク", ru: "Веб или внешняя ссылка", zh: "网页或外部链接"
  },
  "notes.slash.link_desc": {
    es_ar: "Insertar un enlace markdown [texto](url)", es_es: "Insertar un enlace markdown [texto](url)",
    en: "Insert a markdown link [text](url)", pt: "Inserir um link markdown [texto](url)",
    de: "Einen Markdown-Link einfügen [Text](URL)", fr: "Insérer un lien markdown [texte](url)",
    ja: "マークダウンリンクを挿入 [テキスト](URL)", ru: "Вставить ссылку markdown [текст](url)",
    zh: "插入 Markdown 链接 [文本](url)"
  },
  "notes.editor.action.math": {
    es_ar: "Fórmula matemática (LaTeX)", es_es: "Fórmula matemática (LaTeX)",
    en: "Math formula (LaTeX)", pt: "Fórmula matemática (LaTeX)",
    de: "Mathematische Formel (LaTeX)", fr: "Formule mathématique (LaTeX)",
    ja: "数式 (LaTeX)", ru: "Математическая формула (LaTeX)",
    zh: "数学公式 (LaTeX)"
  }
};

function setDeep(obj, pathArr, value) {
  let cur = obj;
  for (let i = 0; i < pathArr.length - 1; i++) {
    const k = pathArr[i];
    if (!cur[k] || typeof cur[k] !== 'object') {
      cur[k] = {};
    }
    cur = cur[k];
  }
  cur[pathArr[pathArr.length - 1]] = value;
}

const catalogs = {};

for (const code of langCodes) {
  const jsonPath = path.join(i18nDir, code, 'notes.json');
  let data = {};
  if (fs.existsSync(jsonPath)) {
    data = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
  }

  for (const [fullKey, trMap] of Object.entries(translations)) {
    const val = trMap[code] || trMap['en'] || trMap['es_ar'];
    
    // Also set flat key for instant 1-step lookup
    data[fullKey] = val;

    // Set nested path
    if (fullKey.startsWith('notes.')) {
      const stripped = fullKey.substring(6);
      data[stripped] = val;
      setDeep(data, stripped.split('.'), val);
    } else {
      setDeep(data, fullKey.split('.'), val);
    }
  }

  fs.writeFileSync(jsonPath, JSON.stringify(data, null, 2) + '\n', 'utf8');
  catalogs[code] = data;
  console.log(`Updated ${code} (total keys: ${Object.keys(data).length})`);
}

// Write qml/I18nCatalogs.js
const catalogsJsContent = `.pragma library

const meta = ${JSON.stringify(meta, null, 2)};

const catalogs = ${JSON.stringify(catalogs, null, 2)};
`;

fs.writeFileSync(catalogsPath, catalogsJsContent, 'utf8');
console.log(`Successfully generated ${catalogsPath}`);
