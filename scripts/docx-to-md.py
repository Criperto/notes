#!/usr/bin/env -S python3 -B
# -*- coding: utf-8 -*-
"""docx-to-md.py — Conversor de Microsoft Word (.docx) a Markdown (.md)
con extracción de imágenes (FolderNotes), YAML frontmatter y reporte de progreso.

Uso:
    python3 -B docx-to-md.py --input "/ruta/documento.docx" --notes-dir "/home/u/Documentos/notes"
"""

import sys
sys.dont_write_bytecode = True

import os
import re
import subprocess
import datetime
import argparse
import zipfile
import xml.etree.ElementTree as ET

# Namespaces estándar OpenXML
NS = {
    'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
    'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
    'wp': 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
    'a': 'http://schemas.openxmlformats.org/drawingml/2006/main',
    'pic': 'http://schemas.openxmlformats.org/drawingml/2006/picture',
    'w14': 'http://schemas.microsoft.com/office/word/2010/wordml',
    'v': 'urn:schemas-microsoft-com:vml',
}

MONOSPACE_FONTS = {
    'consolas', 'courier', 'courier new', 'fira code', 'fira mono',
    'jetbrains mono', 'source code pro', 'monaco', 'menlo', 'inconsolata',
    'ubuntu mono', 'cascadia code', 'cascadia mono', 'monospace'
}


def report_progress(val: float, message: str = ""):
    val = max(0.0, min(1.0, float(val)))
    sys.stdout.write(f"PROGRESS:{val:.2f}\n")
    if message:
        sys.stdout.write(f"STATUS:{message}\n")
    sys.stdout.flush()


def sanitize_title(name: str) -> str:
    base = os.path.splitext(os.path.basename(name))[0]
    return base.strip()


def slugify(text: str) -> str:
    s = text.strip().lower()
    s = re.sub(r'[\/\\:*?"<>|\x00-\x1f\x7f¿¡]', ' ', s)
    s = re.sub(r'[\s\-_]+', '_', s)
    s = s.strip('_')
    return s[:80] if s else "nota"


def escape_markdown_inline(text: str) -> str:
    """Escapa caracteres conflictivos de markdown básico sin romper palabras."""
    return text.replace('\\', '\\\\')


def extract_numbering_info(docx_path: str):
    """Extrae formatos de lista (numFmt) desde word/numbering.xml si existe."""
    num_fmt_map = {}  # (numId, ilvl) -> 'bullet' | 'decimal' | etc.
    try:
        with zipfile.ZipFile(docx_path) as z:
            if 'word/numbering.xml' in z.namelist():
                tree = ET.fromstring(z.read('word/numbering.xml'))
                # abstractNumId -> {ilvl: numFmt}
                abstract_map = {}
                for abstract in tree.findall('.//w:abstractNum', NS):
                    abs_id = abstract.attrib.get(f"{{{NS['w']}}}abstractNumId")
                    if not abs_id:
                        continue
                    lvl_dict = {}
                    for lvl in abstract.findall('.//w:lvl', NS):
                        ilvl = lvl.attrib.get(f"{{{NS['w']}}}ilvl", "0")
                        num_fmt_elem = lvl.find('.//w:numFmt', NS)
                        if num_fmt_elem is not None:
                            lvl_dict[ilvl] = num_fmt_elem.attrib.get(f"{{{NS['w']}}}val", "decimal")
                    abstract_map[abs_id] = lvl_dict

                # numId -> abstractNumId
                for num in tree.findall('.//w:num', NS):
                    num_id = num.attrib.get(f"{{{NS['w']}}}numId")
                    abs_ref = num.find('.//w:abstractNumId', NS)
                    if num_id and abs_ref is not None:
                        abs_id = abs_ref.attrib.get(f"{{{NS['w']}}}val")
                        if abs_id in abstract_map:
                            for ilvl, fmt in abstract_map[abs_id].items():
                                num_fmt_map[(num_id, ilvl)] = fmt
    except Exception:
        pass
    return num_fmt_map


