#!/usr/bin/env -S python3 -B
# -*- coding: utf-8 -*-
"""make_import_samples.py — Generador de muestras de prueba para importación de Notas.
Crea una carpeta ~/Descargas/notes-import-samples/ con archivos listos para probar:
- muestra.docx
- muestra.odt
- muestra.epub
- muestra.html
- muestra.rtf
- muestra.csv
- muestra.tsv
- muestra.xlsx
- muestra.pdf
- Alicia_en_el_pais_de_las_maravillas.epub (libro real de dominio público de Gutenberg)
"""

import sys
sys.dont_write_bytecode = True

import os
import csv
import zipfile
import urllib.request
import subprocess


def get_samples_dir():
    home = os.path.expanduser("~")
    descargas = os.path.join(home, "Descargas")
    if not os.path.isdir(descargas):
        descargas = os.path.join(home, "Downloads")
        if not os.path.isdir(descargas):
            descargas = os.path.join(home, "Descargas")
    target_dir = os.path.join(descargas, "notes-import-samples")
    os.makedirs(target_dir, exist_ok=True)
    return target_dir


def create_sample_png(path: str):
    """Crea una imagen PNG válida mínima de 64x64 píxeles (azul/cyan) sin Pillow."""
    # Cabecera PNG de 64x64 con compresión zlib stdlib
    import zlib
    import struct

    width, height = 64, 64
    raw_data = bytearray()
    for y in range(height):
        raw_data.append(0)  # filter type 0
        for x in range(width):
            # Gradiente azul-cyan
            raw_data.extend([int(x * 3.5), int(y * 3.5), 220, 255])

    compressed = zlib.compress(bytes(raw_data))

    png = bytearray(b'\x89PNG\r\n\x1a\n')

    def make_chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

    ihdr = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    png.extend(make_chunk(b'IHDR', ihdr))
    png.extend(make_chunk(b'IDAT', compressed))
    png.extend(make_chunk(b'IEND', b''))

    with open(path, 'wb') as f:
        f.write(png)


def make_html_sample(target_dir: str):
    html_path = os.path.join(target_dir, "muestra.html")
    img_name = "muestra_grafico.png"
    img_path = os.path.join(target_dir, img_name)
    create_sample_png(img_path)

    content = f"""<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Muestra de Documento Web</title>
</head>
<body>
    <h1>Muestra de Documento Web HTML</h1>
    <p>Este documento demuestra la importación de archivos <strong>HTML/HTM</strong> en <em>Quickshell Notes</em>.</p>
    
    <h2>Sección 1: Formatos de Texto</h2>
    <p>Admite <strong>negrita</strong>, <em>cursiva</em>, <s>tachado</s>, <code>código en línea</code> y <a href="https://github.com">enlaces web</a>.</p>
    
    <blockquote>
        Esta es una cita en bloque importada desde HTML.
    </blockquote>

    <h2>Sección 2: Listas y Tablas</h2>
    <ul>
        <li>Elemento de lista con viñeta A</li>
        <li>Elemento de lista con viñeta B
            <ul>
                <li>Sub-elemento anidado 1</li>
                <li>Sub-elemento anidado 2</li>
            </ul>
        </li>
    </ul>

    <table border="1">
        <thead>
            <tr>
                <th>Herramienta</th>
                <th>Propósito</th>
                <th>Estado</th>
            </tr>
        </thead>
        <tbody>
            <tr>
                <td>Quickshell</td>
                <td>Entorno de escritorio</td>
                <td>Activo</td>
            </tr>
            <tr>
                <td>Markdown</td>
                <td>Formato de notas</td>
                <td>Soportado</td>
            </tr>
        </tbody>
    </table>

    <h2>Sección 3: Imágenes</h2>
    <p>A continuación una imagen local de prueba:</p>
    <img src="{img_name}" alt="Gráfico de muestra">
</body>
</html>
"""
    with open(html_path, "w", encoding="utf-8") as f:
        f.write(content)
    print(f"  ✓ Creado: {html_path}")