class DocxConverter:
    def __init__(self, docx_path: str, notes_dir: str, copy_mode: bool = True):
        self.docx_path = os.path.abspath(docx_path)
        self.notes_dir = os.path.abspath(notes_dir)
        self.copy_mode = copy_mode
        self.raw_title = sanitize_title(docx_path)
        self.slug = slugify(self.raw_title)
        self.num_fmt_map = extract_numbering_info(self.docx_path)
        self.num_counters = {}  # (numId, ilvl) -> current_number
        self.image_map = {}     # rId -> 'assets/imageX.ext'
        self.extracted_images = []
        self.is_folder_note = False
        self.target_dir = self.notes_dir
        self.assets_dir = ""

    def prepare_assets(self, doc):
        """Escanea e inspecciona imágenes dentro de document.xml.rels."""
        report_progress(0.15, "Inspeccionando imágenes del documento...")
        media_rels = {}
        for r_id, rel in doc.part.rels.items():
            if "image" in rel.target_ref or rel.reltype.endswith("/image"):
                media_rels[r_id] = rel

        if media_rels:
            self.is_folder_note = True
            # Resolver nombre único de carpeta de la nota si ya existe
            cand_folder = os.path.join(self.notes_dir, self.raw_title)
            n = 2
            while os.path.exists(cand_folder):
                cand_folder = os.path.join(self.notes_dir, f"{self.raw_title} ({n})")
                n += 1
            self.target_dir = cand_folder
            self.assets_dir = os.path.join(self.target_dir, "assets")
            os.makedirs(self.assets_dir, exist_ok=True)

            img_idx = 1
            total_media = len(media_rels)
            for r_id, rel in media_rels.items():
                try:
                    img_blob = rel.target_part.blob
                    filename = os.path.basename(rel.target_ref)
                    ext = os.path.splitext(filename)[1].lower() or ".png"
                    # Sanitizar extensión si es desconocida
                    if ext not in ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp', '.svg']:
                        ext = '.png'
                    out_name = f"img_{img_idx}{ext}"
                    out_path = os.path.join(self.assets_dir, out_name)
                    with open(out_path, 'wb') as f:
                        f.write(img_blob)
                    self.image_map[r_id] = f"assets/{out_name}"
                    self.extracted_images.append(out_path)
                    img_idx += 1
                    report_progress(0.15 + (0.25 * (img_idx / max(1, total_media))), f"Extrayendo imagen {img_idx-1} de {total_media}...")
                except Exception as e:
                    sys.stderr.write(f"Aviso: error extrayendo {r_id}: {e}\n")

    def _convert_run(self, run, r_id_lookup=None) -> str:
        """Convierte un Run de python-docx a fragmento Markdown con formato."""
        text = run.text or ""
        text = text.replace('\r', '')

        # Revisar si contiene imágenes incrustadas dentro del elemento w:drawing
        drawings = run._element.findall('.//w:drawing', NS)
        img_tags = []
        for drw in drawings:
            blips = drw.findall('.//a:blip', NS)
            doc_pr = drw.find('.//wp:docPr', NS)
            alt_text = doc_pr.attrib.get('descr', '') if doc_pr is not None else ''
            if not alt_text and doc_pr is not None:
                alt_text = doc_pr.attrib.get('name', '')
            if not alt_text:
                alt_text = "imagen"

            for blip in blips:
                r_id = blip.attrib.get(f"{{{NS['r']}}}embed")
                if r_id and r_id in self.image_map:
                    rel_src = self.image_map[r_id]
                    img_tags.append(f"\n![{alt_text}]({rel_src})\n")

        # Imágenes VML legacy (w:pict / v:imagedata)
        picts = run._element.findall('.//v:imagedata', NS)
        for pict in picts:
            r_id = pict.attrib.get(f"{{{NS['r']}}}id")
            if r_id and r_id in self.image_map:
                rel_src = self.image_map[r_id]
                img_tags.append(f"\n![imagen]({rel_src})\n")

        if not text and img_tags:
            return "".join(img_tags)
        if not text:
            return ""

        # Detección de estilos inline
        is_bold = bool(run.bold)
        is_italic = bool(run.italic)
        is_strike = bool(run.font.strike or run.font.double_strike)
        is_underline = bool(run.underline)
        
        # Resaltado / Highlight
        is_highlight = False
        try:
            if run.font.highlight_color is not None:
                is_highlight = True
        except Exception:
            pass
        if not is_highlight and run._element.find('.//w:highlight', NS) is not None:
            is_highlight = True

        # Fuente monoespaciada (código inline)
        is_code = False
        try:
            font_name = (run.font.name or "").lower()
            if any(m in font_name for m in MONOSPACE_FONTS):
                is_code = True
        except Exception:
            pass

        # Superíndice y subíndice
        is_super = bool(run.font.superscript)
        is_sub = bool(run.font.subscript)

        # Aplicación de decoraciones (respetando espacios en los extremos)
        lead_space = ""
        trail_space = ""
        m_lead = re.match(r'^(\s+)', text)
        if m_lead:
            lead_space = m_lead.group(1)
            text = text[len(lead_space):]
        m_trail = re.search(r'(\s+)$', text)
        if m_trail:
            trail_space = m_trail.group(1)
            text = text[:-len(trail_space)]

        if not text:
            return lead_space + "".join(img_tags) + trail_space

        # Código inline
        if is_code and not (is_bold or is_italic):
            res = f"`{text}`"
        else:
            res = text
            if is_super:
                res = f"^{res}^"
            elif is_sub:
                res = f"~{res}~"

            if is_underline:
                res = f"<u>{res}</u>"
            if is_strike:
                res = f"~~{res}~~"
            if is_highlight:
                res = f"=={res}=="
            if is_bold and is_italic:
                res = f"***{res}***"
            elif is_bold:
                res = f"**{res}**"
            elif is_italic:
                res = f"*{res}*"

        final_chunk = lead_space + res + trail_space
        if img_tags:
            final_chunk += "".join(img_tags)
        return final_chunk

    def _convert_paragraph_inline(self, paragraph) -> str:
        """Convierte los runs e hipervínculos de un párrafo preservando el orden."""
        parts = []
        for child in paragraph.iter_inner_content():
            # Si es Hyperlink
            if hasattr(child, 'address') or hasattr(child, 'url') or type(child).__name__ == 'Hyperlink':
                url = ""
                try:
                    if hasattr(child, 'url') and child.url:
                        url = child.url
                    elif hasattr(child, 'rId') and child.rId in paragraph.part.rels:
                        url = paragraph.part.rels[child.rId].target_ref
                    elif hasattr(child, 'address') and child.address:
                        url = child.address
                except Exception:
                    pass

                link_text_parts = []
                for sub_run in child.runs:
                    link_text_parts.append(self._convert_run(sub_run))
                link_text = "".join(link_text_parts).strip()
                if url and link_text:
                    parts.append(f"[{link_text}]({url})")
                elif link_text:
                    parts.append(link_text)
            elif hasattr(child, 'text'):
                parts.append(self._convert_run(child))

        raw = "".join(parts)
        # Limpiar tokens adyacentes redundantemente fragmentados (ej. **** -> vacío)
        raw = re.sub(r'\*\*\*\*', '', raw)
        return raw

    def _get_heading_level(self, paragraph) -> int:
        """Determina el nivel de encabezado (1..6) o 0 si es texto normal."""
        style_name = (paragraph.style.name or "").strip().lower()
        if style_name in ['title', 'título']:
            return 1
        if style_name in ['subtitle', 'subtítulo']:
            return 2
        m = re.match(r'^(?:heading|título|encabezado)\s*([1-6])', style_name)
        if m:
            return int(m.group(1))

        # xml outlineLvl
        pPr = paragraph._element.find('.//w:pPr', NS)
        if pPr is not None:
            outline = pPr.find('.//w:outlineLvl', NS)
            if outline is not None:
                val = outline.attrib.get(f"{{{NS['w']}}}val")
                if val and val.isdigit() and int(val) < 6:
                    return int(val) + 1
        return 0

    def _get_list_prefix(self, paragraph) -> tuple[str, str]:
        """Determina si el párrafo es un ítem de lista (viñeta, numerada, checklist).
        Devuelve (prefijo, tipo_lista: 'bullet'|'ordered'|'task'|'')
        """
        pPr = paragraph._element.find('.//w:pPr', NS)
        if pPr is None:
            return ("", "")
        numPr = pPr.find('.//w:numPr', NS)
        if numPr is None:
            # Fallback a nombre de estilo
            style_name = (paragraph.style.name or "").lower()
            if 'bullet' in style_name or 'viñeta' in style_name:
                return ("- ", "bullet")
            if 'number' in style_name or 'número' in style_name:
                return ("1. ", "ordered")
            return ("", "")

        ilvl_elem = numPr.find('.//w:ilvl', NS)
        numId_elem = numPr.find('.//w:numId', NS)
        ilvl = int(ilvl_elem.attrib.get(f"{{{NS['w']}}}val", "0")) if ilvl_elem is not None else 0
        numId = numId_elem.attrib.get(f"{{{NS['w']}}}val", "1") if numId_elem is not None else "1"

        indent = "  " * ilvl
        fmt = self.num_fmt_map.get((numId, str(ilvl)), "bullet")

        # Checkbox detección
        chk = pPr.find('.//w14:checkbox', NS)
        if chk is not None:
            checked = chk.find('.//w14:checked', NS)
            val = checked.attrib.get(f"{{{NS['w14']}}}val", "0") if checked is not None else "0"
            is_chk = (val == "1" or val.lower() == "true")
            mark = "x" if is_chk else " "
            return (f"{indent}- [{mark}] ", "task")

        # Texto inicial con símbolos de checkbox
        first_text = paragraph.text.strip()
        if first_text.startswith(('☐', '[ ]')):
            return (f"{indent}- [ ] ", "task")
        if first_text.startswith(('☑', '☒', '[x]', '[X]')):
            return (f"{indent}- [x] ", "task")

        if fmt in ['decimal', 'decimalZero', 'lowerLetter', 'upperLetter', 'lowerRoman', 'upperRoman']:
            key = (numId, ilvl)
            cur = self.num_counters.get(key, 0) + 1
            self.num_counters[key] = cur
            return (f"{indent}{cur}. ", "ordered")

        return (f"{indent}- ", "bullet")

    def _convert_table(self, table) -> str:
        """Convierte una tabla Word a tabla Markdown (GFM)."""
        rows = table.rows
        if not rows:
            return ""

        table_md = []
        num_cols = len(rows[0].cells)

        alignments = []
        for cell in rows[0].cells:
            # Deducir alineación por primer párrafo de celda
            align = "left"
            if cell.paragraphs:
                p_align = cell.paragraphs[0].alignment
                if p_align == 1: # CENTER
                    align = "center"
                elif p_align == 2: # RIGHT
                    align = "right"
            alignments.append(align)

        # Fila de cabecera
        header_cells = []
        for c in rows[0].cells:
            content = "<br>".join([self._convert_paragraph_inline(p).strip() for p in c.paragraphs if p.text.strip()])
            content = content.replace('|', '\\|')
            header_cells.append(content or " ")
        table_md.append("| " + " | ".join(header_cells) + " |")

        # Separador GFM con alineación
        sep_cells = []
        for a in alignments:
            if a == "center":
                sep_cells.append(":---:")
            elif a == "right":
                sep_cells.append("---:")
            else:
                sep_cells.append("---")
        table_md.append("| " + " | ".join(sep_cells) + " |")

        # Filas de datos
        for row in rows[1:]:
            row_cells = []
            for cell in row.cells:
                content = "<br>".join([self._convert_paragraph_inline(p).strip() for p in cell.paragraphs if p.text.strip()])
                content = content.replace('|', '\\|')
                row_cells.append(content or " ")
            # Asegurar longitud de columnas
            while len(row_cells) < num_cols:
                row_cells.append(" ")
            table_md.append("| " + " | ".join(row_cells[:num_cols]) + " |")

        return "\n" + "\n".join(table_md) + "\n\n"

    def convert(self) -> str:
        """Flujo maestro de conversión."""
        report_progress(0.05, "Cargando documento OpenXML...")
        try:
            import docx
        except ImportError:
            sys.stderr.write("MISSING_DEP:python-docx\n")
            sys.exit(2)

        doc = docx.Document(self.docx_path)
        self.prepare_assets(doc)

        report_progress(0.45, "Generando metadatos y frontmatter YAML...")

        # Metadatos del documento
        created_dt = None
        modified_dt = None
        try:
            cp = doc.core_properties
            created_dt = cp.created
            modified_dt = cp.modified
        except Exception:
            pass

        now = datetime.datetime.now()
        if not created_dt:
            try:
                created_dt = datetime.datetime.fromtimestamp(os.path.getctime(self.docx_path))
            except Exception:
                created_dt = now
        if not modified_dt:
            try:
                modified_dt = datetime.datetime.fromtimestamp(os.path.getmtime(self.docx_path))
            except Exception:
                modified_dt = now

        fmt_created = created_dt.strftime("%Y-%m-%d %H:%M:%S")
        fmt_modified = modified_dt.strftime("%Y-%m-%d %H:%M:%S")

        # YAML Frontmatter
        frontmatter_lines = [
            "---",
            f'title: "{self.raw_title}"',
            f'created: "{fmt_created}"',
            f'modified: "{fmt_modified}"',
            'type: "text"'
        ]

        # Extraer keywords como tags si existen
        try:
            if doc.core_properties.keywords:
                tags = [t.strip() for t in doc.core_properties.keywords.split(',') if t.strip()]
                if tags:
                    tags_str = ", ".join([f'"{t}"' for t in tags])
                    frontmatter_lines.append(f'tags: [{tags_str}]')
        except Exception:
            pass

        frontmatter_lines.append("---\n")
        body_parts = ["\n".join(frontmatter_lines)]

        # Recorrer el contenido principal iter_inner_content() en orden
        elements = list(doc.iter_inner_content())
        total_elems = len(elements)
        report_progress(0.50, "Convirtiendo párrafos, tablas y listas...")

        in_code_block = False
        code_block_lines = []

        for idx, elem in enumerate(elements):
            progress_val = 0.50 + (0.45 * (idx / max(1, total_elems)))
            if idx % 10 == 0:
                report_progress(progress_val)

            # Caso Tabla
            if type(elem).__name__ == 'Table' or hasattr(elem, 'rows'):
                if in_code_block:
                    body_parts.append("```\n" + "\n".join(code_block_lines) + "\n```\n\n")
                    in_code_block = False
                    code_block_lines = []
                body_parts.append(self._convert_table(elem))
                continue

            # Caso Párrafo
            p = elem
            style_name = (p.style.name or "").lower()

            # Detección de bloque de código
            is_code_style = any(k in style_name for k in ['code', 'preformatted', 'código'])
            if is_code_style:
                if not in_code_block:
                    in_code_block = True
                    code_block_lines = []
                code_block_lines.append(p.text)
                continue
            elif in_code_block:
                body_parts.append("```\n" + "\n".join(code_block_lines) + "\n```\n\n")
                in_code_block = False
                code_block_lines = []

            # Regla horizontal / Page break
            pBdr = p._element.find('.//w:pBdr', NS)
            has_bottom_border = pBdr is not None and pBdr.find('.//w:bottom', NS) is not None
            has_page_break = p._element.find('.//w:br[@w:type="page"]', NS) is not None
            if has_bottom_border or has_page_break:
                body_parts.append("\n---\n\n")
                if not p.text.strip():
                    continue

            # Nivel de Heading
            heading_lvl = self._get_heading_level(p)
            list_pfx, list_type = self._get_list_prefix(p)

            inline_content = self._convert_paragraph_inline(p).strip()

            # Limpiar checkboxes en el texto si ya fueron puestos por el prefijo
            if list_type == "task":
                inline_content = re.sub(r'^(?:\[[ xX]?\]|[☐☑☒])\s*', '', inline_content)

            if not inline_content and not p._element.findall('.//w:drawing', NS):
                # Párrafo vacío -> espacio vertical
                body_parts.append("\n")
                continue

            # Caso Heading en lista (soporte Typora: * ## Titulo)
            if list_pfx and heading_lvl > 0:
                h_pfx = "#" * heading_lvl
                body_parts.append(f"{list_pfx}{h_pfx} {inline_content}\n")
            elif list_pfx:
                body_parts.append(f"{list_pfx}{inline_content}\n")
            elif heading_lvl > 0:
                h_pfx = "#" * heading_lvl
                body_parts.append(f"\n{h_pfx} {inline_content}\n\n")
            elif 'quote' in style_name or 'cita' in style_name:
                body_parts.append(f"> {inline_content}\n\n")
            else:
                body_parts.append(f"{inline_content}\n\n")

        if in_code_block:
            body_parts.append("```\n" + "\n".join(code_block_lines) + "\n```\n\n")

        report_progress(0.96, "Escribiendo archivo Markdown final...")

        full_md = "".join(body_parts)
        # Normalizar triples saltos de línea a doble salto
        full_md = re.sub(r'\n{3,}', '\n\n', full_md)

        # Destino del archivo .md
        if self.is_folder_note:
            md_file_path = os.path.join(self.target_dir, f"{self.raw_title}.md")
        else:
            # Nota simple: resolver nombre si ya existe
            cand_md = os.path.join(self.notes_dir, f"{self.raw_title}.md")
            n = 2
            while os.path.exists(cand_md):
                cand_md = os.path.join(self.notes_dir, f"{self.raw_title} ({n}).md")
                n += 1
            md_file_path = cand_md

        with open(md_file_path, 'w', encoding='utf-8') as f:
            f.write(full_md)

        # Si se solicitó mover/borrar el origen:
        if not self.copy_mode:
            try:
                # Usar gio trash si está disponible para no destruir permanentemente
                ret = subprocess.run(["gio", "trash", self.docx_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                if ret.returncode != 0:
                    os.remove(self.docx_path)
            except Exception as e:
                sys.stderr.write(f"Aviso al quitar origen: {e}\n")

        report_progress(1.00, "¡Conversión completada con éxito!")
        sys.stdout.write(f"RESULT:{md_file_path}\n")
        sys.stdout.flush()
        return md_file_path


def main():
    parser = argparse.ArgumentParser(description="Conversor docx a md para Quickshell Notes")
    parser.add_argument("--input", "-i", required=True, help="Ruta al archivo .docx")
    parser.add_argument("--notes-dir", "-d", default="", help="Directorio base de notas")
    parser.add_argument("--mode", "-m", choices=["copy", "move"], default="copy", help="Modo de importación")
    args = parser.parse_args()

    input_file = os.path.expanduser(args.input)
    if not os.path.isfile(input_file):
        sys.stderr.write(f"Error: no existe el archivo {input_file}\n")
        sys.exit(1)

    notes_dir = os.path.expanduser(args.notes_dir) if args.notes_dir else os.path.dirname(input_file)
    if not os.path.isdir(notes_dir):
        os.makedirs(notes_dir, exist_ok=True)

    converter = DocxConverter(input_file, notes_dir, copy_mode=(args.mode == "copy"))
    out_file = converter.convert()
    print(f"Generado: {out_file}")


if __name__ == "__main__":
    main()