def make_rtf_sample(target_dir: str):
    rtf_path = os.path.join(target_dir, "muestra.rtf")
    # RTF estándar con texto enriquecido, negrita, cursiva, viñetas y tabla básica
    rtf_content = r"""{\rtf1\ansi\deff0
{\fonttbl{\f0\fnil\fcharset0 Arial;}}
\viewkind4\uc1\pard\lang1034\f0\fs28\b Muestra de Documento RTF\b0\fs22\par
\par
Este es un archivo \b Rich Text Format (.rtf)\b0  creado para verificar la importaci\'f3n en Quickshell Notes.\par
\par
\b Caracter\'edsticas soportadas:\b0\par
\bullet  Texto en \b negrita\b0  y \i cursiva\i0 .\par
\bullet  P\'e1rrafos y listas con vi\'f1etas.\par
\bullet  Caracteres con tildes y caracteres internacionales.\par
\par
\b Tabla b\'e1sica de ejemplo:\b0\par
\trowd\cellx2000\cellx4000\cellx6000
Par\'e1metro\cell Valor\cell Descripci\'f3n\cell\row
\trowd\cellx2000\cellx4000\cellx6000
Motor\cell Python stdlib\cell Sin paquetes externos\cell\row
\trowd\cellx2000\cellx4000\cellx6000
Formato\cell RTF 1.0\cell Compatible\cell\row
\par
}"""
    with open(rtf_path, "wb") as f:
        f.write(rtf_content.encode("latin-1"))
    print(f"  ✓ Creado: {rtf_path}")


def make_csv_sample(target_dir: str):
    csv_path = os.path.join(target_dir, "muestra.csv")
    data = [
        ["ID", "Producto", "Categoría", "Precio ARS", "Stock", "Estado"],
        ["101", "Teclado Mecánico", "Periféricos", "45000", "12", "En stock"],
        ["102", "Monitor 27 pulgadas", "Pantallas", "280000", "5", "Poco stock"],
        ["103", "Mouse Inalámbrico", "Periféricos", "32000", "28", "En stock"],
        ["104", "Auriculares Estudio", "Audio", "95000", "0", "Agotado"],
        ["105", "Brazo de Micrófono", "Accesorios", "24000", "15", "En stock"],
    ]
    with open(csv_path, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerows(data)
    print(f"  ✓ Creado: {csv_path}")


def make_tsv_sample(target_dir: str):
    tsv_path = os.path.join(target_dir, "muestra.tsv")
    data = [
        ["Servicio", "Puerto", "Protocolo", "Seguridad"],
        ["HTTP", "80", "TCP", "Plano"],
        ["HTTPS", "443", "TCP", "TLS 1.3"],
        ["SSH", "22", "TCP", "Cifrado ed25519"],
        ["DNS", "53", "UDP", "DoH opcional"],
    ]
    with open(tsv_path, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, delimiter="\t")
        writer.writerows(data)
    print(f"  ✓ Creado: {tsv_path}")


def make_odt_sample(target_dir: str):
    odt_path = os.path.join(target_dir, "muestra.odt")
    img_tmp = os.path.join(target_dir, "_temp_odt_img.png")
    create_sample_png(img_tmp)
    with open(img_tmp, 'rb') as f:
        img_bytes = f.read()
    try:
        os.remove(img_tmp)
    except Exception:
        pass

    content_xml = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0"
                         xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0"
                         xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0"
                         xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0"
                         xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0"
                         xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0"
                         xmlns:xlink="http://www.w3.org/1999/xlink"
                         office:version="1.2">
  <office:automatic-styles>
    <style:style style:name="BoldStyle" style:family="text">
      <style:text-properties fo:font-weight="bold"/>
    </style:style>
    <style:style style:name="ItalicStyle" style:family="text">
      <style:text-properties fo:font-style="italic"/>
    </style:style>
  </office:automatic-styles>
  <office:body>
    <office:text>
      <text:h text:outline-level="1">Documento OpenDocument (.odt)</text:h>
      <text:p>Este archivo fue generado para verificar el conversor nativo de <text:span text:style-name="BoldStyle">OpenDocument Text</text:span> sin requerir paquetes externos.</text:p>
      
      <text:h text:outline-level="2">Características de ODT</text:h>
      <text:p>Permite texto en <text:span text:style-name="ItalicStyle">cursiva</text:span>, enlaces a <text:a xlink:href="https://libreoffice.org">LibreOffice</text:a>, listas y tablas.</text:p>
      
      <text:list>
        <text:list-item><text:p>Primer elemento de lista ODT</text:p></text:list-item>
        <text:list-item><text:p>Segundo elemento con viñeta</text:p></text:list-item>
      </text:list>

      <table:table table:name="Tabla1">
        <table:table-row>
          <table:table-cell><text:p>Columna 1</text:p></table:table-cell>
          <table:table-cell><text:p>Columna 2</text:p></table:table-cell>
        </table:table-row>
        <table:table-row>
          <table:table-cell><text:p>Valor A</text:p></table:table-cell>
          <table:table-cell><text:p>Valor B</text:p></table:table-cell>
        </table:table-row>
      </table:table>

      <text:p>
        <draw:frame draw:name="Imagen1">
          <draw:image xlink:href="Pictures/muestra.png"/>
        </draw:frame>
      </text:p>
    </office:text>
  </office:body>
</office:document-content>"""

    manifest_xml = """<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
  <manifest:file-entry manifest:full-path="/" manifest:media-type="application/vnd.oasis.opendocument.text"/>
  <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
  <manifest:file-entry manifest:full-path="Pictures/muestra.png" manifest:media-type="image/png"/>
</manifest:manifest>"""

    with zipfile.ZipFile(odt_path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("mimetype", "application/vnd.oasis.opendocument.text", compress_type=zipfile.ZIP_STORED)
        z.writestr("META-INF/manifest.xml", manifest_xml)
        z.writestr("content.xml", content_xml)
        z.writestr("Pictures/muestra.png", img_bytes)
    print(f"  ✓ Creado: {odt_path}")


def make_epub_sample(target_dir: str):
    epub_path = os.path.join(target_dir, "muestra.epub")
    img_tmp = os.path.join(target_dir, "_temp_epub_img.png")
    create_sample_png(img_tmp)
    with open(img_tmp, 'rb') as f:
        img_bytes = f.read()
    try:
        os.remove(img_tmp)
    except Exception:
        pass

    container_xml = """<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>"""

    content_opf = """<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookID" version="2.0">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Libro de Prueba EPUB</dc:title>
    <dc:creator>Tomas</dc:creator>
    <dc:identifier id="BookID">urn:uuid:12345-67890</dc:identifier>
    <dc:language>es</dc:language>
  </metadata>
  <manifest>
    <item id="ch1" href="capitulo1.xhtml" media-type="application/xhtml+xml"/>
    <item id="ch2" href="capitulo2.xhtml" media-type="application/xhtml+xml"/>
    <item id="img1" href="images/portada.png" media-type="image/png"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="ch1"/>
    <itemref idref="ch2"/>
  </spine>
</package>"""

    ch1_xhtml = """<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Capítulo 1</title></head>
<body>
  <h1>Capítulo 1: El Comienzo</h1>
  <p>Este es el primer capítulo de un libro electrónico <strong>EPUB</strong>.</p>
  <p>La importación preserva la estructura de capítulos dividiéndolos con separadores horizontales en Markdown.</p>
  <p><img src="images/portada.png" alt="Ilustración"/></p>
</body>
</html>"""

    ch2_xhtml = """<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Capítulo 2</title></head>
<body>
  <h1>Capítulo 2: Características</h1>
  <p>El parser de EPUB lee el contenedor, el manifiesto y el orden de lectura (<em>spine</em>) automáticamente.</p>
  <ul>
    <li>Cero dependencias externas para EPUB</li>
    <li>Extrae imágenes a la subcarpeta de recursos</li>
    <li>Unifica los capítulos en una sola nota navegable</li>
  </ul>
</body>
</html>"""

    with zipfile.ZipFile(epub_path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml", container_xml)
        z.writestr("OEBPS/content.opf", content_opf)
        z.writestr("OEBPS/capitulo1.xhtml", ch1_xhtml)
        z.writestr("OEBPS/capitulo2.xhtml", ch2_xhtml)
        z.writestr("OEBPS/images/portada.png", img_bytes)
    print(f"  ✓ Creado: {epub_path}")


def make_docx_sample(target_dir: str):
    docx_path = os.path.join(target_dir, "muestra.docx")
    try:
        import docx
        doc = docx.Document()
        doc.add_heading("Documento de Prueba Microsoft Word (.docx)", 0)
        p = doc.add_paragraph("Este es un párrafo con texto en ")
        p.add_run("negrita").bold = True
        p.add_run(" y en ")
        p.add_run("cursiva").italic = True
        p.add_run(".")

        doc.add_heading("Sección de Listas", level=1)
        doc.add_paragraph("Primer punto importante", style='List Bullet')
        doc.add_paragraph("Segundo punto importante", style='List Bullet')

        doc.add_heading("Tabla de Muestra", level=2)
        table = doc.add_table(rows=1, cols=3)
        hdr_cells = table.rows[0].cells
        hdr_cells[0].text = "Elemento"
        hdr_cells[1].text = "Tipo"
        hdr_cells[2].text = "Notas"

        row_cells = table.add_row().cells
        row_cells[0].text = "Word"
        row_cells[1].text = ".docx"
        row_cells[2].text = "Soporta imágenes"

        img_tmp = os.path.join(target_dir, "_temp_docx_img.png")
        create_sample_png(img_tmp)
        doc.add_picture(img_tmp)
        try:
            os.remove(img_tmp)
        except Exception:
            pass

        doc.save(docx_path)
        print(f"  ✓ Creado: {docx_path}")
    except Exception as e:
        print(f"  ⚠️ No se pudo generar docx: {e}")


def make_xlsx_sample(target_dir: str):
    xlsx_path = os.path.join(target_dir, "muestra.xlsx")
    py_exec = "/tmp/qs-pdf-venv/bin/python" if os.path.isfile("/tmp/qs-pdf-venv/bin/python") else sys.executable
    script = f"""
import openpyxl
wb = openpyxl.Workbook()
ws1 = wb.active
ws1.title = "Ventas 2026"
ws1.append(["Mes", "Zona Norte", "Zona Sur", "Total"])
ws1.append(["Enero", 150000, 180000, 330000])
ws1.append(["Febrero", 165000, 192000, 357000])
ws1.append(["Marzo", 180000, 210000, 390000])

ws2 = wb.create_sheet(title="Servidores")
ws2.append(["Host", "IP", "Rol", "Estado"])
ws2.append(["node-01", "10.0.0.1", "Master", "Online"])
ws2.append(["node-02", "10.0.0.2", "Worker", "Online"])
ws2.append(["node-03", "10.0.0.3", "Worker", "Mantenimiento"])

wb.save("{xlsx_path}")
print("OK")
"""
    try:
        res = subprocess.run([py_exec, "-c", script], capture_output=True, text=True, check=True)
        print(f"  ✓ Creado: {xlsx_path}")
    except Exception as e:
        print(f"  ⚠️ No se pudo generar xlsx: {e}")


def make_pdf_sample(target_dir: str):
    pdf_path = os.path.join(target_dir, "muestra.pdf")
    py_exec = "/tmp/qs-pdf-venv/bin/python" if os.path.isfile("/tmp/qs-pdf-venv/bin/python") else sys.executable
    img_tmp = os.path.join(target_dir, "_temp_pdf_img.png")
    create_sample_png(img_tmp)

    script = f"""
import fitz
doc = fitz.open()

# Página 1: Títulos y contenido estructurado
page1 = doc.new_page(width=595, height=842)
page1.insert_text((50, 70), "Documento de Prueba PDF", fontsize=24, fontname="helv", color=(0.1, 0.2, 0.4))
page1.insert_text((50, 110), "Generado para pruebas de importación con PyMuPDF", fontsize=14, fontname="helv", color=(0.3, 0.3, 0.3))

page1.insert_text((50, 160), "1. Sección Principal", fontsize=18, fontname="helv", color=(0.15, 0.15, 0.15))
p1_text = (
    "Este archivo PDF contiene texto seleccionable con diferentes niveles de títulos,\\n"
    "listas con viñetas y formato en negrita. PyMuPDF analiza las fuentes\\n"
    "y tamaños para convertirlo en encabezados y párrafos de Markdown limpios."
)
page1.insert_text((50, 190), p1_text, fontsize=11, fontname="helv")

page1.insert_text((50, 270), "• Primer punto de lista en el documento PDF", fontsize=11, fontname="helv")
page1.insert_text((50, 290), "• Segundo punto de lista con información complementaria", fontsize=11, fontname="helv")
page1.insert_text((50, 310), "• Tercer punto con detalles adicionales", fontsize=11, fontname="helv")

page1.insert_image(fitz.Rect(50, 340, 180, 470), filename="{img_tmp}")

# Tabla simple dibujada con rectángulos para detección de Page.find_tables()
y = 520
page1.draw_rect(fitz.Rect(50, y, 450, y + 80), color=(0.5, 0.5, 0.5), width=1)
page1.draw_line((50, y + 25), (450, y + 25), color=(0.5, 0.5, 0.5), width=1)
page1.draw_line((180, y), (180, y + 80), color=(0.5, 0.5, 0.5), width=1)
page1.draw_line((310, y), (310, y + 80), color=(0.5, 0.5, 0.5), width=1)

page1.insert_text((60, y + 17), "Módulo", fontsize=11, fontname="helv")
page1.insert_text((190, y + 17), "Versión", fontsize=11, fontname="helv")
page1.insert_text((320, y + 17), "Estado", fontsize=11, fontname="helv")

page1.insert_text((60, y + 45), "PyMuPDF", fontsize=10, fontname="helv")
page1.insert_text((190, y + 45), "2.0", fontsize=10, fontname="helv")
page1.insert_text((320, y + 45), "Verificado", fontsize=10, fontname="helv")

page1.insert_text((60, y + 70), "Quickshell", fontsize=10, fontname="helv")
page1.insert_text((190, y + 70), "0.1.0", fontsize=10, fontname="helv")
page1.insert_text((320, y + 70), "Listo", fontsize=10, fontname="helv")

doc.save("{pdf_path}")
print("OK")
"""
    try:
        res = subprocess.run([py_exec, "-c", script], capture_output=True, text=True, check=True)
        print(f"  ✓ Creado: {pdf_path}")
    except Exception as e:
        print(f"  ⚠️ No se pudo generar pdf: {e}")
    finally:
        if os.path.exists(img_tmp):
            try:
                os.remove(img_tmp)
            except Exception:
                pass


def download_gutenberg_sample(target_dir: str):
    epub_name = "Alicia_en_el_pais_de_las_maravillas.epub"
    dest_path = os.path.join(target_dir, epub_name)
    url = "https://www.gutenberg.org/ebooks/11.epub.noimages"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=12) as response, open(dest_path, "wb") as out_file:
            out_file.write(response.read())
        print(f"  ✓ Descargado libro real: {dest_path}")
    except Exception as e:
        print(f"  ⚠️ No se pudo descargar libro de Gutenberg ({e}), usando muestra local.")


def main():
    target_dir = get_samples_dir()
    print(f"Generando muestras en: {target_dir}")
    make_html_sample(target_dir)
    make_rtf_sample(target_dir)
    make_csv_sample(target_dir)
    make_tsv_sample(target_dir)
    make_odt_sample(target_dir)
    make_epub_sample(target_dir)
    make_docx_sample(target_dir)
    make_xlsx_sample(target_dir)
    make_pdf_sample(target_dir)
    download_gutenberg_sample(target_dir)
    print("\n¡Todas las muestras han sido generadas y están listas para probar!")


if __name__ == "__main__":
    main()
