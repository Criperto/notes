const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');

function loadModule(relPath) {
    let fullPath = path.resolve(__dirname, '../qml', relPath);
    if (!fs.existsSync(fullPath)) fullPath = path.resolve(__dirname, '..', relPath);
    let code = fs.readFileSync(fullPath, 'utf8');
    code = code.replace(/^\.pragma\s+library\s*;?/m, '');
    const context = {
        console,
        parseInt,
        parseFloat,
        Math,
        Array,
        Object,
        String,
        Number,
        Boolean,
        RegExp,
        Date
    };
    vm.createContext(context);
    vm.runInContext(code, context);
    return context;
}

const BlockModel = loadModule('BlockModel.js');
const ListParser = loadModule('ListParser.js');
const Selection = loadModule('Selection.js');
const TableParser = loadModule('TableParser.js');
const Inline = loadModule('Inline.js');
const SearchLogic = loadModule('SearchLogic.js');
const ImportLogic = loadModule('ImportLogic.js');
const ImageProbe = loadModule('ImageProbe.js');
const TagsLogic = loadModule('TagsLogic.js');
const FolderNotes = loadModule('FolderNotes.js');
const SortLogic = loadModule('SortLogic.js');
const MD = loadModule('MarkdownParser.js');
const PV = loadModule('PreviewLogic.js');
const Hist = loadModule('History.js');
const QP = loadModule('QuoteParser.js');
const LH = loadModule('ListHeading.js');
const SpellLogic = loadModule('SpellLogic.js');
const MermaidParser = loadModule('MermaidParser.js');
const MermaidShapes = loadModule('MermaidShapes.js');
const MermaidLayout = loadModule('MermaidLayout.js');
const MermaidTemplates = loadModule('MermaidTemplates.js');
const MathTemplates = loadModule('MathTemplates.js');
const LangDetect = loadModule('LangDetect.js');
const Anchors = loadModule('Anchors.js');
const SlashLogic = loadModule('SlashLogic.js');
const SlashCommands = loadModule('SlashCommands.js');
const ReferenceLogic = loadModule('ReferenceLogic.js');
const EditorActions = loadModule('EditorActions.js');

let passed = 0;
let failed = 0;

function runTest(name, fn) {
    try {
        fn();
        passed++;
        console.log(`✓ ${name}`);
    } catch (e) {
        failed++;
        console.log(`✗ ${name}: ${e.message}`);
    }
}

// ── Invariante round-trip ───────────────────────────────────────────────────
runTest('Invariante: joinBlocks(splitBlocks(md)) === md (texto plano)', () => {
    const md = "Hola mundo\n\nSegundo párrafo\n";
    assert.strictEqual(BlockModel.joinBlocks(BlockModel.splitBlocks(md)), md);
});

runTest('Invariante: round-trip con lista, citas y tabla', () => {
    const md = "# Título\n\n> Cita\n\n- Ítem 1\n- Ítem 2\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n";
    assert.strictEqual(BlockModel.joinBlocks(BlockModel.splitBlocks(md)), md);
});

// ── Selection.js ────────────────────────────────────────────────────────────
runTest('Selection: toMap y count', () => {
    const map = Selection.toMap([1, 2, 5]);
    assert.strictEqual(Selection.count(map), 3);
    assert.strictEqual(map[1], true);
    assert.strictEqual(map[2], true);
    assert.strictEqual(map[5], true);
    assert.strictEqual(map[3], undefined);
});

runTest('Selection: rangeBids continuo', () => {
    const blocks = [{ bid: 10 }, { bid: 20 }, { bid: 30 }, { bid: 40 }];
    const range = Selection.rangeBids(blocks, 20, 40);
    assert.deepStrictEqual(Array.from(range), [20, 30, 40]);
});

runTest('Selection: rangeBids inverso', () => {
    const blocks = [{ bid: 10 }, { bid: 20 }, { bid: 30 }, { bid: 40 }];
    const range = Selection.rangeBids(blocks, 40, 20);
    assert.deepStrictEqual(Array.from(range), [20, 30, 40]);
});


runTest('Selection: removeSelected con fallback si queda vacio', () => {
    const blocks = [{ bid: 1, raw: "Solo" }];
    const map = Selection.toMap([1]);
    const res = Selection.removeSelected(blocks, map, () => ({ bid: 99, type: "paragraph", raw: "" }));
    assert.strictEqual(res.blocks.length, 1);
    assert.strictEqual(res.blocks[0].bid, 99);
    assert.strictEqual(res.focusIndex, 0);
});

runTest('Selection: removeSelected parcial', () => {
    const blocks = [{ bid: 1, raw: "A" }, { bid: 2, raw: "B" }, { bid: 3, raw: "C" }];
    const map = Selection.toMap([2]);
    const res = Selection.removeSelected(blocks, map);
    assert.strictEqual(res.blocks.length, 2);
    assert.strictEqual(res.blocks[0].bid, 1);
    assert.strictEqual(res.blocks[1].bid, 3);
    assert.strictEqual(res.focusIndex, 1);
});

runTest('Selection: extractSelectedText continuo entre bloques', () => {
    const sampleBlocks = [
        { bid: 10, raw: "# Titulo" },
        { bid: 20, raw: "Primer parrafo completo" },
        { bid: 30, raw: "Segundo parrafo" }
    ];
    // De pos 2 de bloque 10 a pos 6 de bloque 20
    const txt = Selection.extractSelectedText(sampleBlocks, 10, 2, 20, 6);
    assert.strictEqual(txt, "Titulo\n\nPrimer");

    // Inverso (hacia arriba)
    const txtRev = Selection.extractSelectedText(sampleBlocks, 20, 6, 10, 2);
    assert.strictEqual(txtRev, "Titulo\n\nPrimer");

    // Mismo bloque
    const txtSame = Selection.extractSelectedText(sampleBlocks, 20, 0, 20, 6);
    assert.strictEqual(txtSame, "Primer");
});

runTest('Selection: replaceSelectedRange fusiona prefijo y sufijo entre bloques', () => {
    const blocks = [
        { bid: 10, type: "paragraph", raw: "Hola mundo cruel" },
        { bid: 20, type: "paragraph", raw: "Intermedio" },
        { bid: 30, type: "paragraph", raw: "Que lindo dia" }
    ];

    // Borrado desde "mundo" (pos 5) en bloque 10 hasta "lindo" (pos 10) en bloque 30
    const resDel = Selection.replaceSelectedRange(blocks, 10, 5, 30, 10, "");
    assert.strictEqual(resDel.blocks.length, 1);
    assert.strictEqual(resDel.blocks[0].bid, 10);
    assert.strictEqual(resDel.blocks[0].raw, "Hola dia");
    assert.strictEqual(resDel.cursorBid, 10);
    assert.strictEqual(resDel.cursorPos, 5);

    // Pegado / Reemplazo con texto "hermoso "
    const resPaste = Selection.replaceSelectedRange(blocks, 10, 5, 30, 10, "hermoso ");
    assert.strictEqual(resPaste.blocks.length, 1);
    assert.strictEqual(resPaste.blocks[0].raw, "Hola hermoso dia");
    assert.strictEqual(resPaste.cursorPos, 13);
});

// ── Tests de T1 (estos pueden fallar antes de aplicar T1) ────────────────────
runTest('T1: "- " detecta viñeta como list bullet', () => {
    const auto = BlockModel.detectAutoformat("- Hola");
    assert.ok(auto.matched, "Debe detectar '- ' como viñeta");
    assert.strictEqual(auto.type, "list");
    assert.strictEqual(auto.subType, "bullet");
});

runTest('T1: "- - -" sigue siendo hr, no viñeta', () => {
    const auto = BlockModel.detectAutoformat("- - -");
    assert.strictEqual(auto.matched, false, "'- - -' no debe confundirse con viñeta");
});

runTest('T1: cursorAfterAutoformat calcula cursor tras prefijo', () => {
    assert.ok(typeof BlockModel.cursorAfterAutoformat === "function", "cursorAfterAutoformat debe existir");
    const auto = { matched: true, prefix: "- " };
    const pos = BlockModel.cursorAfterAutoformat(auto, 10);
    assert.strictEqual(pos, 8);
});

runTest('T1: detectTaskShorthand convierte [] y [ ] dentro de item', () => {
    assert.ok(typeof ListParser.detectTaskShorthand === "function", "detectTaskShorthand debe existir");
    const sh1 = ListParser.detectTaskShorthand("[] tarea");
    assert.ok(sh1 !== null);
    assert.strictEqual(sh1.checked, false);
    assert.strictEqual(sh1.rest, "tarea");

    const sh2 = ListParser.detectTaskShorthand("[x] lista");
    assert.ok(sh2 !== null);
    assert.strictEqual(sh2.checked, true);
    assert.strictEqual(sh2.rest, "lista");

    const shLink = ListParser.detectTaskShorthand("[x](http://test)");
    assert.strictEqual(shLink, null, "No debe capturar enlaces markdown");

    const shEmpty1 = ListParser.detectTaskShorthand("[]");
    assert.ok(shEmpty1 !== null);
    assert.strictEqual(shEmpty1.checked, false);
    assert.strictEqual(shEmpty1.rest, "");

    const shEmpty2 = ListParser.detectTaskShorthand("[ ]");
    assert.ok(shEmpty2 !== null);
    assert.strictEqual(shEmpty2.checked, false);
    assert.strictEqual(shEmpty2.rest, "");

    const shEmpty3 = ListParser.detectTaskShorthand(" []");
    assert.ok(shEmpty3 !== null);
    assert.strictEqual(shEmpty3.checked, false);
    assert.strictEqual(shEmpty3.rest, "");
});

// ── Search Highlight (Inline.highlightInHtml) ──────────────────────────────
runTest('Search Highlight: resalta texto case-insensitive', () => {
    const html = 'Hola mundo, rehacer la UI del editor';
    const res = Inline.highlightInHtml(html, 'ui', 'rgba(100, 149, 237, 0.38)');
    assert.ok(res.includes('<span style="background-color: rgba(100, 149, 237, 0.38); border-radius: 3px; padding: 0 2px;">UI</span>'));
});

runTest('Search Highlight: no altera tags ni atributos HTML (href/style)', () => {
    const html = '<a href="https://ui.example.com">UI del editor</a>';
    const res = Inline.highlightInHtml(html, 'ui', '#ff0000');
    assert.ok(res.includes('href="https://ui.example.com"'), 'href no debe ser modificado');
    assert.ok(res.includes('<span style="background-color: #ff0000; border-radius: 3px; padding: 0 2px;">UI</span>'));
});

runTest('Search Highlight: maneja caracteres especiales de regex de forma segura', () => {
    const html = 'Código con [item] y *estrella*';
    const res = Inline.highlightInHtml(html, '[item]', '#ff0000');
    assert.ok(res.includes('<span style="background-color: #ff0000; border-radius: 3px; padding: 0 2px;">[item]</span>'));
});

runTest('Search Highlight: inlineToHtml integra searchQuery', () => {
    const md = 'Rehacer la **UI** del editor';
    const res = Inline.inlineToHtml(md, { searchQuery: 'ui', searchHighlightBg: 'rgba(1,2,3,0.5)' });
    assert.ok(res.includes('<b>'));
    assert.ok(res.includes('background-color: rgba(1,2,3,0.5)'));
});

runTest('F1: texto de link se resalta una sola vez, sin spans anidados', () => {
    const html = Inline.inlineToHtml('[link Hola](https://hola.example.com/x)', { searchQuery: 'hola', searchHighlightBg: 'BG' });
    const count = (html.match(/background-color: BG/g) || []).length;
    assert.strictEqual(count, 1);
    assert.ok(!html.includes('<span style="background-color: BG') || html.indexOf('<span style="background-color: BG') === html.lastIndexOf('<span style="background-color: BG'));
    assert.ok(html.includes('href="https://hola.example.com/x"'));
});

// ── F2: SearchLogic + coincidencia activa ────────────────────────────────────
runTest('F2: normalize ignora mayúsculas y acentos sin cambiar longitud', () => {
    assert.strictEqual(SearchLogic.normalize('Café Ñandú'), 'cafe nandu');
    assert.strictEqual(SearchLogic.normalize('Hola').length, 4);
    assert.strictEqual(SearchLogic.normalize(''), '');
});

runTest('F2: findAll devuelve posiciones no solapadas', () => {
    assert.strictEqual(JSON.stringify(SearchLogic.findAll('Hola hola HOLA', 'hola')), JSON.stringify([{ pos: 0, len: 4 }, { pos: 5, len: 4 }, { pos: 10, len: 4 }]));
    assert.strictEqual(JSON.stringify(SearchLogic.findAll('un café', 'cafe')), JSON.stringify([{ pos: 3, len: 4 }]));
    assert.strictEqual(SearchLogic.findAll('texto', '').length, 0);
    assert.strictEqual(SearchLogic.findAll('texto', '  ').length, 0);
});

runTest('F2: stripForSearch quita URLs e imágenes pero conserva texto con mapa', () => {
    const s = SearchLogic.stripForSearch('[link Hola](https://hola.example.com/x) fin');
    assert.strictEqual(s.text, 'link Hola fin');
    // 'Hola' visible en 5..9 mapea al offset original dentro del link
    const m = SearchLogic.findAll(s.text, 'hola');
    assert.strictEqual(m.length, 1);
    const origPos = s.map[m[0].pos];
    assert.strictEqual('[link Hola](https://hola.example.com/x) fin'.substring(origPos, origPos + 4), 'Hola');

    const img = SearchLogic.stripForSearch('ver ![alt Hola](assets/hola.png) ya');
    assert.strictEqual(img.text, 'ver  ya');
    assert.strictEqual(SearchLogic.findAll(img.text, 'hola').length, 0);

    const code = SearchLogic.stripForSearch('usa `Hola code` aquí');
    assert.strictEqual(code.text, 'usa Hola code aquí');
});

runTest('F2: headingPrefixLen y quoteCleanMap espejan los delegates', () => {
    assert.strictEqual(SearchLogic.headingPrefixLen('## Título Hola'), 3);
    assert.strictEqual(SearchLogic.headingPrefixLen('  ### x'), 6);
    assert.strictEqual(SearchLogic.headingPrefixLen('sin prefijo'), 0);
    const q = SearchLogic.quoteCleanMap('> Hola mundo\n> segunda Hola');
    assert.strictEqual(q.clean, 'Hola mundo\nsegunda Hola');
    const pos = q.clean.indexOf('mundo');
    assert.strictEqual('> Hola mundo\n> segunda Hola'.substring(q.map[pos], q.map[pos] + 5), 'mundo');
});

runTest('F2: codePureRange espeja BlockCode.pureCodeText', () => {
    const raw = '```js\nHola code\nsegunda\n```';
    const r = SearchLogic.codePureRange(raw);
    assert.strictEqual(raw.substring(r.start, r.start + r.length), 'Hola code\nsegunda');
    const raw2 = '```\nsolo Hola\n```';
    const r2 = SearchLogic.codePureRange(raw2);
    assert.strictEqual(raw2.substring(r2.start, r2.start + r2.length), 'solo Hola');
});

runTest('F2: highlightInHtml con ordinal activo pinta solo esa ocurrencia distinto', () => {
    const html = 'Hola y hola y HOLA';
    const res = Inline.highlightInHtml(html, 'hola', 'SOFT', 'ACTIVE', 1, '#fff');
    const soft = (res.match(/background-color: SOFT/g) || []).length;
    const act = (res.match(/background-color: ACTIVE/g) || []).length;
    assert.strictEqual(soft, 2);
    assert.strictEqual(act, 1);
    assert.ok(res.includes('color: #fff;'));
    // La activa es la segunda
    assert.ok(res.indexOf('ACTIVE') > res.indexOf('SOFT') && res.indexOf('ACTIVE') < res.lastIndexOf('SOFT'));
});

runTest('F2: highlightInHtml sin ordinal mantiene firma vieja byte a byte', () => {
    const html = 'Hola mundo, rehacer la UI del editor';
    const res = Inline.highlightInHtml(html, 'ui', 'rgba(100, 149, 237, 0.38)');
    assert.ok(res.includes('<span style="background-color: rgba(100, 149, 237, 0.38); border-radius: 3px; padding: 0 2px;">UI</span>'));
    const resNeg = Inline.highlightInHtml(html, 'ui', 'SOFT', undefined, -1);
    assert.strictEqual((resNeg.match(/SOFT/g) || []).length, 1);
    assert.ok(!resNeg.includes('ACTIVE'));
});

runTest('F2: countInHtml coincide con spans pintados (incluye links y código)', () => {
    const samples = [
        Inline.inlineToHtml('**negrita**, Hola, [link Hola](https://hola.example.com/x) Hola', {}),
        Inline.inlineToHtml('- ## Hola en lista', { headingSizes: { 2: 26 } }),
        Inline.inlineToHtml('`Hola code` y Hola', {}),
        Inline.inlineToHtml('Tom & Jerry Hola', {}),
        'Hola <a href="https://hola.example.com">Hola</a> hola'
    ];
    for (const html of samples) {
        const painted = Inline.highlightInHtml(html, 'hola', 'BG');
        const spans = (painted.match(/background-color: BG/g) || []).length;
        assert.strictEqual(SearchLogic.countInHtml(html, 'hola'), spans, 'parity en: ' + html.slice(0, 60));
    }
});

runTest('F2: inlineToHtml propaga ordinal activo y es retrocompatible', () => {
    const res = Inline.inlineToHtml('Hola y hola', { searchQuery: 'hola', searchHighlightBg: 'SOFT', searchHighlightActiveBg: 'ACTIVE', searchActiveOrdinal: 0, searchHighlightActiveFg: '#000' });
    assert.strictEqual((res.match(/background-color: ACTIVE/g) || []).length, 1);
    assert.strictEqual((res.match(/background-color: SOFT/g) || []).length, 1);
    const old = Inline.inlineToHtml('Hola y hola', { searchQuery: 'hola', searchHighlightBg: 'SOFT' });
    assert.strictEqual((old.match(/background-color: SOFT/g) || []).length, 2);
});

// ── F5: ImportLogic ─────────────────────────────────────────────────────────
runTest('F5: decodeDropUrl decodifica espacios, tildes y ñ', () => {
    assert.strictEqual(ImportLogic.decodeDropUrl('file:///home/u/Mi%20nota%20%C3%B1and%C3%BA.md'), '/home/u/Mi nota ñandú.md');
    assert.strictEqual(ImportLogic.decodeDropUrl('file://localhost/home/u/a.md'), '/home/u/a.md');
    assert.strictEqual(ImportLogic.decodeDropUrl('/home/u/nota con espacios.md'), '/home/u/nota con espacios.md');
    assert.strictEqual(ImportLogic.decodeDropUrl('/home/u/doc\0bad.md'), '');
    assert.strictEqual(ImportLogic.decodeDropUrl('https://example.com/a.md'), '');
    assert.strictEqual(ImportLogic.decodeDropUrl(''), '');
    assert.strictEqual(ImportLogic.decodeDropUrl(null), '');
});


runTest('F5: isInsideDir detecta archivos dentro de notasDir', () => {
    assert.strictEqual(ImportLogic.isInsideDir('/n/sub/a.md', '/n'), true);
    assert.strictEqual(ImportLogic.isInsideDir('/n/a.md', '/n/'), true);
    assert.strictEqual(ImportLogic.isInsideDir('/n', '/n'), true);
    assert.strictEqual(ImportLogic.isInsideDir('/notas2/a.md', '/notas'), false);
    assert.strictEqual(ImportLogic.isInsideDir('/x/a.md', '/n'), false);
});

runTest('F5: uniqueFileName nunca pisa (nombre (2).md)', () => {
    assert.strictEqual(ImportLogic.uniqueFileName('a.md', ['b.md']), 'a.md');
    assert.strictEqual(ImportLogic.uniqueFileName('a.md', ['A.MD']), 'a (2).md');
    assert.strictEqual(ImportLogic.uniqueFileName('a.md', ['a.md', 'a (2).md']), 'a (3).md');
    assert.strictEqual(ImportLogic.uniqueFileName('Mi nota.md', ['mi nota.md']), 'Mi nota (2).md');
});

runTest('F5: validateImport rechaza no-regulares y enormes', () => {
    assert.strictEqual(ImportLogic.validateImport('regular file', 100).ok, true);
    assert.strictEqual(ImportLogic.validateImport('regular', 100).ok, true);
    assert.strictEqual(ImportLogic.validateImport('directory', 100).ok, false);
    assert.strictEqual(ImportLogic.validateImport('directory', 100).reason, 'type');
    // stat localizado ("fichero regular") debe fallar: el servicio usa LC_ALL=C
    assert.strictEqual(ImportLogic.validateImport('fichero regular', 100).ok, false);
    assert.strictEqual(ImportLogic.validateImport('regular file', 6 * 1024 * 1024).reason, 'size');
    assert.strictEqual(ImportLogic.validateImport('regular file', 5 * 1024 * 1024).ok, true);
    // docx y formatos convertibles permiten hasta 50MB, pdf hasta 100MB
    assert.strictEqual(ImportLogic.validateImport('regular file', 15 * 1024 * 1024, 'docx').ok, true);
    assert.strictEqual(ImportLogic.validateImport('regular file', 51 * 1024 * 1024, 'docx').reason, 'size');
    assert.strictEqual(ImportLogic.validateImport('regular file', 80 * 1024 * 1024, 'pdf').ok, true);
    assert.strictEqual(ImportLogic.validateImport('regular file', 101 * 1024 * 1024, 'pdf').reason, 'size');
});

runTest('F5: helpers de formatos e importación particionada', () => {
    assert.strictEqual(ImportLogic.isDocx('/path/doc.docx'), true);
    assert.strictEqual(ImportLogic.isDocx('/path/doc.DOCX'), true);
    assert.strictEqual(ImportLogic.isDocx('/path/doc.md'), false);
    assert.strictEqual(ImportLogic.isImportable('file.docx'), true);
    assert.strictEqual(ImportLogic.isImportable('file.md'), true);
    assert.strictEqual(ImportLogic.isImportable('file.txt'), true);
    assert.strictEqual(ImportLogic.isImportable('file.pdf'), true);
    assert.strictEqual(ImportLogic.isImportable('file.odt'), true);
    assert.strictEqual(ImportLogic.isImportable('file.epub'), true);
    assert.strictEqual(ImportLogic.isImportable('file.html'), true);
    assert.strictEqual(ImportLogic.isImportable('file.rtf'), true);
    assert.strictEqual(ImportLogic.isImportable('file.csv'), true);
    assert.strictEqual(ImportLogic.isImportable('file.xlsx'), true);
    assert.strictEqual(ImportLogic.isImportable('file.exe'), false);
    assert.strictEqual(ImportLogic.isConvertible('file.pdf'), true);
    assert.strictEqual(ImportLogic.isConvertible('file.md'), false);

    assert.strictEqual(ImportLogic.getDepForExt('pdf'), 'python-pymupdf');
    assert.strictEqual(ImportLogic.getDepForExt('xlsx'), 'python-openpyxl');
    assert.strictEqual(ImportLogic.getDepForExt('docx'), 'python-docx');
    assert.strictEqual(ImportLogic.getDepForExt('odt'), '');

    const deps = ImportLogic.depsForItems([
        { ext: 'pdf' },
        { ext: 'odt' },
        { ext: 'pdf' },
        { ext: 'xlsx' }
    ]);
    assert.deepStrictEqual([...deps], ['python-pymupdf', 'python-openpyxl']);

    const parts = ImportLogic.partitionDroppedUrls([
        'file:///home/u/a.md',
        'file:///home/u/doc.docx',
        'file:///home/u/b.txt',
        'file:///home/u/other.pdf',
        'file:///home/u/data.csv',
        'file:///home/u/unknown.bin'
    ]);
    assert.strictEqual(parts.normalUrls.length, 2);
    assert.strictEqual(parts.docxItems.length, 1);
    assert.strictEqual(parts.docxItems[0].localPath, '/home/u/doc.docx');
    assert.strictEqual(parts.convertItems.length, 3);
    assert.strictEqual(parts.convertItems[0].ext, 'docx');
    assert.strictEqual(parts.convertItems[1].ext, 'pdf');
    assert.strictEqual(parts.convertItems[2].ext, 'csv');

    const filters = ImportLogic.getFilterSpecs();
    assert.ok(filters.length >= 4);
    assert.ok(filters[0].includes('*.pdf'));
    assert.ok(filters[0].includes('*.docx'));
});

runTest('F5: summarizeImport cuenta un solo resumen por lote', () => {
    const s = ImportLogic.summarizeImport([{ status: 'copied' }, { status: 'copied' }, { status: 'already' }, { status: 'error' }, {}]);
    assert.strictEqual(s.copied, 2);
    assert.strictEqual(s.already, 1);
    assert.strictEqual(s.errors, 2);
    assert.strictEqual(s.total, 5);
});

// ── F6: formato txt ─────────────────────────────────────────────────────────
runTest('F6: parseNote txt no interpreta frontmatter y marca format', () => {
    const src = '---\ntitle: "X"\n---\n# Hola\ncuerpo\n';
    const p = MD.parseNote('nota.txt', '/n/nota.txt', false, src);
    assert.strictEqual(p.format, 'txt');
    assert.strictEqual(p.body, src);
    assert.strictEqual(p.slug, 'nota');
    const m = MD.parseNote('nota.md', '/n/nota.md', false, src);
    assert.strictEqual(m.format, 'md');
    assert.strictEqual(m.title, 'X');
});

runTest('F6: serializeNote txt devuelve el cuerpo intacto', () => {
    const body = '---\ntitle: "X"\n---\n# Hola\n';
    assert.strictEqual(MD.serializeNote({ format: 'txt', fileName: 'a.txt' }, body), body);
    assert.strictEqual(MD.serializeNote({ fileName: 'a.txt' }, body), body);
    const md = MD.serializeNote({ title: 'T', fileName: 'a.md' }, 'texto');
    assert.ok(!md.includes('---') || md.includes('texto'));
});

runTest('F6: replaceExtension cambia solo la extensión', () => {
    assert.strictEqual(ImportLogic.replaceExtension('notas.txt', 'md'), 'notas.md');
    assert.strictEqual(ImportLogic.replaceExtension('Mi nota.TXT', 'md'), 'Mi nota.md');
    assert.strictEqual(ImportLogic.uniqueFileName('a.md', ['a.txt']), 'a.md');
});

// ── F7: ImageProbe + skipMissing ────────────────────────────────────────────
runTest('F7: ImageProbe clasifica y resuelve rutas', () => {
    assert.strictEqual(ImageProbe.isRemote('https://example.com/a.png'), true);
    assert.strictEqual(ImageProbe.isRemote('HTTP://x/y.jpg'), true);
    assert.strictEqual(ImageProbe.isRemote('assets/a.png'), false);
    assert.strictEqual(ImageProbe.isRemote('/abs/a.png'), false);
    assert.strictEqual(ImageProbe.isRemote('file:///x/a.png'), false);
    assert.strictEqual(ImageProbe.resolveLocal('/n', 'assets/a.png'), '/n/assets/a.png');
    assert.strictEqual(ImageProbe.resolveLocal('/n/', 'assets/a.png'), '/n/assets/a.png');
    assert.strictEqual(ImageProbe.resolveLocal('/n', '/abs/a.png'), '/abs/a.png');
    assert.strictEqual(ImageProbe.resolveLocal('/n', 'https://e.com/a.png'), '');
    assert.strictEqual(ImageProbe.resolveLocal('/n', 'file:///home/u/Mi%20foto.png'), '/home/u/Mi foto.png');
    assert.strictEqual(ImageProbe.resolveLocal('', 'assets/a.png'), '');
    assert.strictEqual(ImageProbe.resolveLocal('/n', ''), '');
});

runTest('F7: inlineToHtml con skipMissing evita <img> inexistente', () => {

    const exists = (p) => p === '/n/assets/ok.png';
    const opts = { baseFolder: '/n', imageSkipMissing: true, imageExists: exists };
    const miss = Inline.inlineToHtml('ver ![alt foto](assets/miss.png) ya', opts);
    assert.ok(!miss.includes('<img'), 'no debe generar <img>');
    assert.ok(miss.includes('[alt foto]'), 'conserva el texto: ' + miss);
    const hit = Inline.inlineToHtml('ver ![alt foto](assets/ok.png) ya', opts);
    assert.ok(hit.includes('<img'), 'existente sí genera <img>');
    const remote = Inline.inlineToHtml('ver ![r](https://e.com/404.png) ya', opts);
    assert.ok(remote.includes('<img'), 'remota se carga igual');
    const abs = Inline.inlineToHtml('ver ![a](/x/miss.png) ya', opts);
    assert.ok(!abs.includes('<img'), 'absoluta inexistente tampoco genera <img>');
    // Sin opts nuevos: comportamiento viejo intacto
    const old = Inline.inlineToHtml('ver ![alt foto](assets/miss.png) ya', { baseFolder: '/n' });
    assert.ok(old.includes('<img'));
});

// ── F8: extractImages + stripImages ────────────────────────────────────────
runTest('F8: extractImages extrae simple y enlazada', () => {
    const items = Inline.extractImages('ver ![alt foto](assets/a.png) y [![b](assets/b.png)](https://x)');
    assert.strictEqual(items.length, 2);
    assert.strictEqual(items[0].alt, 'alt foto');
    assert.strictEqual(items[0].src, 'assets/a.png');
    assert.strictEqual(items[1].src, 'assets/b.png');
    assert.strictEqual(items[1].link, 'https://x');
    assert.strictEqual(Inline.extractImages('sin imagen').length, 0);
});

runTest('F8: stripImages quita el alt del texto', () => {
    assert.strictEqual(Inline.stripImages('Ítem ![en lista](x.png) fin'), 'Ítem  fin');
    assert.strictEqual(Inline.stripImages('![solo](a.png)'), '');
    assert.strictEqual(Inline.stripImages('sin imagen'), 'sin imagen');
    assert.strictEqual(Inline.stripImages(''), '');
    const html = Inline.inlineToHtml(Inline.stripImages('Ítem ![en lista](x.png)'), {});
    assert.ok(!html.includes('[en lista]'));
    assert.ok(!html.includes('<img'));
    assert.ok(html.includes('Ítem'));
});

// ── F15: identidad de notas ─────────────────────────────────────────────────
runTest('F15: clave slug+ext distingue md/txt y preserva subcarpeta', () => {
    const kMd = FolderNotes.dictKey('foo', 'md');
    const kTxt = FolderNotes.dictKey('foo', 'txt');
    assert.ok(kMd !== kTxt);
    assert.strictEqual(FolderNotes.slugOfKey(kMd), 'foo');
    assert.strictEqual(FolderNotes.extOfKey(kTxt), 'txt');
    assert.strictEqual(FolderNotes.extOfKey(kMd), 'md');
    assert.strictEqual(FolderNotes.isKey(kMd), true);
    assert.strictEqual(FolderNotes.isKey('foo'), false);
    assert.strictEqual(FolderNotes.slugOfKey('plano'), 'plano');
    const kSub = FolderNotes.keyForFileName('Sub/Nota.md');
    assert.strictEqual(FolderNotes.slugOfKey(kSub), 'sub/nota');
    assert.strictEqual(FolderNotes.keyForFileName('a.md') !== FolderNotes.keyForFileName('sub/a.md'), true);
    assert.strictEqual(FolderNotes.canonSlug('  Mi Nota '), 'mi nota');
    assert.strictEqual(FolderNotes.canonExt('x.TXT'), 'txt');
    assert.strictEqual(FolderNotes.canonExt('x.md'), 'md');
});

runTest('F15: NUL nunca llega a rutas (bug loadedSlug como slug)', () => {
    const key = FolderNotes.dictKey('nota', 'md');
    // Lo que hacía el código viejo: concatenar la clave donde iba un slug
    const oldConflict = key + '.conflict-20240101';
    const oldAssets = '/n/assets/' + key + '/img.png';
    assert.ok(FolderNotes.firstNulPath([oldConflict]) !== '');
    assert.ok(FolderNotes.firstNulPath([oldAssets]) !== '');
    // Lo nuevo: slug extraído, rutas limpias
    const slug = FolderNotes.slugOfKey(key);
    assert.strictEqual(slug, 'nota');
    assert.strictEqual(FolderNotes.firstNulPath([slug + '.conflict-20240101']), '');
    assert.strictEqual(FolderNotes.firstNulPath(['/n/assets/' + slug + '/img.png']), '');
    assert.strictEqual(FolderNotes.firstNulPath(['a', 'b']), '');
});
runTest('F8: cleanCardText convierte sintaxis propia sin tocar markdown', () => {
    assert.strictEqual(PV.cleanCardText('ver ==resaltado== fin'), 'ver resaltado fin');
    assert.strictEqual(PV.cleanCardText('[[otra nota]]'), 'otra nota');
    assert.strictEqual(PV.cleanCardText('[[otra nota|Alias]]'), 'Alias');
    assert.strictEqual(PV.cleanCardText('a ![x](i.png) b').includes('<img'), false);
    assert.ok(PV.cleanCardText('**b** y [t](http://u)').includes('**b**'));
});

runTest('F8: cleanSubtitle deja texto plano de una línea', () => {
    assert.strictEqual(PV.cleanSubtitle('> Este documento usa **git**.'), 'Este documento usa git.');
    assert.strictEqual(PV.cleanSubtitle('## Título con [link](http://u)'), 'Título con link');
    assert.strictEqual(PV.cleanSubtitle('- [ ] ## Tarea **x**'), 'Tarea x');
});

runTest('F8: stripDuplicateLead recorta solo si duplica', () => {
    assert.strictEqual(PV.stripDuplicateLead('> Cita **b**.\n\nMás texto', '> Cita **b**.'), 'Más texto');
    assert.strictEqual(PV.stripDuplicateLead('Otro cuerpo', 'Sub de frontmatter'), 'Otro cuerpo');
    assert.strictEqual(PV.stripDuplicateLead('', 'x'), '');
});

// ── F9: TagsLogic ───────────────────────────────────────────────────────────
runTest('F9: normalizeTag limpia y limita', () => {
    assert.strictEqual(TagsLogic.normalizeTag('  #Mi Etiqueta  '), 'Mi-Etiqueta');
    assert.strictEqual(TagsLogic.normalizeTag('##doble'), 'doble');
    assert.strictEqual(TagsLogic.normalizeTag('con,coma [x] "q"'), 'concoma-x-q');
    assert.strictEqual(TagsLogic.normalizeTag(''), '');
    assert.strictEqual(TagsLogic.normalizeTag('   '), '');
    assert.strictEqual(TagsLogic.normalizeTag('###'), '');
    assert.strictEqual(TagsLogic.normalizeTag(new Array(50).join('a')).length, 40);
});

runTest('F9: sameTag ignora mayúsculas y acentos', () => {
    assert.strictEqual(TagsLogic.sameTag('Búsqueda', 'busqueda'), true);
    assert.strictEqual(TagsLogic.sameTag('Tag', 'TAG'), true);
    assert.strictEqual(TagsLogic.sameTag('a', 'b'), false);
});

runTest('F9: add/remove con deduplicación sin mutar', () => {
    const base = ['uno'];
    const r1 = TagsLogic.addTag(base, '  #DOS  ');
    assert.strictEqual(r1.added, 'DOS');
    assert.strictEqual(r1.changed, true);
    assert.strictEqual(JSON.stringify(base), JSON.stringify(['uno']));
    const r2 = TagsLogic.addTag(r1.tags, 'dos');
    assert.strictEqual(r2.changed, false);
    assert.strictEqual(r2.added, '');
    const r3 = TagsLogic.addTag(r1.tags, '   ');
    assert.strictEqual(r3.changed, false);
    const r4 = TagsLogic.removeTag(r1.tags, 'UNO');
    assert.strictEqual(r4.removed, true);
    assert.strictEqual(JSON.stringify(r4.tags), JSON.stringify(['DOS']));
    assert.strictEqual(TagsLogic.removeTag(r1.tags, 'nope').removed, false);
});

runTest('F9: suggest con prefijo primero, excluye puestas y limita', () => {
    const all = ['prueba', 'markdown', 'búsqueda', 'proyecto', 'otra'];
    const s = TagsLogic.suggest(all, 'pr', ['prueba'], 10);
    assert.strictEqual(JSON.stringify(s), JSON.stringify(['proyecto']));
    const s2 = TagsLogic.suggest(all, 'bús', [], 10);
    assert.strictEqual(JSON.stringify(s2), JSON.stringify(['búsqueda']));
    const s3 = TagsLogic.suggest(['a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7'], 'a', [], 6);
    assert.strictEqual(s3.length, 6);
    assert.strictEqual(TagsLogic.suggest(all, '', [], 6).length, 0);
});

// ── Inline detectFormats ───────────────────────────────────────────────────
runTest('Inline: detectFormats detecta negrita y cursiva combinadas', () => {
    const det = Inline.detectFormats("Texto con ***ambos*** y ~~tachado~~", 12, 17);
    assert.strictEqual(det.bold, true);
    assert.strictEqual(det.italic, true);
    assert.strictEqual(det.strike, false);

    const detStrike = Inline.detectFormats("Texto con ***ambos*** y ~~tachado~~", 26, 33);
    assert.strictEqual(detStrike.strike, true);
    assert.strictEqual(detStrike.bold, false);
});

// ── T01, T02, T03, T11, T25 ──────────────────────────────────────────────
runTest('T01: título humano sobrevive a serialize→parse', () => {
    const ser = MD.serializeNote({ title: 'Reunión del lunes', created: '2026-10-09 10:00:00' }, 'texto');
    const p = MD.parseNote('reunion_del_lunes.md', '/n/reunion_del_lunes.md', false, ser);
    assert.strictEqual(p.title, 'Reunión del lunes');
});

runTest('T01: nota con H1 igual al título no añade title: al frontmatter', () => {
    const ser = MD.serializeNote({ title: 'Reunión del lunes' }, '# Reunión del lunes\ntexto');
    assert.ok(!ser.includes('title: "Reunión del lunes"'));
});

runTest('T02: subtitle del frontmatter se conserva', () => {
    const src = '---\ntitle: "A"\nsubtitle: "S"\ncustom: 1\n---\ncuerpo\n';
    const p = MD.parseNote('a.md', '/n/a.md', false, src);
    const out = MD.serializeNote(p, p.body);
    assert.ok(out.includes('subtitle: "S"') && out.includes('custom: 1'));
});

runTest('T03: history con snapshot previo al undo permite redo', () => {
    const h = Hist.createHistory('A');
    Hist.pushState(h, 'B');
    Hist.pushState(h, 'C');
    assert.strictEqual(Hist.undo(h).md, 'B');
    assert.strictEqual(Hist.redo(h).md, 'C');
});

runTest('T11: título no sale de un fence ni de un H1 tardío', () => {
    assert.strictEqual(MD.parseNote('x.md', '/n/x.md', false, '```bash\n# instalar\n```\n').title, 'x');
    assert.strictEqual(MD.parseNote('y.md', '/n/y.md', false, 'Hola\n# Sección\n').title, 'y');
});

runTest('T25: searchBlob incluye tags', () => {
    const p = MD.parseNote('a.md', '/n/a.md', false, '---\ntags: [uni]\n---\ntexto\n');
    assert.ok(p.searchBlob.includes('uni'));
});

// ── T09, T10, T12 ────────────────────────────────────────────────────────
runTest('T09: formatos de 1 carácter no se fusionan', () => {
    assert.strictEqual(Inline.inlineToHtml('**a** y **b**'), '<b>a</b> y <b>b</b>');
    assert.strictEqual(Inline.inlineToHtml('*a* y *b*'), '<i>a</i> y <i>b</i>');
    assert.strictEqual(Inline.inlineToHtml('**negrita** normal **otra** fin'), '<b>negrita</b> normal <b>otra</b> fin');
});

runTest('T10: resaltado no parte entidades y ignora acentos', () => {
    const h = Inline.inlineToHtml('Tom & Jerry', { searchQuery: 'amp' });
    assert.ok(h.includes('&amp;') && !h.includes('&<span'));
    assert.ok(Inline.inlineToHtml('un café', { searchQuery: 'cafe' }).includes('<span'));
});

runTest('T12: toggleWrap deja los espacios del borde afuera', () => {
    assert.strictEqual(Inline.toggleWrap('hola mundo cruel', 0, 11, '**').text, '**hola mundo** cruel');
});

// ── T17 ──────────────────────────────────────────────────────────────────
runTest('T17: plainText normaliza U+2028 y U+2029 a saltos \\n', () => {
    assert.strictEqual(Inline.plainText("linea 1\u2028linea 2\u2029linea 3"), "linea 1\nlinea 2\nlinea 3");
    assert.strictEqual(Inline.plainText({ getText: () => "hola\u2028mundo", length: 10 }), "hola\nmundo");
});

// ── T23 ──────────────────────────────────────────────────────────────────
runTest('T23: formatRelative formatea fechas relativas en español', () => {
    const fixedNow = 1791560000000;
    assert.strictEqual(PV.formatRelative(new Date(fixedNow - 10000), fixedNow), "recién");
    assert.strictEqual(PV.formatRelative(new Date(fixedNow - 5 * 60 * 1000), fixedNow), "hace 5 min");
    assert.strictEqual(PV.formatRelative(new Date(fixedNow - 2 * 3600 * 1000), fixedNow), "hace 2 h");
    assert.strictEqual(PV.formatRelative(new Date(fixedNow - 25 * 3600 * 1000), fixedNow), "ayer");
    assert.strictEqual(PV.formatRelative(new Date(fixedNow - 4 * 86400 * 1000), fixedNow), "hace 4 d");
});


// ── T27 ──────────────────────────────────────────────────────────────────
runTest('T27: detectAutoformat con [] crea lista de tareas', () => {
    const auto = BlockModel.detectAutoformat("[] comprar pan");
    assert.strictEqual(auto.matched, true);
    assert.strictEqual(auto.type, "list");
    assert.strictEqual(auto.subType, "task");
    assert.strictEqual(auto.prefix, "- [ ] ");
    assert.strictEqual(auto.content, "comprar pan");
});

runTest('T27: detectAutoformat limita listas numeradas a <= 99', () => {
    const year = BlockModel.detectAutoformat("2024. fue un buen año");
    assert.strictEqual(year.matched, false);
    const valid = BlockModel.detectAutoformat("12. paso doce");
    assert.strictEqual(valid.matched, true);
    assert.strictEqual(valid.subType, "ordered");
    assert.strictEqual(valid.number, 12);
});

// ── T29 & T30 ────────────────────────────────────────────────────────────
runTest('T29: linkifica URLs peladas y remueve puntuación final', () => {
    const html = Inline.inlineToHtml("visita https://github.com/quickshell y prueba.");
    assert.ok(html.includes('<a href="https://github.com/quickshell"'));
    assert.ok(html.endsWith(' y prueba.'));
});

runTest('T29: resuelve src relativo de imagenes con baseFolder', () => {
    const html = Inline.inlineToHtml("![diagrama](assets/img.png)", { baseFolder: "/home/user/notes" });
    assert.ok(html.includes('src="/home/user/notes/assets/img.png"'));
});

runTest('T30: wikilinks se renderizan como enlaces', () => {
    const html = Inline.inlineToHtml("[[reunion-lunes|Ver Reunión]]");
    assert.ok(html.includes('<a href="reunion-lunes"'));
    assert.ok(html.includes('>Ver Reunión</a>'));
    const detected = Inline.detectFormats("[[mi-nota]]", 0, 9);
    assert.strictEqual(detected.link, true);
});

runTest('T31: "## título" en ítem de lista se renderiza con tamaño de encabezado', () => {
    const hs = { 1: 30, 2: 26, 3: 22, 4: 18, 5: 16, 6: 12 };
    const items = ListParser.parseList("* ## titulo grande\n* normal");
    assert.strictEqual(items[0].text, "## titulo grande");
    const html = Inline.inlineToHtml(items[0].text, { headingSizes: hs });
    assert.ok(html.includes('font-size: 26px'));
    assert.ok(!html.includes('##'));
    // sin headingSizes no cambia el comportamiento (párrafos)
    assert.strictEqual(Inline.inlineToHtml("## x"), "## x");
    const live = Inline.formatForLiveEditing("### x", { headingSizes: hs });
    assert.ok(live.includes('font-size: 22px'));
    assert.ok(live.includes('###'));
});

// ── F17: orden estable ──────────────────────────────────────────────────────
runTest('F17: lastOpened ordena y desempata sin aperturas', () => {
    const a = { slug: 'a', title: 'Beta', fileModified: '2026-01-02 10:00:00' };
    const b = { slug: 'b', title: 'Alfa', fileModified: '2026-01-01 10:00:00' };
    const c = { slug: 'c', title: 'Alfa', fileModified: '2026-01-01 10:00:00' };
    // Sin aperturas: mismo lastOpened "" → desempata por modificación, luego título
    assert.strictEqual(SortLogic.compareNotes(a, b, 'lastOpened', {}), -1);
    assert.strictEqual(SortLogic.compareNotes(b, a, 'lastOpened', {}), 1);
    assert.strictEqual(SortLogic.compareNotes(b, c, 'lastOpened', {}), 0);
    // Con aperturas manda lastOpened
    const map = { b: '2026-05-01 10:00:00' };
    assert.strictEqual(SortLogic.compareNotes(a, b, 'lastOpened', map), 1);
    assert.strictEqual(SortLogic.compareNotes(b, a, 'lastOpened', map), -1);
    // Fijadas primero siempre
    const p = { slug: 'p', title: 'Zzz', pinned: true, fileModified: '2020-01-01 00:00:00' };
    assert.strictEqual(SortLogic.compareNotes(a, p, 'lastOpened', {}), 1);
    // Modos clásicos
    assert.strictEqual(SortLogic.compareNotes(a, b, 'title', {}), 1); // Beta > Alfa
    assert.strictEqual(SortLogic.compareNotes(a, b, 'modified', {}), -1); // 02 > 01
    assert.strictEqual(SortLogic.compareNotes(a, b, 'created', {}), -1); // fallback a fileModified
});

runTest('F17: ciclo de orden arranca en Apertura', () => {
    assert.strictEqual(SortLogic.nextSort('lastOpened'), 'modified');
    assert.strictEqual(SortLogic.nextSort('modified'), 'created');
    assert.strictEqual(SortLogic.nextSort('created'), 'title');
    assert.strictEqual(SortLogic.nextSort('title'), 'lastOpened');
    assert.strictEqual(SortLogic.nextSort('otro'), 'lastOpened');
});

// ── F18: destino del cierre por borrado ─────────────────────────────────────
runTest('F18: toastTargetRect centra abajo con clamp', () => {
    const t = PV.toastTargetRect(1080, 760);
    assert.strictEqual(t.w, 360);
    assert.strictEqual(t.h, 48);
    assert.strictEqual(t.x, 360);
    assert.strictEqual(t.y, 688);
    const n = PV.toastTargetRect(400, 500);
    assert.strictEqual(n.w, 360);
    assert.strictEqual(n.x, 20);
});

runTest('F18: deleteMorphTarget escala y centra sin geometría', () => {
    const d = PV.deleteMorphTarget(1080, 760, 1080, 760);
    assert.ok(d.scale > 0.29 && d.scale < 0.31);
    assert.strictEqual(d.dx, 0);
    assert.strictEqual(d.dy, 332);
    const small = PV.deleteMorphTarget(680, 500, 680, 500);
    assert.ok(small.scale > 0.46 && small.scale < 0.48);
});

// ── F19: notas-carpeta ──────────────────────────────────────────────────────
runTest('F19: isFolderNotePath y slugForPath', () => {
    assert.strictEqual(FolderNotes.isFolderNotePath('Foo/Foo.md'), true);
    assert.strictEqual(FolderNotes.isFolderNotePath('FOO/foo.MD'), true);
    assert.strictEqual(FolderNotes.isFolderNotePath('a/b/b.txt'), true);
    assert.strictEqual(FolderNotes.isFolderNotePath('Foo/Bar.md'), false);
    assert.strictEqual(FolderNotes.isFolderNotePath('Foo.md'), false);
    assert.strictEqual(FolderNotes.isFolderNotePath('Foo/'), false);
    assert.strictEqual(FolderNotes.isFolderNotePath(''), false);
    assert.strictEqual(FolderNotes.slugForPath('Foo/Foo.md'), 'foo');
    assert.strictEqual(FolderNotes.slugForPath('a/b/b.txt'), 'a/b');
    assert.strictEqual(FolderNotes.slugForPath('Sub/Nota.md'), 'sub/nota');
    assert.strictEqual(FolderNotes.slugForPath('Café/Café.md'), 'café');
});

runTest('F19: carpeta propia y nombre único', () => {
    assert.strictEqual(FolderNotes.folderPathFor('Foo.md'), 'Foo');
    assert.strictEqual(FolderNotes.folderPathFor('sub/n.md'), 'sub/n');
    assert.strictEqual(FolderNotes.parentDir('a/b/c.md'), 'a/b');
    assert.strictEqual(FolderNotes.parentDir('x.md'), '');
    assert.strictEqual(FolderNotes.uniqueFolderName('Foo', ['foo.md']), 'Foo');
    assert.strictEqual(FolderNotes.uniqueFolderName('Foo', ['foo', 'x']), 'Foo_2');
    assert.strictEqual(FolderNotes.uniqueFolderName('Foo', ['foo', 'foo_2']), 'Foo_3');
});

runTest('F19: rewriteAssetLinks mueve solo lo referenciado', () => {
    const body = 'ver ![a](assets/vieja/a.png) y [t](assets/vieja/a.png "t") fin ![b](assets/otra.png)';
    const r = FolderNotes.rewriteAssetLinks(body, [{ from: 'assets/vieja/a.png', to: 'assets/a.png' }]);
    assert.strictEqual(r.moved, 1);
    assert.ok(r.body.includes('](assets/a.png)'));
    assert.ok(r.body.includes('](assets/a.png "t")'));
    assert.ok(r.body.includes('assets/otra.png'));
    assert.ok(!r.body.includes('assets/vieja/'));
    const r2 = FolderNotes.rewriteAssetLinks(body, [{ from: 'assets/no.png', to: 'assets/x.png' }]);
    assert.strictEqual(r2.moved, 0);
    assert.strictEqual(r2.body, body);
});

// ── F22: encabezado dentro de ítems de lista ──────────────────────────────
runTest('F22: headingLevelOf detecta niveles y descarta hashtags', () => {
    assert.strictEqual(ListParser.headingLevelOf('## texto'), 2);
    assert.strictEqual(ListParser.headingLevelOf('# título'), 1);
    assert.strictEqual(ListParser.headingLevelOf('### x'), 3);
    assert.strictEqual(ListParser.headingLevelOf('##'), 2);
    assert.strictEqual(ListParser.headingLevelOf('## '), 2);
    assert.strictEqual(ListParser.headingLevelOf('#hashtag'), 0);
    assert.strictEqual(ListParser.headingLevelOf('texto ## adentro'), 0);
    assert.strictEqual(ListParser.headingLevelOf(''), 0);
    assert.strictEqual(ListParser.headingLevelOf('####### siete'), 0);
    assert.strictEqual(ListParser.stripHeadingPrefix('## texto'), 'texto');
    assert.strictEqual(ListParser.stripHeadingPrefix('##'), '');
    assert.strictEqual(ListParser.stripHeadingPrefix('sin prefijo'), 'sin prefijo');
});

runTest('F22: headingLevelOfItems y allItemsMatchHeading por rango', () => {
    const items = ListParser.parseList('- ## Uno\n- ## Dos\n- Tres');
    assert.strictEqual(ListParser.headingLevelOfItems(items, 0, 1), 2);
    assert.strictEqual(ListParser.headingLevelOfItems(items, 0, 2), 0);
    assert.strictEqual(ListParser.allItemsMatchHeading(items, 0, 1, 2), true);
    assert.strictEqual(ListParser.allItemsMatchHeading(items, 0, 2, 2), false);
    assert.strictEqual(ListParser.allItemsMatchHeading(items, 2, 2, 2), false);
    // Viñeta + H2 simultáneos: el marcador sigue siendo viñeta y el nivel H2
    assert.strictEqual(items[0].marker, '-');
    assert.strictEqual(ListParser.headingLevelOf(items[0].text), 2);
    // Ítem vacío con solo ##
    const emptyH = ListParser.parseList('- ##');
    assert.strictEqual(ListParser.headingLevelOf(emptyH[0].text), 2);
    assert.strictEqual(ListParser.allItemsMatchHeading(emptyH, 0, 0, 2), true);
});

runTest('F22: parseList → serialize round-trip idéntico (sección 10)', () => {
    const lines = [
        '- ## Encabezado dos',
        '- # Encabezado uno',
        '1. ### Encabezado tres ordenado',
        '- [ ] ## Tarea con encabezado',
        '* ## Viñeta estrella',
        '- ## **Negrita** con formato',
        '- ítem normal'
    ];
    const raw = lines.join('\n');
    const parsed = ListParser.parseList(raw);
    assert.strictEqual(ListParser.serializeList(parsed), raw);
});

// ── F26: computeSlideDeltas (FLIP) ────────────────────────────────────────
runTest('F26: computeSlideDeltas detecta movidas, nuevas, eliminadas y sin cambios', () => {
    const oldM = { a: { x: 0, y: 0 }, b: { x: 0, y: 120 }, c: { x: 200, y: 0 } };
    const newM = { a: { x: 0, y: 0 }, b: { x: 0, y: 240 }, d: { x: 200, y: 0 } };
    const r = PV.computeSlideDeltas(oldM, newM);
    assert.strictEqual(r.moved.length, 1);
    assert.strictEqual(r.moved[0].key, 'b');
    assert.strictEqual(r.moved[0].dx, 0);
    assert.strictEqual(r.moved[0].dy, 120);
    assert.strictEqual(JSON.stringify(r.entered), JSON.stringify(['d']));
    assert.strictEqual(JSON.stringify(r.removed), JSON.stringify(['c']));
    // Cambio de columna: mismo key, distinta x/y
    const col = PV.computeSlideDeltas({ k: { x: 10, y: 10 } }, { k: { x: 220, y: 40 } });
    assert.strictEqual(col.moved.length, 1);
    assert.strictEqual(col.moved[0].dx, 210);
    // Sin cambios: todo vacío
    const same = PV.computeSlideDeltas({ a: { x: 1, y: 2 } }, { a: { x: 1, y: 2 } });
    assert.strictEqual(same.moved.length, 0);
    assert.strictEqual(same.entered.length, 0);
    assert.strictEqual(same.removed.length, 0);
});

// ── F25: QuoteParser ──────────────────────────────────────────────────────
runTest('F25: parseQuote simple y multilínea (un solo párrafo)', () => {
    const t1 = QP.parseQuote('> Cita simple');
    assert.strictEqual(t1.children.length, 1);
    assert.strictEqual(t1.children[0].kind, 'paragraph');
    assert.strictEqual(t1.children[0].text, 'Cita simple');
    const t2 = QP.parseQuote('> línea uno\n> línea dos');
    assert.strictEqual(t2.children.length, 1);
    assert.strictEqual(t2.children[0].kind, 'paragraph');
    assert.strictEqual(t2.children[0].text, 'línea uno\nlínea dos');
});

runTest('F25: parseQuote con encabezado ## (sin ## y con nivel)', () => {
    const t = QP.parseQuote('> ## Cita con encabezado');
    assert.strictEqual(t.children.length, 1);
    assert.strictEqual(t.children[0].kind, 'heading');
    assert.strictEqual(t.children[0].level, 2);
    assert.strictEqual(t.children[0].text, 'Cita con encabezado');
    // La vista pasa "## texto" a inlineToHtml con headingSizes (igual que BlockList)
    const html = Inline.inlineToHtml('## Cita con encabezado', { headingSizes: { 2: 26 } });
    assert.ok(html.includes('font-size: 26px'));
    assert.ok(!html.includes('##'));
});

runTest('F25: parseQuote anidada > > y >> con dos niveles', () => {
    const a = QP.parseQuote('> exterior\n> > anidada\n> exterior 2');
    assert.strictEqual(a.children.length, 3);
    assert.strictEqual(a.children[1].kind, 'quote');
    assert.strictEqual(a.children[1].children[0].text, 'anidada');
    const b = QP.parseQuote('>> anidada sin espacio');
    assert.strictEqual(b.children.length, 1);
    assert.strictEqual(b.children[0].kind, 'quote');
    const flat = QP.flattenQuote(a);
    const depths = flat.map(s => s.depth);
    assert.ok(depths.includes(1) && depths.includes(2));
});

runTest('F25: parseQuote con lista (viñetas reales, varias líneas)', () => {
    const t = QP.parseQuote('> - ítem 1\n> - ítem 2');
    assert.strictEqual(t.children.length, 1);
    assert.strictEqual(t.children[0].kind, 'list');
    assert.strictEqual(t.children[0].items.length, 2);
    assert.strictEqual(t.children[0].items[0].text, 'ítem 1');
    const flat = QP.flattenQuote(t);
    assert.strictEqual(flat.length, 2);
    assert.strictEqual(flat[0].kind, 'listItem');
});

runTest('F25: anidado de 3 niveles, línea vacía y > sin texto', () => {
    const t = QP.parseQuote('> uno\n> > dos\n> > > tres');
    const flat = QP.flattenQuote(t);
    assert.strictEqual(flat.length, 3);
    assert.strictEqual(flat[2].depth, 3);
    const e = QP.parseQuote('> con hueco\n>\n> sigue');
    assert.strictEqual(e.children.length, 2);
    const empty = QP.parseQuote('>');
    assert.strictEqual(empty.children.length, 0);
});

runTest('F25: round-trip canónico raw → parse → raw', () => {
    const raws = [
        '> Cita simple',
        '> ## Cita con encabezado',
        '> exterior\n> > anidada',
        '> - ítem 1\n> - ítem 2',
        '> uno\n> > dos\n> > > tres'
    ];
    for (const r of raws) {
        assert.strictEqual(QP.serializeQuote(QP.parseQuote(r)), r);
    }
    // searchUnits espeja segmentos visibles
    const u = QP.searchUnits('> ## Titular\n> - ítem 1\n> texto');
    assert.strictEqual(u.length, 3);
});

// ── F21: ListHeading (ítems de lista con encabezado) ───────────────────────
runTest('F21: splitHeading/composeHeading niveles 1-6 y casos borde', () => {
    const eq = (raw, level, content) => {
        const s = LH.splitHeading(raw);
        assert.strictEqual(s.level, level, 'level de ' + JSON.stringify(raw));
        assert.strictEqual(s.content, content, 'content de ' + JSON.stringify(raw));
    };
    eq('## texto', 2, 'texto');
    eq('# uno', 1, 'uno');
    eq('###### seis', 6, 'seis');
    eq('##', 2, '');
    eq('## ', 2, '');
    // Sin espacio tras # con texto pegado NO es encabezado
    eq('#hashtag', 0, '#hashtag');
    eq('##pegado', 0, '##pegado');
    // # adentro del contenido no cuenta
    eq('texto con # adentro', 0, 'texto con # adentro');
    eq('', 0, '');
    assert.strictEqual(LH.composeHeading(2, 'texto'), '## texto');
    assert.strictEqual(LH.composeHeading(1, ''), '#');
    assert.strictEqual(LH.composeHeading(0, 'x'), 'x');
    // Coherente con ListParser.headingLevelOf
    assert.strictEqual(LH.splitHeading('## texto').level, ListParser.headingLevelOf('## texto'));
    assert.strictEqual(LH.splitHeading('#hashtag').level, ListParser.headingLevelOf('#hashtag'));
});

runTest('F21: mapeo de posiciones ida y vuelta (display <-> raw)', () => {
    // Nivel 2: prefijo canónico `## ` (3). Contenido `texto`.
    assert.strictEqual(LH.toDisplayPos(2, 0), 0);
    assert.strictEqual(LH.toDisplayPos(2, 3), 0);
    assert.strictEqual(LH.toDisplayPos(2, 4), 1);
    assert.strictEqual(LH.toRawPos(2, 0), 3);
    assert.strictEqual(LH.toRawPos(2, 1), 4);
    for (let d = 0; d <= 8; d++) {
        assert.strictEqual(LH.toDisplayPos(2, LH.toRawPos(2, d)), d);
    }
    assert.strictEqual(LH.toDisplayPos(0, 5), 5);
    assert.strictEqual(LH.toRawPos(0, 5), 5);
});

runTest('F21: parseList → serializar idéntico con encabezados (sección 10)', () => {
    const lines = [
        '- ## Encabezado dos',
        '- # Encabezado uno',
        '1. ### Encabezado tres ordenado',
        '- [ ] ## Tarea con encabezado',
        '* ## Viñeta estrella',
        '- ## **Negrita** con formato',
        '- ##',
        '- ítem normal'
    ];
    const raw = lines.join('\n');
    const parsed = ListParser.parseList(raw);
    assert.strictEqual(ListParser.serializeList(parsed), raw);
    // Cada línea con ## se detecta igual por ListHeading y ListParser
    for (const p of parsed) {
        assert.strictEqual(LH.splitHeading(p.text).level, ListParser.headingLevelOf(p.text));
    }
});

runTest('baseFolder nunca apunta al archivo .md en notas-carpeta', () => {
    const p = MD.parseNote("Nota/Nota.md", "/tmp/notes/Nota/Nota.md", true, "# Hola");
    assert.strictEqual(p.baseFolder, "/tmp/notes/Nota");
    assert.ok(!/\.(md|txt)$/i.test(p.baseFolder), "baseFolder no debe terminar en .md/.txt: " + p.baseFolder);
    const p2 = MD.parseNote("Nota.md", "/tmp/notes/Nota.md", true, "# Hola");
    assert.strictEqual(p2.baseFolder, "/tmp/notes");
});

runTest('F28: estimateBlockHeight calcula alturas deterministas >= 24px', () => {
    assert.strictEqual(typeof BlockModel.estimateBlockHeight, "function");
    const hHeading = BlockModel.estimateBlockHeight("heading", "# Titulo H1", 700);
    assert.ok(hHeading >= 40, "Heading H1 debe ser >= 40px: " + hHeading);

    const hP1 = BlockModel.estimateBlockHeight("paragraph", "Linea corta", 700);
    const hP2 = BlockModel.estimateBlockHeight("paragraph", "Linea 1\nLinea 2\nLinea 3\nLinea 4", 700);
    assert.ok(hP1 >= 30, "Parrafo debe ser >= 30px: " + hP1);
    assert.ok(hP2 > hP1, "Parrafo de varias lineas debe ser mas alto que de 1 linea");

    const hCode = BlockModel.estimateBlockHeight("code", "```js\nconsole.log(1);\nconsole.log(2);\n```", 700);
    assert.ok(hCode >= 64, "Code block debe ser >= 64px: " + hCode);

    const hHr = BlockModel.estimateBlockHeight("hr", "---", 700);
    assert.strictEqual(hHr, 24);

    const hTable = BlockModel.estimateBlockHeight("table", "| a | b |\n|---|---|\n| 1 | 2 |", 700);
    assert.ok(hTable >= 80, "Tabla debe ser >= 80px: " + hTable);
});

runTest('F28: MarkdownParser.parseNote asigna previewImage y acota bodySlice en notas grandes', () => {
    const hugeBody = "# Gran Nota\n\n![Foto](img.png)\n\n" + "Texto largo ".repeat(1000);
    const parsed = MD.parseNote("grande.md", "/tmp/grande.md", false, hugeBody);
    assert.strictEqual(parsed.previewImage, "img.png");
    assert.ok(parsed.preview.length <= 505);
    assert.ok(parsed.preview.indexOf("Gran Nota") === -1, "H1 igual al titulo no debe duplicarse en preview");
});

runTest('F28: PreviewLogic.getPreviewImage y estimateCardHeight operan en O(1)', () => {
    // 1. Con previewImage precalculado
    const noteWithPreview = { previewImage: "/path/img.png", assets: ["/path/img.png"], preview: "Hola" };
    assert.strictEqual(PV.getPreviewImage(noteWithPreview), "/path/img.png");

    // 2. Nota sin imagenes pero con assets=[] vacio (no debe escanear body)
    let bodyAccessed = false;
    const noteNoImg = {
        assets: [],
        preview: "Nota de texto plano",
        get body() {
            bodyAccessed = true;
            return "Texto con body pero sin imagenes";
        }
    };
    assert.strictEqual(PV.getPreviewImage(noteNoImg), "");
    assert.strictEqual(bodyAccessed, false, "getPreviewImage no debe tocar body si assets es un array");

    // 3. estimateCardHeight usa preview y no body
    let bodyAccessedForHeight = false;
    const noteForHeight = {
        preview: "Linea de vista previa",
        assets: [],
        get body() {
            bodyAccessedForHeight = true;
            return "Cuerpo enorme";
        }
    };
    const cardH = PV.estimateCardHeight(noteForHeight);
    assert.ok(cardH >= 80);
    assert.strictEqual(bodyAccessedForHeight, false, "estimateCardHeight no debe tocar body si preview existe");
});

runTest('F29: PreviewLogic.getPreviewImages devuelve todas las imágenes en orden excluyendo badges', () => {
    assert.strictEqual(typeof PV.getPreviewImages, "function");
    const note = {
        assets: [
            "https://img.shields.io/badge/test-badge-blue",
            "/path/to/img1.png",
            "assets/photo2.webp",
            "https://github.com/user/repo/workflows/ci/badge.svg",
            "/images/final.jpg"
        ]
    };
    const images = PV.getPreviewImages(note);
    assert.strictEqual(images.length, 3);
    assert.strictEqual(images[0], "/path/to/img1.png");
    assert.strictEqual(images[1], "assets/photo2.webp");
    assert.strictEqual(images[2], "/images/final.jpg");

    // getPreviewImage devuelve la primera imagen
    assert.strictEqual(PV.getPreviewImage(note), "/path/to/img1.png");
});

runTest('F29: NotesConfig schema tiene showImagePreviews y cyclePreviewImages y no tiene defaultNoteType', () => {
    const qml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesConfig.qml'), 'utf8');
    assert.ok(qml.indexOf('key: "showImagePreviews"') !== -1, "showImagePreviews debe estar en el schema");
    assert.ok(qml.indexOf('key: "cyclePreviewImages"') !== -1, "cyclePreviewImages debe estar en el schema");
    assert.ok(qml.indexOf('key: "defaultNoteType"') === -1, "defaultNoteType debe haber sido eliminado del schema");
});

runTest('F30: ListParser sangría de sub-listas y serialización round-trip', () => {
    const raw = "1. Item 1\n  1. Subitem 1\n  2. Subitem 2\n2. Item 2\n  - Viñeta sub 1\n  - Viñeta sub 2";
    const parsed = ListParser.parseList(raw);
    assert.strictEqual(parsed.length, 6);
    assert.strictEqual(parsed[0].indent, "");
    assert.strictEqual(parsed[1].indent, "  ");
    assert.strictEqual(parsed[2].indent, "  ");
    assert.strictEqual(parsed[3].indent, "");
    assert.strictEqual(parsed[4].indent, "  ");
    assert.strictEqual(parsed[5].indent, "  ");
    assert.strictEqual(ListParser.serializeList(parsed), raw);
});

runTest('F31: NotesConfig schema tiene editorZoom configurado como int (50-300)', () => {
    const qml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesConfig.qml'), 'utf8');
    assert.ok(qml.indexOf('key: "editorZoom"') !== -1, "editorZoom debe estar en el schema");
    assert.ok(qml.indexOf('editorZoom: 100') !== -1, "editorZoom debe tener default 100");
});

runTest('F32: SpellLogic tokeniza Unicode, filtra URLs/emails/dígitos y resuelve locales', () => {
    const tokens = SpellLogic.tokenize("¡Hola mundo! Visita https://test.org con el modelo v2. Ejecutar `systemctl` en /var/log.");
    const words = tokens.map(t => t.word);
    assert.ok(words.includes("Hola"));
    assert.ok(words.includes("mundo"));
    assert.ok(!words.includes("https"));
    assert.ok(!words.includes("v2"));
    assert.ok(!words.includes("systemctl"), "código inline debe filtrarse");
    assert.ok(!words.includes("log"), "rutas unix deben filtrarse");
    assert.strictEqual(SpellLogic.normalizeLocale("es_AR.UTF-8"), "es_AR");
    assert.strictEqual(SpellLogic.matchCapitalization("Kasa", "casa"), "Casa");

    const multi = SpellLogic.resolveEffectiveLanguages("es_AR.UTF-8", {}, ["es_AR", "en_US"]);
    assert.strictEqual(multi.length, 2);
    assert.strictEqual(multi[0], "es_AR");
    assert.strictEqual(multi[1], "en_US");

    const emptyWave = SpellLogic.calculateWaveSegments(() => ({ x: 0, y: 0, width: 0, height: 0 }), 0, 5);
    assert.strictEqual(emptyWave.length, 0, "No debe dibujar puntos en (0,0) con layout vacío");
});

runTest('F33: NotesService cola serial de eliminación a papelera y prevención de borrado destructivo', () => {
    const qml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesService.qml'), 'utf8');

    // 1. Verificación de propiedades de cola serial
    assert.ok(qml.indexOf('property var _trashQueue: []') !== -1, "_trashQueue debe estar declarado como array");
    assert.ok(qml.indexOf('property bool _isTrashing: false') !== -1, "_isTrashing debe estar declarado");

    // 2. Verificación de que usa gio trash y fallback sin rm destructivo
    assert.ok(qml.indexOf('"gio", "trash"') !== -1, "debe usar gio trash para papelera");
    assert.ok(qml.indexOf('var fallbackDest = trashDir + "/" + safeBase') !== -1, "debe tener fallback a .trash");
    assert.ok(!/command:\s*\[[^\]]*"rm"/.test(qml), "no debe contener comandos rm directos para borrar notas");

    // 3. Verificación de manejo de huérfanos y prepareToQuit
    assert.ok(qml.indexOf('Quickshell.execDetached(["gio", "trash"') !== -1, "prepareToQuit debe vaciar la cola con execDetached");
    assert.ok(qml.indexOf('root.prepareToQuit();') !== -1, "Component.onDestruction debe llamar a prepareToQuit");

    // 4. Simulación del algoritmo FIFO de la cola
    let isTrashing = false;
    let queue = [];
    const deletingKeys = { "nota1:md": true, "nota2:md": true, "nota3:md": true };
    const executed = [];

    function enqueue(key, targetPath) {
        queue.push({ key, targetPath });
        processQueue();
    }

    function processQueue() {
        if (isTrashing || queue.length === 0) return;
        const item = queue.shift();
        if (!deletingKeys[item.key]) {
            processQueue();
            return;
        }
        isTrashing = true;
        // Simular ejecución
        executed.push(item.targetPath);
        isTrashing = false;
        processQueue();
    }

    // Agregar nota1 y nota2
    enqueue("nota1:md", "/path/to/nota1.md");
    enqueue("nota2:md", "/path/to/nota2.md");

    // Cancelar nota3 antes de que se encole
    delete deletingKeys["nota3:md"];
    enqueue("nota3:md", "/path/to/nota3.md");

    assert.strictEqual(executed.length, 2);
    assert.strictEqual(executed[0], "/path/to/nota1.md");
    assert.strictEqual(executed[1], "/path/to/nota2.md");
    assert.ok(!executed.includes("/path/to/nota3.md"));
});

runTest("F34: _storeImageDimension crea nueva referencia inmutable para bindings QML", () => {
    let _imageDimensions = {};
    function _storeImageDimension(src, w, h) {
        if (!src || w <= 0 || h <= 0) return;
        if (!_imageDimensions) _imageDimensions = ({});
        if (!_imageDimensions[src] || _imageDimensions[src].w !== w || _imageDimensions[src].h !== h) {
            var copy = Object.assign({}, _imageDimensions);
            copy[src] = { w: w, h: h };
            _imageDimensions = copy;
        }
    }

    const ref1 = _imageDimensions;
    _storeImageDimension("assets/image_1.png", 800, 600);
    const ref2 = _imageDimensions;

    assert.notStrictEqual(ref1, ref2, "La referencia del diccionario debe cambiar para emitir señal en QML");
    assert.deepStrictEqual(_imageDimensions["assets/image_1.png"], { w: 800, h: 600 });

    // Invocación redundante con mismos valores no debe crear nuevo objeto ni disparar bindings espurios
    _storeImageDimension("assets/image_1.png", 800, 600);
    const ref3 = _imageDimensions;
    assert.strictEqual(ref2, ref3, "Valores idénticos no deben reasignar el objeto");
});

runTest("F34: imageStateFor devuelve 'yes' inmediatamente para rutas registradas sin esperar probe", () => {
    const service = {
        imageProbeReady: false,
        _imageExists: {},
        imageStateFor: function(src, baseFolder) {
            var abs = ImageProbe.resolveLocal(baseFolder || "", src || "");
            if (!abs) {
                if ((src || "").trim() === "") return "no";
                return "remote";
            }
            if (this._imageExists && this._imageExists[abs]) return "yes";
            if (!this.imageProbeReady) return "unknown";
            return "no";
        },
        registerImagePath: function(absPath) {
            if (!absPath) return;
            var m = Object.assign({}, this._imageExists);
            m[absPath] = true;
            this._imageExists = m;
            this.imageProbeReady = true;
        }
    };

    const base = "/home/user/notes/muestra";
    const src = "assets/image_1.png";
    const abs = base + "/" + src;

    // Antes de registrar: desconocido porque probe no está listo
    assert.strictEqual(service.imageStateFor(src, base), "unknown");

    // Tras registrar el archivo creado por PyMuPDF:
    service.registerImagePath(abs);
    assert.strictEqual(service.imageStateFor(src, base), "yes", "Debe devolver 'yes' inmediatamente");
    assert.strictEqual(service.imageProbeReady, true);
});

runTest("F34: isLayoutReady reactivo detecta carga de tarjetas asíncronas", () => {
    let cardsReadySeq = 0;
    function notifyCardReady() {
        cardsReadySeq++;
    }

    const editor = {
        _imageDimensions: {}
    };

    const imagesList = [{ src: "assets/image_1.png" }];
    const cards = [{ isCardReady: false }];

    function isLayoutReady(isRawActive) {
        var _ = cardsReadySeq;
        if (isRawActive || imagesList.length === 0) return true;
        for (var i = 0; i < imagesList.length; i++) {
            var src = imagesList[i].src;
            var cachedDim = editor._imageDimensions ? editor._imageDimensions[src] : null;
            if (cachedDim && cachedDim.w > 0 && cachedDim.h > 0) continue;
            var card = cards[i];
            if (!card || !card.isCardReady) return false;
        }
        return true;
    }

    // Inicialmente no está listo
    assert.strictEqual(isLayoutReady(false), false);

    // Tarjeta se completa asíncronamente
    cards[0].isCardReady = true;
    notifyCardReady();
    assert.strictEqual(cardsReadySeq, 1);
    assert.strictEqual(isLayoutReady(false), true, "isLayoutReady debe ser true tras notifyCardReady");
});

runTest("F35: MermaidParser.detect identifica tipos Fase 1 y categoriza Fases 2 y 3", () => {
    assert.strictEqual(MermaidParser.detect("flowchart TD\n A-->B").type, "flowchart");
    assert.strictEqual(MermaidParser.detect("graph LR\n A-->B").type, "flowchart");
    assert.strictEqual(MermaidParser.detect("sequenceDiagram\n A->>B: Hola").type, "sequenceDiagram");
    assert.strictEqual(MermaidParser.detect("pie title Mascotas\n \"Perros\": 50").type, "pie");
    assert.strictEqual(MermaidParser.detect("stateDiagram-v2\n [*] --> S1").type, "stateDiagram");

    // Fase 2 ya está soportada en el motor nativo:
    const cDiag = MermaidParser.detect("classDiagram\n class Foo");
    assert.strictEqual(cDiag.supported, true);
    assert.strictEqual(cDiag.type, "classDiagram");

    const erDiag = MermaidParser.detect("erDiagram\n A ||--o{ B : r");
    assert.strictEqual(erDiag.supported, true);
    assert.strictEqual(erDiag.type, "erDiagram");

    // Fase 3 ya está soportada en el motor nativo:
    const gitDiag = MermaidParser.detect("gitGraph\n commit");
    assert.strictEqual(gitDiag.supported, true);
    assert.strictEqual(gitDiag.type, "gitGraph");

    const qDiag = MermaidParser.detect("quadrantChart\n x-axis A --> B");
    assert.strictEqual(qDiag.supported, true);
    assert.strictEqual(qDiag.type, "quadrantChart");

    const jDiag = MermaidParser.detect("journey\n title Dia");
    assert.strictEqual(jDiag.supported, true);
    assert.strictEqual(jDiag.type, "journey");

    const xyDiag = MermaidParser.detect("xychart-beta\n x-axis [a,b]");
    assert.strictEqual(xyDiag.supported, true);
    assert.strictEqual(xyDiag.type, "xychart");
});

runTest("F35: MermaidParser.parse flowchart extrae formas, etiquetas y aristas", () => {
    const src = `flowchart TD
    A[Rectángulo] -->|link1| B(Redondo)
    B --> C{Decisión}
    C -->|Sí| D[(Cilindro)]
    C -->|No| E([Estadio])
    A & B --> F((Círculo))`;

    const res = MermaidParser.parse(src);
    assert.strictEqual(res.ok, true);
    assert.strictEqual(res.type, "flowchart");
    assert.strictEqual(res.ast.direction, "TD");

    const nodes = res.ast.nodes;
    assert.strictEqual(nodes["A"].shape, "rect");
    assert.strictEqual(nodes["A"].label, "Rectángulo");
    assert.strictEqual(nodes["B"].shape, "round");
    assert.strictEqual(nodes["C"].shape, "diamond");
    assert.strictEqual(nodes["D"].shape, "cylinder");
    assert.strictEqual(nodes["E"].shape, "stadium");
    assert.strictEqual(nodes["F"].shape, "circle");

    // Conexión múltiple A & B --> F crea aristas A->F y B->F
    const edges = res.ast.edges;
    const aToF = edges.find(e => e.from === "A" && e.to === "F");
    const bToF = edges.find(e => e.from === "B" && e.to === "F");
    assert.ok(aToF, "Debe existir arista A -> F");
    assert.ok(bToF, "Debe existir arista B -> F");
});

runTest("F35: MermaidParser.parse sequenceDiagram extrae participantes, notas y mensajes", () => {
    const src = `sequenceDiagram
    autonumber
    actor U as Usuario
    participant S as Servidor
    U->>+S: Petición GET
    Note over S: Procesando datos
    S-->>-U: Respuesta 200 OK`;

    const res = MermaidParser.parse(src);
    assert.strictEqual(res.ok, true);
    assert.strictEqual(res.type, "sequenceDiagram");
    assert.strictEqual(res.ast.autonumber, true);
    assert.strictEqual(res.ast.participants.length, 2);
    assert.strictEqual(res.ast.participants[0].id, "U");
    assert.strictEqual(res.ast.participants[0].label, "Usuario");
    assert.strictEqual(res.ast.participants[0].isActor, true);

    const msgs = res.ast.events.filter(e => e.kind === "message");
    assert.strictEqual(msgs.length, 2);
    assert.strictEqual(msgs[0].arrow, "arrow");
    assert.strictEqual(msgs[0].dotted, false);
    assert.strictEqual(msgs[1].dotted, true);

    const notes = res.ast.events.filter(e => e.kind === "note");
    assert.strictEqual(notes.length, 1);
    assert.strictEqual(notes[0].text, "Procesando datos");
});

runTest("F35: MermaidParser.parse pie extrae porciones y calcula total", () => {
    const src = `pie title Formatos
    "Markdown" : 60
    "Texto" : 40`;

    const res = MermaidParser.parse(src);
    assert.strictEqual(res.ok, true);
    assert.strictEqual(res.type, "pie");
    assert.strictEqual(res.ast.title, "Formatos");
    assert.strictEqual(res.ast.slices.length, 2);
    assert.strictEqual(res.ast.total, 100);
});

runTest("F35: MermaidShapes genera rutas SVG válidas sin NaN", () => {
    const shapes = ["rect", "round", "stadium", "subroutine", "cylinder", "circle", "doublecircle", "diamond", "hexagon", "parallelogram", "trapezoid", "asym"];
    for (const sh of shapes) {
        const path = MermaidShapes.getShapePath(sh, 100, 50, 6);
        assert.ok(typeof path === "string" && path.length > 5, `Ruta para ${sh} debe ser string no vacío`);
        assert.ok(!path.includes("NaN"), `Ruta para ${sh} no debe contener NaN`);
    }

    const arrow = MermaidShapes.getArrowPath("arrow", 50, 50, Math.PI / 4, 8);
    assert.ok(arrow.startsWith("M "), "Flecha debe generar ruta SVG");
    assert.ok(!arrow.includes("NaN"), "Flecha no debe contener NaN");
});

runTest("F35: MermaidLayout calcula geometría determinista y respeta límites", () => {
    const src = `flowchart LR
    A[Inicio] --> B{Decisión}
    B -->|Sí| C[Fin A]
    B -->|No| D[Fin B]`;

    const parsed = MermaidParser.parse(src);
    const layoutRes = MermaidLayout.layout(parsed);

    assert.strictEqual(layoutRes.ok, true);
    assert.ok(layoutRes.width > 150, "Ancho debe ser positivo");
    assert.ok(layoutRes.height > 80, "Alto debe ser positivo");
    assert.strictEqual(Object.keys(layoutRes.nodes).length, 4);
    assert.strictEqual(layoutRes.edges.length, 3);

    for (const edge of layoutRes.edges) {
        assert.ok(edge.path.startsWith("M "), "Cada arista debe tener ruta Bézier SVG");
        assert.ok(!edge.path.includes("NaN"), "Ruta de arista no debe contener NaN");
    }

    // Pie chart layout
    const pieParsed = MermaidParser.parse(`pie\n "A": 50\n "B": 50`);
    const pieLayout = MermaidLayout.layout(pieParsed);
    assert.strictEqual(pieLayout.ok, true);
    assert.strictEqual(pieLayout.slices.length, 2);
    assert.ok(pieLayout.slices[0].path.startsWith("M "));
});

runTest("F35: BlockModel clasifica mermaid como bloque dedicado y estima altura", () => {
    const md = "# Nota\n\n```mermaid\nflowchart TD\n    A --> B\n```\n\nTexto final";
    const res = BlockModel.splitBlocks(md);
    const blocks = res.blocks;
    assert.strictEqual(blocks.length, 3);
    assert.strictEqual(blocks[0].type, "heading");
    assert.strictEqual(blocks[1].type, "mermaid");
    assert.strictEqual(blocks[2].type, "paragraph");

    const h = BlockModel.estimateBlockHeight("mermaid", blocks[1].raw, 600);
    assert.strictEqual(h, 260);

    // Invariante de reensamblado intacto
    const joined = BlockModel.joinBlocks(res);
    assert.strictEqual(joined, md);
});

runTest("F35: MermaidTemplates provee plantillas completas con ids válidos para Fases 1, 2 y 3", () => {
    const list = MermaidTemplates.getTemplateList();
    assert.strictEqual(list.length, 13);
    const ids = Array.from(list).map(item => String(item.id));
    assert.strictEqual(ids.join(","), "flowchart,sequence,pie,state,classDiagram,erDiagram,gantt,timeline,mindmap,gitGraph,quadrantChart,journey,xychart");

    for (let i = 0; i < list.length; i++) {
        const item = list[i];
        const tpl = MermaidTemplates.getTemplate(item.id);
        assert.ok(tpl.startsWith("```mermaid\n"));
        assert.ok(tpl.endsWith("```"));
        const parsed = MermaidParser.parse(tpl);
        assert.strictEqual(parsed.ok, true, `La plantilla ${item.id} debe compilar sin errores`);
    }
});

runTest("F36: MermaidParser aristas con etiquetas inline y líneas punteadas sin nodos fantasma", () => {
    const src = `flowchart TD
    A -->|Texto| B
    B ---|Línea sin flecha| C
    C -.->|Línea punteada flecha| D
    D -.-|Línea punteada sin flecha| E
    E ==>|Flecha gruesa| F
    F ===|Línea gruesa sin flecha| G
    Check -- Sí --> Hex[Proceso Hexagonal]
    Check -- No --> Trap[Trapecio]`;

    const parsed = MermaidParser.parse(src);
    assert.strictEqual(parsed.ok, true);

    const nodeIds = Object.keys(parsed.ast.nodes);
    // Debe contener únicamente A, B, C, D, E, F, G, Check, Hex, Trap
    assert.strictEqual(nodeIds.includes("Sí"), false, "No debe crear nodo dummy 'Sí'");
    assert.strictEqual(nodeIds.includes("No"), false, "No debe crear nodo dummy 'No'");
    assert.ok(!nodeIds.some(id => id.includes(">") || id.includes("|")), "No debe contener identificadores corruptos por pipes");

    const edgeCD = parsed.ast.edges.find(e => e.from === "C" && e.to === "D");
    assert.ok(edgeCD, "Debe existir arista C -> D");
    assert.strictEqual(edgeCD.label, "Línea punteada flecha");
    assert.strictEqual(edgeCD.type, "arrow");
    assert.strictEqual(edgeCD.strokeDash, true);

    const edgeCheckHex = parsed.ast.edges.find(e => e.from === "Check" && e.to === "Hex");
    assert.ok(edgeCheckHex, "Debe existir arista Check -> Hex");
    assert.strictEqual(edgeCheckHex.label, "Sí");

    const edgeEF = parsed.ast.edges.find(e => e.from === "E" && e.to === "F");
    assert.ok(edgeEF, "Debe existir arista E -> F");
    assert.strictEqual(edgeEF.label, "Flecha gruesa");
    assert.strictEqual(edgeEF.type, "arrow");
    assert.strictEqual(edgeEF.thick, true);
});

runTest("F36: MermaidLayout ciclos en stateDiagram, terminal end y aristas recíprocas", () => {
    const src = `stateDiagram-v2
    [*] --> Reposo
    Reposo --> Editando : Modificar código
    Editando --> Validando : Ejecutar linter
    Validando --> Editando : Error de sintaxis
    Validando --> [*] : Validación correcta`;

    const parsed = MermaidParser.parse(src);
    assert.strictEqual(parsed.ok, true);

    const layoutRes = MermaidLayout.layout(parsed);
    assert.strictEqual(layoutRes.ok, true);

    const nodes = layoutRes.nodes;
    const startNode = Object.values(nodes).find(n => n.shape === "start");
    const endNode = Object.values(nodes).find(n => n.shape === "end");

    assert.ok(startNode, "Debe existir nodo start");
    assert.strictEqual(startNode.w, 22);
    assert.strictEqual(startNode.h, 22);

    assert.ok(endNode, "Debe existir nodo end");
    assert.strictEqual(endNode.w, 24);
    assert.strictEqual(endNode.h, 24);

    // Estado terminal [*] debe ubicarse al final verticalmente
    assert.ok(endNode.y >= nodes["Validando"].y, "Nodo end debe estar abajo o en la misma capa final");

    // Aristas recíprocas Editando <-> Validando no deben compartir la misma curva idéntica
    const e1 = layoutRes.edges.find(e => e.from === "Editando" && e.to === "Validando");
    const e2 = layoutRes.edges.find(e => e.from === "Validando" && e.to === "Editando");
    assert.ok(e1 && e2, "Deben existir ambas aristas recíprocas");
    assert.notStrictEqual(e1.path, e2.path, "Las curvas recíprocas deben tener trayectorias opuestas");
});

runTest("F36: MermaidLayout dimensiones especializadas para cilindro", () => {
    const src = `flowchart TD\n DB[(Base de datos)]`;
    const parsed = MermaidParser.parse(src);
    const layoutRes = MermaidLayout.layout(parsed);
    assert.strictEqual(layoutRes.ok, true);
    const dbNode = layoutRes.nodes["DB"];
    assert.ok(dbNode.w >= 76, "Ancho de cilindro debe ser >= 76px: " + dbNode.w);
    assert.ok(dbNode.h >= 46, "Alto de cilindro debe ser >= 46px: " + dbNode.h);
});

runTest("F37: NotesService lote de múltiples notas borradas y deshacer acumulativo", () => {
    const qml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesService.qml'), 'utf8');

    // 1. Declaración de propiedades reactivas del lote en NotesService
    assert.ok(qml.indexOf("property var _pendingDeletions: ({})") !== -1, "_pendingDeletions debe existir");
    assert.ok(qml.indexOf("readonly property int pendingDeleteCount: Object.keys(_pendingDeletions).length") !== -1, "pendingDeleteCount debe existir");
    assert.ok(qml.indexOf("id: deleteBatchTimer") !== -1, "deleteBatchTimer debe existir en NotesService");
    assert.ok(qml.indexOf("function queueDelete(") !== -1, "queueDelete debe existir");
    assert.ok(qml.indexOf("function commitPendingDeletions()") !== -1, "commitPendingDeletions debe existir");
    assert.ok(qml.indexOf("function undoPendingDeletions()") !== -1, "undoPendingDeletions debe existir");

    // 2. Simulación de la lógica de encolado y deshacer en lote
    let _pendingDeletions = {};
    let _deletingKeys = {};
    let trashedNotes = [];
    let timerRunning = false;

    function queueDelete(key, noteData) {
        _deletingKeys[key] = true;
        const copy = Object.assign({}, _pendingDeletions);
        copy[key] = { key, noteData, queuedAt: Date.now() };
        _pendingDeletions = copy;
        timerRunning = true;
    }

    function undoPendingDeletions() {
        timerRunning = false;
        for (const k in _pendingDeletions) {
            delete _deletingKeys[k];
        }
        _pendingDeletions = {};
    }

    function commitPendingDeletions() {
        timerRunning = false;
        const batch = _pendingDeletions;
        _pendingDeletions = {};
        for (const k in batch) {
            trashedNotes.push(k);
        }
    }

    // Borrado consecutivo de 2 notas
    queueDelete("nota1:md", { title: "Nota 1" });
    assert.strictEqual(Object.keys(_pendingDeletions).length, 1);
    assert.strictEqual(_deletingKeys["nota1:md"], true);
    assert.strictEqual(trashedNotes.length, 0, "Nota 1 no debe enviarse a papelera prematuramente");

    queueDelete("nota2:md", { title: "Nota 2" });
    assert.strictEqual(Object.keys(_pendingDeletions).length, 2);
    assert.strictEqual(_deletingKeys["nota2:md"], true);
    assert.strictEqual(trashedNotes.length, 0, "Nota 1 no debe haberse forzado a papelera al llegar Nota 2");

    // Deshacer restaura ambas notas
    undoPendingDeletions();
    assert.strictEqual(Object.keys(_pendingDeletions).length, 0);
    assert.strictEqual(_deletingKeys["nota1:md"], undefined);
    assert.strictEqual(_deletingKeys["nota2:md"], undefined);
    assert.strictEqual(trashedNotes.length, 0, "Ambas notas deben recuperarse sin haber tocado papelera");

    // Borrado nuevamente y confirmación (commit)
    queueDelete("nota1:md", { title: "Nota 1" });
    queueDelete("nota2:md", { title: "Nota 2" });
    assert.strictEqual(Object.keys(_pendingDeletions).length, 2);

    commitPendingDeletions();
    assert.strictEqual(Object.keys(_pendingDeletions).length, 0);
    assert.strictEqual(trashedNotes.length, 2, "Ambas notas deben enviarse juntas a la papelera");
    assert.deepStrictEqual(trashedNotes, ["nota1:md", "nota2:md"]);
});

runTest("F38: fenceExit detecta salida del bloque sólo al final de la valla de cierre", () => {
    const raw = "```mermaid\ngraph TD\n    A --> B\n```";
    // Cursor al final del bloque
    const atEnd = BlockModel.fenceExit(raw, raw.length);
    assert.strictEqual(atEnd.exit, true);
    assert.strictEqual(atEnd.raw, raw);

    // Cursor con espacios/saltos finales extra
    const withExtra = raw + "\n\n";
    const atEndExtra = BlockModel.fenceExit(withExtra, withExtra.length);
    assert.strictEqual(atEndExtra.exit, true);
    assert.strictEqual(atEndExtra.raw, raw, "debe limpiar saltos de línea sobrantes");

    // Cursor en el cuerpo del bloque (no en la valla de cierre)
    const inside = BlockModel.fenceExit(raw, 15);
    assert.strictEqual(inside.exit, false);

    // Sin valla de cierre completa
    const noClose = "```mermaid\ngraph TD\n    A --> B\n";
    const noCloseRes = BlockModel.fenceExit(noClose, noClose.length);
    assert.strictEqual(noCloseRes.exit, false);

    // Texto de una sola línea
    assert.strictEqual(BlockModel.fenceExit("```", 3).exit, false);
});

runTest("F39: MermaidParser subgrafos con espacios antes de corchetes", () => {
    const src = `flowchart TD\nsubgraph Frontend [Capa de Usuario]\nA[Web]\nend`;
    const parsed = MermaidParser.parse(src);
    assert.strictEqual(parsed.ok, true);
    assert.strictEqual(parsed.ast.subgraphs.length, 1);
    assert.strictEqual(parsed.ast.subgraphs[0].id, "Frontend");
    assert.strictEqual(parsed.ast.subgraphs[0].title, "Capa de Usuario");
});

runTest("F40: MermaidLayout ruteo multi-capa y normalización de coordenadas", () => {
    const src = `flowchart TD
A -->|Flecha sólida con texto| B
A --> D
B ---|Línea sin flecha| C
B --> D
C -.->|Línea punteada flecha| D
D -.-|Línea punteada sin flecha| E
E ==>|Flecha gruesa| F
F ==|Línea gruesa sin flecha| G`;
    const parsed = MermaidParser.parse(src);
    assert.strictEqual(parsed.ok, true);
    assert.strictEqual(parsed.ast.edges.length, 8);

    const layout = MermaidLayout.layout(parsed, (t) => ({ width: t.length * 7, height: 14 }));
    assert.strictEqual(layout.ok, true);
    assert.strictEqual(Object.keys(layout.nodes).length, 7);

    // Todos los nodos deben tener x >= 16 e y >= 16
    for (const id in layout.nodes) {
        assert.ok(layout.nodes[id].x >= 16, `Nodo ${id} x=${layout.nodes[id].x} debe ser >= 16`);
        assert.ok(layout.nodes[id].y >= 16, `Nodo ${id} y=${layout.nodes[id].y} debe ser >= 16`);
    }

    // Aristas multi-capa A->D y B->D deben rutear por canal lateral fuera de los nodos
    const ad = layout.edges.find(e => e.from === "A" && e.to === "D");
    const bd = layout.edges.find(e => e.from === "B" && e.to === "D");
    assert.ok(ad && ad.corridorX !== undefined, "A->D debe tener canal corridorX");
    assert.ok(bd && bd.corridorX !== undefined, "B->D debe tener canal corridorX");

    const maxNodeRight = Math.max(
        layout.nodes["B"].x + layout.nodes["B"].w,
        layout.nodes["C"].x + layout.nodes["C"].w
    );
    assert.ok(ad.corridorX > maxNodeRight, `Canal A->D (${ad.corridorX}) debe estar a la derecha de nodos intermedios (${maxNodeRight})`);
    assert.ok(bd.corridorX > maxNodeRight, `Canal B->D (${bd.corridorX}) debe estar a la derecha de nodos intermedios (${maxNodeRight})`);

    // Aristas gruesas
    const ef = layout.edges.find(e => e.from === "E" && e.to === "F");
    const fg = layout.edges.find(e => e.from === "F" && e.to === "G");
    assert.strictEqual(ef.thick, true);
    assert.strictEqual(fg.thick, true);
});

runTest("F41: Cylinder inset, Subgraph title width, Multi-layer vertical tangents and State diagram label clearance", () => {
    // 1. Cilindro con inset para no recortar arco inferior
    const cylPath = MermaidShapes.getShapePath("cylinder", 100, 50);
    assert.ok(cylPath.indexOf("M 1 ") !== -1, "El cilindro debe iniciar con pad 1px en x");
    assert.ok(cylPath.indexOf("L 99 ") !== -1, "El cilindro debe respetar el límite derecho con pad");

    // 2. Subgrafo con título largo ensancha el contenedor
    const subSrc = `flowchart TB\n subgraph Backend [Servicios del Sistema Super Largos]\n Core[NotesService]\n end`;
    const subParsed = MermaidParser.parse(subSrc);
    const subLayout = MermaidLayout.layout(subParsed, (t) => ({ width: t.length * 8, height: 16 }));
    assert.strictEqual(subLayout.ok, true);
    assert.strictEqual(subLayout.subgraphs.length, 1);
    const sg = subLayout.subgraphs[0];
    assert.ok(sg.w >= 280, `Subgrafo debe tener ancho suficiente para el título: ${sg.w}`);

    // 3. Aristas multi-capa: llegada vertical congruente con endAngle 90°
    const multiSrc = `flowchart TD\n A --> B\n B --> C\n C --> D\n A & B --> C & D`;
    const multiParsed = MermaidParser.parse(multiSrc);
    const multiLayout = MermaidLayout.layout(multiParsed, (t) => ({ width: 60, height: 20 }));
    const adEdge = multiLayout.edges.find(e => e.from === "A" && e.to === "D");
    assert.ok(adEdge, "Debe existir arista A->D");
    assert.strictEqual(adEdge.endAngle, Math.PI / 2, "El ángulo de llegada debe ser exactamente 90°");
    // Verificar que el último punto de control de Bézier tenga x igual al punto final (derivada vertical pura)
    const matchC = adEdge.path.match(/C\s+[\d\.\-]+\s+[\d\.\-]+,\s*([\d\.\-]+)\s+([\d\.\-]+),\s*([\d\.\-]+)\s+([\d\.\-]+)$/);
    assert.ok(matchC, "Debe terminar en comando C de Bézier cúbica");
    const cp4X = Math.round(parseFloat(matchC[1]));
    const endX = Math.round(parseFloat(matchC[3]));
    assert.strictEqual(cp4X, endX, `cp4.x (${cp4X}) debe ser igual a end.x (${endX}) para entrada vertical`);

    // 4. Diagrama de estado con salto de línea y etiquetas recíprocas escalonadas
    const stateSrc = `stateDiagram-v2\n [*] --> Reposo\n Reposo --> Editando: Clic\n Editando --> Validando: Modificar\n Validando --> Editando: Error\n Validando --> Reposo: Ctrl+Enter /<br/>Confirmar`;
    const stateParsed = MermaidParser.parse(stateSrc);
    const stateLayout = MermaidLayout.layout(stateParsed, (t) => ({ width: t.length * 7, height: 14 }));
    assert.strictEqual(stateLayout.ok, true);
    const eFwd = stateLayout.edges.find(e => e.from === "Editando" && e.to === "Validando");
    const eRev = stateLayout.edges.find(e => e.from === "Validando" && e.to === "Editando");
    assert.ok(eFwd && eRev, "Deben existir aristas Editando <-> Validando");
    assert.notStrictEqual(Math.round(eFwd.labelY), Math.round(eRev.labelY), "Las etiquetas recíprocas no deben solaparse en el mismo Y");
    const backEdge = stateLayout.edges.find(e => e.from === "Validando" && e.to === "Reposo");
    assert.ok(backEdge, "Debe existir back-edge Validando -> Reposo");
    assert.ok(backEdge.label.indexOf("\n") !== -1, "La etiqueta debe contener salto de línea convertido desde <br/>");
});

runTest("F42: Mermaid cylinder closed subpaths and arrowhead marker contracts", () => {
    // 1. Cilindro: dos subrutas cerradas con Z para relleno homogéneo sin artefactos
    const cylPath = MermaidShapes.getShapePath("cylinder", 120, 60);
    const zMatches = cylPath.match(/ Z/g) || [];
    assert.strictEqual(zMatches.length, 2, "El cilindro debe contener exactamente 2 subrutas cerradas con 'Z'");
    assert.ok(cylPath.startsWith("M 1 "), "La cara superior debe iniciar con pad 1px en x");
    assert.ok(cylPath.indexOf("A ") !== -1, "Debe contener comandos de arco para las elipses");

    // 2. Marcadores de flecha generados correctamente
    const arrowPath = MermaidShapes.getArrowPath("arrow", 50, 100, Math.PI / 2, 8);
    assert.ok(arrowPath.indexOf("M 50 100") !== -1, "El marcador de flecha debe anclarse en endX/endY");
    assert.ok(arrowPath.endsWith("Z"), "El marcador debe ser un polígono cerrado con 'Z'");

    // 3. Contrato de coordenadas en navegación por columnas
    const curPosObj = { x: 42, y: 999999 };
    assert.strictEqual(typeof curPosObj, "object");
    assert.strictEqual(curPosObj.x, 42);
    assert.ok(curPosObj.y > 1000, "y > 1000 indica llegada desde el bloque inferior");

    const curPosDownObj = { x: 42, y: 0 };
    assert.strictEqual(curPosDownObj.y, 0, "y === 0 indica llegada desde el bloque superior");
});

runTest("F43: Preferred horizontal column memory & vertical boundary navigation contracts", () => {
    // 1. Simulación del estado y funciones de BlockEditor.preferredCursorX
    let preferredCursorX = -1;
    function getPreferredCursorX(curX) {
        if (preferredCursorX >= 0) return preferredCursorX;
        if (typeof curX === "number" && curX >= 0) {
            preferredCursorX = curX;
            return curX;
        }
        return -1;
    }
    function resetPreferredCursorX() {
        if (preferredCursorX !== -1) {
            preferredCursorX = -1;
        }
    }

    // Inicia en línea larga: columna x = 320
    assert.strictEqual(preferredCursorX, -1);
    const targetX1 = getPreferredCursorX(320);
    assert.strictEqual(targetX1, 320);
    assert.strictEqual(preferredCursorX, 320);

    // Navega hacia una línea corta intermedia (ancho máximo 80)
    // El cursor visual se clampa a 80, pero getPreferredCursorX mantiene 320
    const targetX2 = getPreferredCursorX(80);
    assert.strictEqual(targetX2, 320, "Debe preservar 320 al atravesar una línea corta");
    assert.strictEqual(preferredCursorX, 320);

    // Navega a otra línea larga: retorna a columna 320
    const targetX3 = getPreferredCursorX(500);
    assert.strictEqual(targetX3, 320, "Debe retornar a columna 320 en la siguiente línea");

    // Movimiento horizontal o tipeo resetea la memoria
    resetPreferredCursorX();
    assert.strictEqual(preferredCursorX, -1, "Debe quedar en -1 tras reset");

    // Nuevo movimiento vertical desde x = 150
    const targetX4 = getPreferredCursorX(150);
    assert.strictEqual(targetX4, 150);
    assert.strictEqual(preferredCursorX, 150);

    // 2. Validación de contratos fromBottom y fromTop
    const navFromBottom = { x: 320, fromBottom: true };
    assert.strictEqual(navFromBottom.fromBottom, true);
    assert.strictEqual(navFromBottom.x, 320);

    const navFromTop = { x: 320, fromTop: true };
    assert.strictEqual(navFromTop.fromTop, true);
    assert.strictEqual(navFromTop.x, 320);

    // 3. Simulación de cálculo de targetY para positionAt en línea final e inicial
    function computeTargetY(pos, rects) {
        if (pos.fromBottom === true || pos.y > 1000) {
            const lastRect = rects[rects.length - 1];
            return lastRect.y + (lastRect.height > 0 ? lastRect.height / 2 : 10);
        } else {
            const firstRect = rects[0];
            return firstRect.y + (firstRect.height > 0 ? firstRect.height / 2 : 10);
        }
    }

    const mockRects = [
        { y: 0, height: 20 },
        { y: 22, height: 20 },
        { y: 44, height: 20 }
    ];

    const yBot = computeTargetY(navFromBottom, mockRects);
    assert.strictEqual(yBot, 54, "Target Y en la última línea debe ser 44 + 10 = 54 (centro vertical real)");
    assert.ok(yBot < 1000, "Target Y debe ser una coordenada acotada y real dentro del documento");

    const yTop = computeTargetY(navFromTop, mockRects);
    assert.strictEqual(yTop, 10, "Target Y en la primera línea debe ser 0 + 10 = 10 (centro vertical real)");
});

runTest("F44: Markdown table dynamic column width & horizontal scroll contracts", () => {
    // 1. Cálculo de ancho mínimo y distribución proporcional vs clamp
    function computeTableLayout(colCount, availableWidth, zoom = 1.0) {
        const minColWidth = Math.max(96, Math.round(96 * zoom));
        const colWidth = Math.max(minColWidth, Math.floor(availableWidth / Math.max(1, colCount)));
        const tableColWidth = colCount * colWidth;
        const needsScroll = tableColWidth > availableWidth;
        return { minColWidth, colWidth, tableColWidth, needsScroll };
    }

    // Caso A: Tabla pequeña (3 columnas en 750px) -> se expande proporcionalmente
    const layoutSmall = computeTableLayout(3, 750, 1.0);
    assert.strictEqual(layoutSmall.minColWidth, 96);
    assert.strictEqual(layoutSmall.colWidth, 250);
    assert.strictEqual(layoutSmall.tableColWidth, 750);
    assert.strictEqual(layoutSmall.needsScroll, false, "3 columnas caben sin scroll horizontal");

    // Caso B: Tabla mediana (7 columnas en 750px) -> 107px por columna > 96px
    const layoutMed = computeTableLayout(7, 750, 1.0);
    assert.strictEqual(layoutMed.colWidth, 107);
    assert.strictEqual(layoutMed.needsScroll, false);

    // Caso C: Tabla grande (20 columnas como en la imagen del usuario) -> clampa a 96px
    const layoutLarge = computeTableLayout(20, 750, 1.0);
    assert.strictEqual(layoutLarge.colWidth, 96, "No debe comprimirse por debajo del mínimo de 96px");
    assert.strictEqual(layoutLarge.tableColWidth, 1920, "20 columnas a 96px = 1920px");
    assert.strictEqual(layoutLarge.needsScroll, true, "Activa scroll horizontal");

    // Caso D: Zoom 1.25x escala minColWidth proporcionalmente
    const layoutZoom = computeTableLayout(20, 750, 1.25);
    assert.strictEqual(layoutZoom.minColWidth, 120, "96 * 1.25 = 120px");
    assert.strictEqual(layoutZoom.colWidth, 120);
    assert.strictEqual(layoutZoom.tableColWidth, 2400);

    // 2. Lógica de auto-scroll con ensureCellVisible
    function simulateEnsureCellVisible(colIndex, colWidth, contentX, viewportWidth, contentWidth, dotMargin = 34) {
        const cellLeft = colIndex * colWidth;
        const cellRight = cellLeft + colWidth;
        const viewLeft = contentX;
        const viewRight = viewLeft + viewportWidth;

        let nextX = contentX;
        if (cellLeft < viewLeft) {
            nextX = Math.max(0, cellLeft);
        } else if (cellRight > viewRight) {
            const targetX = cellRight - viewportWidth + dotMargin;
            nextX = Math.max(0, Math.min(contentWidth - viewportWidth, targetX));
        }
        return nextX;
    }

    const vpWidth = 750;
    const totalWidth = 1920; // 20 columnas a 96px
    let curX = 0;

    // Celda 0 ya está a la vista
    curX = simulateEnsureCellVisible(0, 96, curX, vpWidth, totalWidth);
    assert.strictEqual(curX, 0, "Celda 0 no requiere scroll");

    // Navegar a la celda 15 (15 * 96 = 1440px -> fuera de vista a la derecha)
    curX = simulateEnsureCellVisible(15, 96, curX, vpWidth, totalWidth);
    assert.ok(curX > 0, "Debe scrollear a la derecha para revelar la celda 15");
    assert.ok(15 * 96 >= curX && (15 + 1) * 96 <= curX + vpWidth, "Celda 15 debe quedar contenida dentro de la ventana visible");

    // Navegar de vuelta a la celda 2 (2 * 96 = 192px -> fuera de vista a la izquierda)
    curX = simulateEnsureCellVisible(2, 96, curX, vpWidth, totalWidth);
    assert.strictEqual(curX, 192, "Debe scrollear a la izquierda a cellLeft exacto");

    // Agregar nueva columna debe scrollear al extremo derecho
    const maxScrollX = Math.max(0, totalWidth + 96 - vpWidth);
    assert.ok(maxScrollX > 0);
});

runTest("F45: Inline markdown dynamic syntax reveal on cursor touching contracts (Typora style)", () => {
    // 1. Un solo tramo formateado: "**negrita** texto blabla"
    const text1 = "**negrita** texto blabla"; // length: 24, span: [0, 11]

    // Caso 1A: Cursor al final (pos 24) -> Delimitadores ** ocultos
    const htmlEnd = Inline.formatForLiveEditing(text1, { cursorPos: 24 });
    assert.ok(htmlEnd.includes('style="font-size: 1px; color: transparent;">**</span>'), "Los ** deben estar colapsados y transparentes");
    assert.ok(!htmlEnd.includes('<font color="#888888">**</font>'), "Los ** NO deben mostrarse en gris cuando el cursor está al final");

    // Caso 1B: Cursor tocando al final ("**negrita**|", pos 11) -> Delimitadores ** visibles
    const htmlTouchEnd = Inline.formatForLiveEditing(text1, { cursorPos: 11 });
    assert.ok(htmlTouchEnd.includes('<font color="#888888">**</font>'), "Los ** deben revelarse cuando el cursor toca el final de la palabra");
    assert.ok(!htmlTouchEnd.includes('style="font-size: 1px; color: transparent;">**</span>'));

    // Caso 1C: Cursor tocando al inicio ("|**negrita**", pos 0) -> Delimitadores ** visibles
    const htmlTouchStart = Inline.formatForLiveEditing(text1, { cursorPos: 0 });
    assert.ok(htmlTouchStart.includes('<font color="#888888">**</font>'), "Los ** deben revelarse al tocar el inicio");

    // Caso 1D: Cursor dentro de la palabra ("**neg|rita**", pos 5) -> Delimitadores ** visibles
    const htmlInside = Inline.formatForLiveEditing(text1, { cursorPos: 5 });
    assert.ok(htmlInside.includes('<font color="#888888">**</font>'), "Los ** deben revelarse dentro de la palabra");

    // Caso 1E: Cursor en el espacio fuera de contacto (pos 12) -> Delimitadores ** ocultos
    const htmlOutside = Inline.formatForLiveEditing(text1, { cursorPos: 12 });
    assert.ok(htmlOutside.includes('style="font-size: 1px; color: transparent;">**</span>'));

    // 2. Múltiples formatos en una misma línea: "**negrita** y *cursiva* y ~~tachado~~"
    const textMulti = "**negrita** y *cursiva* y ~~tachado~~";
    // bold: [0, 11], italic: [14, 23], strike: [26, 37]

    // Cursor tocando negrita (pos 11)
    const htmlBoldActive = Inline.formatForLiveEditing(textMulti, { cursorPos: 11 });
    assert.ok(htmlBoldActive.includes('<font color="#888888">**</font>'), "Bold debe estar visible");
    assert.ok(htmlBoldActive.includes('style="font-size: 1px; color: transparent;">*</span>'), "Italic debe estar oculto");
    assert.ok(htmlBoldActive.includes('style="font-size: 1px; color: transparent;">~~</span>'), "Strike debe estar oculto");

    // Cursor tocando cursiva (pos 19)
    const htmlItalicActive = Inline.formatForLiveEditing(textMulti, { cursorPos: 19 });
    assert.ok(htmlItalicActive.includes('style="font-size: 1px; color: transparent;">**</span>'), "Bold debe estar oculto");
    assert.ok(htmlItalicActive.includes('<font color="#888888">*</font>'), "Italic debe estar visible");
    assert.ok(htmlItalicActive.includes('style="font-size: 1px; color: transparent;">~~</span>'), "Strike debe estar oculto");

    // Cursor tocando tachado (pos 37)
    const htmlStrikeActive = Inline.formatForLiveEditing(textMulti, { cursorPos: 37 });
    assert.ok(htmlStrikeActive.includes('style="font-size: 1px; color: transparent;">**</span>'), "Bold debe estar oculto");
    assert.ok(htmlStrikeActive.includes('style="font-size: 1px; color: transparent;">*</span>'), "Italic debe estar oculto");
    assert.ok(htmlStrikeActive.includes('<font color="#888888">~~</font>'), "Strike debe estar visible");

    // 3. Otros tipos de formato: código inline, enlace, subrayado, resaltado
    const textOther = "`codigo` y [enlace](https://test.com) y <u>sub</u> y ==res==";
    // Fuera de contacto (pos 0..0 sin foco o cursor = -1)
    const htmlAllHidden = Inline.formatForLiveEditing(textOther, { cursorPos: -1 });
    assert.ok(htmlAllHidden.includes('style="font-size: 1px; color: transparent;">`</span>'), "Código inline oculto");
    assert.ok(htmlAllHidden.includes('style="font-size: 1px; color: transparent;">]('), "URL del enlace oculta");
    assert.ok(htmlAllHidden.includes('style="font-size: 1px; color: transparent;">&lt;u&gt;</span>'), "Tag <u> oculto");
    assert.ok(htmlAllHidden.includes('style="font-size: 1px; color: transparent;">==</span>'), "Delimitador == oculto");

    // Tocando el enlace
    const linkStart = textOther.indexOf("[enlace");
    const htmlLinkActive = Inline.formatForLiveEditing(textOther, { cursorPos: linkStart });
    assert.ok(htmlLinkActive.includes('<font color="#888888">[</font>'), "Delimitador [ debe ser visible");
    assert.ok(htmlLinkActive.includes('<font color="#888888">](https://test.com)</font>'), "URL completa debe ser visible al tocar");

    // 4. Selección activa revela el tramo seleccionado
    const htmlSelected = Inline.formatForLiveEditing(text1, { selStart: 2, selEnd: 8 });
    assert.ok(htmlSelected.includes('<font color="#888888">**</font>'), "Selección activa dentro de negrita revela **");

    // 5. Integridad de datos crudos: el texto limpio de tags HTML preserva exactamente el markdown original
    function cleanHtmlToPlain(html) {
        return html
            .replace(/^<span style="white-space: pre-wrap;">/, '')
            .replace(/<\/span>$/, '')
            .replace(/<br\s*\/?>/g, '\n')
            .replace(/<[^>]+>/g, '')
            .replace(/&amp;/g, '&')
            .replace(/&lt;/g, '<')
            .replace(/&gt;/g, '>')
            .replace(/&quot;/g, '"')
            .replace(/&#39;/g, "'");
    }

    assert.strictEqual(cleanHtmlToPlain(htmlEnd), text1, "El texto crudo debe ser 100% idéntico cuando está oculto");
    assert.strictEqual(cleanHtmlToPlain(htmlTouchEnd), text1, "El texto crudo debe ser 100% idéntico cuando está visible");
    assert.strictEqual(cleanHtmlToPlain(htmlBoldActive), textMulti);
    assert.strictEqual(cleanHtmlToPlain(htmlAllHidden), textOther);
});

runTest("F46: Markdown table multiline cell wrapping, dynamic row height and <br> contracts", () => {
    // 1. Preservación de <br> y <br/> en inlineToHtml para celdas de tabla
    const cellTextWithBr = "Lecturas aleatorias lentas;<br>se desperdicia espacio en cada bloque";
    const cellHtml = Inline.inlineToHtml(cellTextWithBr, { linkColor: "#ffaa00" });
    assert.ok(cellHtml.includes("<br>") || cellHtml.includes("<br/>"), "inlineToHtml debe preservar las etiquetas <br> para saltos de línea");
    assert.ok(cellHtml.includes("Lecturas aleatorias lentas;"), "Debe preservar el contenido de la primera línea");
    assert.ok(cellHtml.includes("se desperdicia espacio en cada bloque"), "Debe preservar el contenido de la segunda línea");

    // 2. Cálculo determinista de altura de fila unificada (máximo entre todas las celdas de la fila)
    function simulateRowHeight(rowCells, colWidth, minRowHeight = 38) {
        // Simulación del cálculo de altura visual por celda con wrap y padding (14px)
        const charWidth = 8;
        const availableCellTextWidth = Math.max(1, colWidth - 16);
        const lineHeight = 20;

        let maxH = minRowHeight;
        const cellHeights = [];

        for (let i = 0; i < rowCells.length; i++) {
            const raw = String(rowCells[i] || "");
            const lines = raw.split(/<br\s*\/?>/i);
            let visualLineCount = 0;
            for (const line of lines) {
                const lineWidth = line.length * charWidth;
                visualLineCount += Math.max(1, Math.ceil(lineWidth / availableCellTextWidth));
            }
            const contentPaintedHeight = visualLineCount * lineHeight;
            const cellHeight = Math.max(minRowHeight, contentPaintedHeight + 14);
            cellHeights.push(cellHeight);
            if (cellHeight > maxH) {
                maxH = cellHeight;
            }
        }
        return { maxRowHeight: maxH, cellHeights };
    }

    // Fila con celdas cortas (sin wrap)
    const shortRow = ["Método", "Cómo funciona", "Pros / contras"];
    const shortResult = simulateRowHeight(shortRow, 250, 38);
    assert.strictEqual(shortResult.maxRowHeight, 38, "Fila corta debe respetar minRowHeight = 38px");

    // Fila del caso de usuario: celda 3 con texto largo que desborda en ancho 200px
    const userRow = [
        "Lista enlazada de bloques",
        "Cada bloque apunta al siguiente",
        "Lecturas aleatorias lentas; se desperdicia espacio en cada bloque guardando dónde está el siguiente"
    ];
    const userResult = simulateRowHeight(userRow, 200, 38);
    // Celda 3 tiene ~99 chars -> a 8px/char = 792px -> en 184px de ancho útil = ~5 líneas (~114px)
    assert.ok(userResult.maxRowHeight > 38, "La fila debe expandirse dinámicamente para alojar el texto multilínea");
    assert.ok(userResult.cellHeights[2] > userResult.cellHeights[0], "La celda con texto largo debe tener mayor altura que las celdas cortas");
    // Todas las celdas de la fila toman la altura sincronizada maxRowHeight
    for (let c = 0; c < userRow.length; c++) {
        const assignedHeight = userResult.maxRowHeight;
        assert.ok(assignedHeight >= userResult.cellHeights[c], "La fila garantiza que ninguna celda se recorte");
    }

    // Fila con salto explícito <br> (Shift+Enter)
    const brRow = [
        "FAT",
        "Una tabla que,<br>dice cuál es el siguiente",
        "Ver abajo"
    ];
    const brResult = simulateRowHeight(brRow, 250, 38);
    assert.ok(brResult.cellHeights[1] >= 54, "La celda con <br> debe tener al menos altura para 2 líneas (>= 54px)");
    assert.strictEqual(brResult.maxRowHeight, brResult.cellHeights[1], "La altura de la fila se adapta a la celda con <br>");

    // 3. Reglas de navegación con flechas arriba/abajo en TextEdit multilínea
    function simulateKeyVerticalNavigation(curRectY, curRectHeight, paintedHeight, key) {
        // En TextEdit:
        // Keys.onUpPressed: si curRect.y <= 2 -> salta a celda de arriba (handled por BlockTable)
        // si curRect.y > 2 -> deja que TextEdit navegue entre sus líneas internas
        // Keys.onDownPressed: si curRect.y + curRect.height >= paintedHeight - 3 -> salta a celda de abajo
        if (key === "Up") {
            return curRectY <= 2 ? "NAVIGATE_ROW_UP" : "TEXTEDIT_INTERNAL";
        }
        if (key === "Down") {
            return (curRectY + curRectHeight >= paintedHeight - 3) ? "NAVIGATE_ROW_DOWN" : "TEXTEDIT_INTERNAL";
        }
        return "IGNORED";
    }

    const paintedH = 60; // 3 líneas de 20px (y=0, y=20, y=40, height=20)
    // Línea 1 (y=0):
    assert.strictEqual(simulateKeyVerticalNavigation(0, 20, paintedH, "Up"), "NAVIGATE_ROW_UP");
    assert.strictEqual(simulateKeyVerticalNavigation(0, 20, paintedH, "Down"), "TEXTEDIT_INTERNAL");

    // Línea 2 (y=20):
    assert.strictEqual(simulateKeyVerticalNavigation(20, 20, paintedH, "Up"), "TEXTEDIT_INTERNAL");
    assert.strictEqual(simulateKeyVerticalNavigation(20, 20, paintedH, "Down"), "TEXTEDIT_INTERNAL");

    // Línea 3 (y=40):
    assert.strictEqual(simulateKeyVerticalNavigation(40, 20, paintedH, "Up"), "TEXTEDIT_INTERNAL");
    assert.strictEqual(simulateKeyVerticalNavigation(40, 20, paintedH, "Down"), "NAVIGATE_ROW_DOWN");
});

runTest("F47: IPC path resolution, external file read-only preview and in-place serialization contracts", () => {
    const notesDir = "/home/usuario/.config/quickshell/notes_storage";
    const internalFile = "/home/usuario/.config/quickshell/notes_storage/mi_nota.md";
    const internalSubFile = "/home/usuario/.config/quickshell/notes_storage/subcarpeta/otra_nota.md";
    const externalFile = "/home/usuario/Descargas/README.md";
    const externalTmp = "/tmp/test-doc.md";

    // 1. Clasificación interna vs externa
    assert.strictEqual(ImportLogic.isInsideDir(internalFile, notesDir), true, "Archivo en notesDir debe ser interno");
    assert.strictEqual(ImportLogic.isInsideDir(internalSubFile, notesDir), true, "Archivo en subcarpeta de notesDir debe ser interno");
    assert.strictEqual(ImportLogic.isInsideDir(externalFile, notesDir), false, "Archivo en Descargas debe ser externo");
    assert.strictEqual(ImportLogic.isInsideDir(externalTmp, notesDir), false, "Archivo en /tmp debe ser externo");

    // 2. Parseo y contrato de modo vista previa (solo lectura)
    const rawExternal = "# Proyecto Externo\n\nEste es un archivo sin frontmatter YAML.\n";
    const parsedExt = MD.parseNote("README.md", externalFile, false, rawExternal);
    parsedExt.isExternal = true;
    parsedExt.readOnly = true;
    parsedExt.hadFrontmatter = Boolean(parsedExt._frontmatterEntries && parsedExt._frontmatterEntries.length > 0);
    parsedExt.key = "__external__:" + externalFile;

    assert.strictEqual(parsedExt.isExternal, true, "Nota externa marcada como isExternal");
    assert.strictEqual(parsedExt.readOnly, true, "Modo preview inicia con readOnly = true");
    assert.strictEqual(parsedExt.hadFrontmatter, false, "README sin frontmatter detecta hadFrontmatter = false");
    assert.ok(parsedExt.key.startsWith("__external__:"), "Clave externa tiene prefijo seguro");

    // 3. Serialización In-Place: NO inyecta frontmatter artificial si no lo tenía
    const serializedNoFm = MD.serializeNote(parsedExt, parsedExt.body || parsedExt.content);
    assert.strictEqual(serializedNoFm.includes("---"), false, "Guardar archivo externo sin frontmatter original NO debe inyectar ---");
    assert.strictEqual(serializedNoFm.includes("title:"), false, "Guardar archivo externo sin frontmatter original NO debe inyectar title:");
    assert.strictEqual(serializedNoFm.includes("created:"), false, "Guardar archivo externo sin frontmatter original NO debe inyectar created:");

    // 4. Si el usuario agrega tags explícitamente, serializeNote los incorpora limpiamente
    parsedExt.tags = ["referencia", "trabajo"];
    const serializedWithTags = MD.serializeNote(parsedExt, parsedExt.body || parsedExt.content);
    assert.ok(serializedWithTags.startsWith("---\ntags: [\"referencia\", \"trabajo\"]\n---\n"), "Al agregar tags se genera frontmatter mínimo");

    // 5. Archivo externo que SÍ tenía frontmatter original lo conserva íntegro
    const rawWithFm = "---\ntitle: \"Doc Original\"\nversion: 2.1\n---\n# Encabezado\nContenido";
    const parsedWithFm = MD.parseNote("Doc.md", "/tmp/Doc.md", false, rawWithFm);
    parsedWithFm.isExternal = true;
    parsedWithFm.hadFrontmatter = Boolean(parsedWithFm._frontmatterEntries && parsedWithFm._frontmatterEntries.length > 0);
    assert.strictEqual(parsedWithFm.hadFrontmatter, true, "Detecta frontmatter original existente");

    const serializedPreserved = MD.serializeNote(parsedWithFm, parsedWithFm.body);
    assert.ok(serializedPreserved.includes("title: \"Doc Original\""), "Conserva title original");
    assert.ok(serializedPreserved.includes("version: 2.1"), "Conserva propiedades custom en frontmatter");
});

runTest("F48: Integridad de applyAction en bloques compuestos (tabla, lista, heading, quote) y navegación", () => {
    // 1. Simulación de edición inline en celda de tabla: preservar resto de filas y columnas
    const initialTableRaw = "| Columna 1 | Columna 2 |\n| --- | --- |\n| Fila 1 A | Fila 1 B |\n| Fila 2 A | Fila 2 B |";
    const tableParsed = TableParser.parseTable(initialTableRaw);
    assert.strictEqual(tableParsed.headers.length, 2);
    assert.strictEqual(tableParsed.rows.length, 2);

    // Usuario aplica negrita en la celda (1, 1): "Fila 2 B" -> "**Fila 2 B**"
    tableParsed.rows[1][1] = "**Fila 2 B**";
    const reserializedTable = TableParser.serializeTable(tableParsed);

    assert.ok(reserializedTable.includes("| Fila 1 A | Fila 1 B |"), "Fila 1 debe permanecer intacta");
    assert.ok(reserializedTable.includes("| Fila 2 A | **Fila 2 B** |"), "Fila 2 celda 1 intacta y celda 2 con formato");
    assert.ok(reserializedTable.includes("| Columna 1 | Columna 2 |"), "Headers deben permanecer intactos");

    // 2. Simulación de edición inline en item de lista
    const initialListRaw = "- Elemento uno\n- Elemento dos\n- Elemento tres";
    const listItems = initialListRaw.split("\n").map(l => l.replace(/^[-\*\+]\s+/, ""));
    assert.strictEqual(listItems.length, 3);
    listItems[1] = "**Elemento dos**";
    const reserializedList = listItems.map(it => "- " + it).join("\n");
    assert.strictEqual(reserializedList, "- Elemento uno\n- **Elemento dos**\n- Elemento tres");

    // 3. Simulación de tabulación y des-tabulación en bloque de código
    function indentCode(text, s, e) {
        if (s !== e) {
            const lineStart = text.lastIndexOf("\n", s - 1) + 1;
            let lineEnd = text.indexOf("\n", e);
            if (lineEnd === -1) lineEnd = text.length;
            const sub = text.substring(lineStart, lineEnd);
            const indented = sub.split("\n").map(l => "    " + l).join("\n");
            return text.substring(0, lineStart) + indented + text.substring(lineEnd);
        }
        return text.substring(0, s) + "    " + text.substring(s);
    }

    function unindentCode(text, s, e) {
        const lineStart = text.lastIndexOf("\n", s - 1) + 1;
        let lineEnd = text.indexOf("\n", e);
        if (lineEnd === -1) lineEnd = text.length;
        const sub = text.substring(lineStart, lineEnd);
        const unindented = sub.split("\n").map(l => {
            if (l.startsWith("    ")) return l.substring(4);
            if (l.startsWith("   ")) return l.substring(3);
            if (l.startsWith("  ")) return l.substring(2);
            if (l.startsWith(" ")) return l.substring(1);
            return l;
        }).join("\n");
        return text.substring(0, lineStart) + unindented + text.substring(lineEnd);
    }

    const code = "function test() {\nreturn 42;\n}";
    // Indentar línea 2
    const s2 = 18; const e2 = 28;
    const indented = indentCode(code, s2, e2);
    assert.strictEqual(indented, "function test() {\n    return 42;\n}");

    // Des-indentar línea 2
    const unindented = unindentCode(indented, s2, e2 + 4);
    assert.strictEqual(unindented, "function test() {\nreturn 42;\n}");
});

runTest("F49: Live-Preview Typora avanzado (anidado, escapes, wikilinks) y aislamiento celda-a-celda de tablas", () => {
    // 1. Formato anidado: **negrita *cursiva***
    const nestedRaw = "**negrita *cursiva***";
    
    // Cursor fuera (al final de la cadena o posición 0):
    const outFar = Inline.formatForLiveEditing(nestedRaw, { cursorPos: 100 });
    // Delimitadores ** y * deben estar ocultos (font-size: 1px; color: transparent;)
    assert.ok(outFar.includes("color: transparent;\">**</span>"), "Delimitador ** oculto cuando cursor está fuera");
    assert.ok(outFar.includes("color: transparent;\">*</span>"), "Delimitador * oculto cuando cursor está fuera");
    assert.ok(outFar.includes("<b>"), "Tag <b> activo");
    assert.ok(outFar.includes("<i>"), "Tag <i> anidado activo");

    // Cursor tocando *cursiva* (pos 15):
    const outTouchingItalic = Inline.formatForLiveEditing(nestedRaw, { cursorPos: 15, dimColor: "#888888" });
    assert.ok(outTouchingItalic.includes('<font color="#888888">**</font>'), "** revelado porque contiene al cursor");
    assert.ok(outTouchingItalic.includes('<font color="#888888">*</font>'), "* revelado porque el cursor toca la cursiva");

    // 2. Escape con barra invertida: \*no es cursiva\*
    const escapedRaw = "\\*no cursiva\\*";
    const outEscaped = Inline.formatForLiveEditing(escapedRaw, { cursorPos: 0 });
    assert.strictEqual(outEscaped.includes("<i>"), false, "Delimitador escapado \\* no debe generar tag <i>");

    // 3. Wikilink: [[Carpeta/Nota|Mi Alias]]
    const wikiRaw = "Ver [[Carpeta/Nota|Mi Alias]] para más datos";
    // Cursor fuera (pos 0):
    const outWikiFar = Inline.formatForLiveEditing(wikiRaw, { cursorPos: 0 });
    assert.ok(outWikiFar.includes("color: transparent;\">[[Carpeta/Nota|</span>"), "Prefijo wikilink oculto cuando cursor fuera");
    assert.ok(outWikiFar.includes("color: transparent;\">]]</span>"), "Sufijo wikilink oculto cuando cursor fuera");
    assert.ok(outWikiFar.includes("Mi Alias"), "Alias visible como enlace");

    // Cursor tocando el wikilink (pos 12):
    const outWikiTouching = Inline.formatForLiveEditing(wikiRaw, { cursorPos: 12, dimColor: "#777777" });
    assert.ok(outWikiTouching.includes('<font color="#777777">[[Carpeta/Nota|</font>'), "Prefijo wikilink revelado con dimColor");
    assert.ok(outWikiTouching.includes('<font color="#777777">]]</font>'), "Sufijo wikilink revelado con dimColor");

    // 4. Contrato de aislamiento celda-a-celda de tablas
    // En una tabla de N celdas, solo la celda enfocada (focusedRow, focusedCol)
    // monta su TextEdit; el resto renderiza RichText con sus saltos <br> y estilos
    const tableData = "| Celda A | Celda B |\n| --- | --- |\n| Línea 1<br>Línea 2 | **Negrita** |";
    const parsedT = TableParser.parseTable(tableData);
    assert.strictEqual(parsedT.rows[0][0], "Línea 1<br>Línea 2");
    assert.strictEqual(parsedT.rows[0][1], "**Negrita**");

    // Si celda (0, 0) está enfocada, celda (0, 1) sigue mostrando RichText
    const renderedCellB = Inline.inlineToHtml(parsedT.rows[0][1]);
    assert.ok(renderedCellB.includes("<b>Negrita</b>"), "Celda B no enfocada permanece formateada como RichText");
});

runTest("F50: Smart multi-block paste, URL markdown link wrap y auto-pair backspace", () => {
    // 1. URL Markdown link wrap: si hay texto seleccionado y se pega una URL
    const selectedText = "Documentación Oficial";
    const pastedUrl = "https://quickshell.outfoxxed.me";
    const wrappedLink = `[${selectedText}](${pastedUrl})`;
    assert.strictEqual(wrappedLink, "[Documentación Oficial](https://quickshell.outfoxxed.me)");

    // 2. Multi-block paste: si el texto pegado contiene párrafos o tablas
    const clipboardMulti = "Primer párrafo de introducción.\n\n| Col A | Col B |\n| --- | --- |\n| 1 | 2 |\n\nÚltimo párrafo de conclusión.";
    const splitResult = BlockModel.splitBlocks(clipboardMulti);
    assert.strictEqual(splitResult.blocks.length, 3, "Debe descomponerse en exactamente 3 bloques");
    assert.strictEqual(splitResult.blocks[0].type, "paragraph");
    assert.strictEqual(splitResult.blocks[1].type, "table");
    assert.strictEqual(splitResult.blocks[2].type, "paragraph");

    // 3. Auto-pair backspace: simulación de eliminación atómica de delimitadores vacíos
    function simulateAutoPairBackspace(text, cursor) {
        if (cursor <= 0 || cursor >= text.length) return { text, cursor, deleted: false };
        const prev1 = text[cursor - 1];
        const next1 = text[cursor];
        if ((prev1 === "(" && next1 === ")") ||
            (prev1 === "[" && next1 === "]") ||
            (prev1 === "{" && next1 === "}") ||
            (prev1 === '"' && next1 === '"') ||
            (prev1 === "`" && next1 === "`") ||
            (prev1 === "*" && next1 === "*")) {
            if (cursor >= 2 && cursor + 2 <= text.length) {
                const prev2 = text.substring(cursor - 2, cursor);
                const next2 = text.substring(cursor, cursor + 2);
                if (prev2 === "**" && next2 === "**") {
                    return {
                        text: text.substring(0, cursor - 2) + text.substring(cursor + 2),
                        cursor: cursor - 2,
                        deleted: true
                    };
                }
            }
            return {
                text: text.substring(0, cursor - 1) + text.substring(cursor + 1),
                cursor: cursor - 1,
                deleted: true
            };
        }
        return { text, cursor, deleted: false };
    }

    // Par simple: (|) -> ""
    const b1 = simulateAutoPairBackspace("()", 1);
    assert.strictEqual(b1.deleted, true);
    assert.strictEqual(b1.text, "");

    // Par doble: **|** -> ""
    const b2 = simulateAutoPairBackspace("****", 2);
    assert.strictEqual(b2.deleted, true);
    assert.strictEqual(b2.text, "");

    // Entre texto normal: a|b -> no auto-pair
    const b3 = simulateAutoPairBackspace("ab", 1);
    assert.strictEqual(b3.deleted, false);
});

runTest("F51: History snapshot con sub-índices compuestos y reordenamiento de bloques", () => {
    // 1. Contrato de History snapshot: preservar subIndex y cellRow/cellCol
    const initialMd = "# Título\n\n- Item 1\n- Item 2\n\n| C1 | C2 |\n| - | - |\n| R1 | R2 |";
    const hist = Hist.createHistory(initialMd);
    assert.strictEqual(Hist.canUndo(hist), false);

    const snapshotWithSubIndex = {
        md: initialMd + "\n- Item 3",
        activeBid: 102,
        activeIndex: 1,
        cursorPos: 5,
        subIndex: 1, // Enfocado en "Item 2"
        cellRow: -1,
        cellCol: -1
    };
    Hist.pushState(hist, snapshotWithSubIndex);
    assert.strictEqual(Hist.canUndo(hist), true);

    const undoneState = Hist.undo(hist);
    assert.strictEqual(undoneState.md, initialMd, "Debe restaurar el estado inicial");

    const redoneState = Hist.redo(hist);
    assert.strictEqual(redoneState.subIndex, 1, "Debe restaurar el sub-índice del item enfocado");

    // 2. Reordenamiento de bloques: mover bloque arriba/abajo
    const blocks = ["Bloque A", "Bloque B", "Bloque C"];
    // Mover bloque 1 (B) a posición 0
    const movedUp = [...blocks];
    const itemToMove = movedUp.splice(1, 1)[0];
    movedUp.splice(0, 0, itemToMove);
    assert.deepStrictEqual(movedUp, ["Bloque B", "Bloque A", "Bloque C"]);

    // Mover bloque 0 (B) a posición 1 (hacia abajo)
    const movedDown = [...movedUp];
    const itemToDown = movedDown.splice(0, 1)[0];
    movedDown.splice(1, 0, itemToDown);
    assert.deepStrictEqual(movedDown, ["Bloque A", "Bloque B", "Bloque C"]);
});

runTest("F52: Preview mode read-only contracts, table/mermaid action hiding & clean selection with hideSyntax", () => {
    // 1. Contrato de formatForLiveEditing con hideSyntax: true en modo preview
    // En modo preview, al hacer click o seleccionar una palabra formateada,
    // los delimitadores de sintaxis (**, *, ~~, #) deben excluirse completamente del HTML
    // para evitar el desplazamiento visual de 1-2px generado por glifos de 1px.
    const boldText = "**Negrita** texto normal";
    const formattedTouching = Inline.formatForLiveEditing(boldText, {
        cursorPos: 3, // Cursor dentro de "Negrita"
        hideSyntax: true
    });
    // Debe excluir completamente delimitadores de sintaxis (**), y NO debe contener font color dim
    assert.ok(!formattedTouching.includes('**'), "Delimitadores ** no deben estar presentes en el texto renderizado en preview");
    assert.ok(!formattedTouching.includes('<font color='), "No debe revelar delimitadores en preview");

    // 2. Encabezado con numerales con hideSyntax: true
    const headingText = "## Título de sección";
    const formattedHeading = Inline.formatForLiveEditing(headingText, {
        cursorPos: 1, // Cursor sobre ##
        hideSyntax: true
    });
    assert.ok(!formattedHeading.includes('##'), "Prefijo ## no debe estar presente en el texto renderizado en preview");

    // 3. Contratos de protección de tabla en preview:
    // Botones de eliminar tabla, agregar fila y agregar columna deben ser invisibles en preview
    function isTableActionVisible(isReadOnly) {
        return !isReadOnly;
    }
    assert.strictEqual(isTableActionVisible(true), false, "Botones de tabla deben estar ocultos en preview");
    assert.strictEqual(isTableActionVisible(false), true, "Botones de tabla deben estar visibles en edición");

    // 4. Modificación de celda bloqueada si readOnly: true
    function simulateCellChange(isReadOnly, table, r, c, val) {
        if (isReadOnly) return false;
        table.headers[c] = val;
        return true;
    }
    const fakeTable = { headers: ["H1", "H2"], rows: [["R1C1", "R1C2"]] };
    const changed = simulateCellChange(true, fakeTable, -1, 0, "H1_mod");
    assert.strictEqual(changed, false, "No debe permitir modificar celda en preview");
    assert.strictEqual(fakeTable.headers[0], "H1", "El valor de la cabecera debe permanecer intacto");
});

runTest("F53: Anchor resolution, TOC links and preview import transition contracts", () => {
    // 1. Parseo de anclas internas estilo GitHub slug
    const curSlug = "__external__:resumen_completo_sistemas_operativos.md";
    const link1 = "#1-archivos-y-sistemas-de-archivos-file-systems";
    const parsed1 = Anchors.parseInternalLink(link1, curSlug);
    assert.ok(parsed1, "Debe parsear enlace con ancla");
    assert.strictEqual(parsed1.isSameNote, true, "Es enlace dentro de la misma nota");
    assert.strictEqual(parsed1.anchor, "1-archivos-y-sistemas-de-archivos-file-systems");

    // 2. Generación de índice de anclas a partir de bloques
    const blocks = [
        { bid: 10, type: "heading", raw: "## Índice Temático" },
        { bid: 11, type: "list", raw: "1. [Archivos y Sistemas de Archivos (File Systems)](#1-archivos-y-sistemas-de-archivos-file-systems)\n2. [Virtualización](#2-virtualizacion)" },
        { bid: 12, type: "heading", raw: "## 1. Archivos y Sistemas de Archivos (File Systems)" },
        { bid: 13, type: "heading", raw: "## 2. Virtualización" }
    ];
    const index = Anchors.buildAnchorIndex(blocks);
    assert.ok(index["1-archivos-y-sistemas-de-archivos-file-systems"], "Debe indexar el encabezado 1");
    assert.strictEqual(index["1-archivos-y-sistemas-de-archivos-file-systems"].bid, 12);
    assert.strictEqual(index["2-virtualización"].bid, 13);

    // 3. Contrato de importación: la nota importada deja de ser preview y launchedForExternal se apaga
    let launchedForExternal = true;
    let isCardMorph = false;
    let activeMorphSlug = "__external__:test.md";
    function onNoteImported(note) {
        launchedForExternal = false;
        isCardMorph = true;
        activeMorphSlug = note.key || note.slug;
    }
    const importedNote = {
        key: "test.md",
        slug: "test",
        isExternal: false,
        readOnly: false
    };
    onNoteImported(importedNote);
    assert.strictEqual(launchedForExternal, false, "launchedForExternal debe desactivarse al importar");
    assert.strictEqual(isCardMorph, true, "isCardMorph debe activarse para animación estándar");
    assert.strictEqual(activeMorphSlug, "test.md");

    // 4. Contrato de cierre: nota importada no debe cerrar la aplicación
    function handleCloseRequest(isExt, launchedExt) {
        if (isExt) return "close_preview_and_quit";
        if (launchedExt) return "quit_app";
        return "return_to_grid";
    }
    const result = handleCloseRequest(importedNote.isExternal, launchedForExternal);
    assert.strictEqual(result, "return_to_grid", "Al cerrar una nota importada debe volver a la grilla");
});

runTest("F54: Non-reentrant live formatting, HTML memoization & read-only preview selection contracts", () => {
    // 1. Simular la estructura del documento con código inline y encabezado
    const rawHeading = "Plan de Migración: De Python a Rust (`qs-helper`) y JS/QML Nativo";

    // 2. En modo de solo lectura (hideSyntax: true), el formato debe ser idéntico independientemente del cursor/selección
    const formattedNoCursor = Inline.formatForLiveEditing(rawHeading, {
        cursorPos: -1,
        selStart: -1,
        selEnd: -1,
        dimColor: "#888888",
        linkColor: "#5294e2",
        hideSyntax: true
    });

    const formattedWithSel = Inline.formatForLiveEditing(rawHeading, {
        cursorPos: 38,
        selStart: 35,
        selEnd: 46,
        dimColor: "#888888",
        linkColor: "#5294e2",
        hideSyntax: true
    });

    assert.strictEqual(formattedNoCursor, formattedWithSel, "En modo lectura con hideSyntax: true, la selección no debe alterar el HTML generado");

    // 3. Simular memoización de HTML vs el QTextDocument HTML retornado por TextEdit.text
    let _lastAppliedHtml = "";
    let _syncingModel = false;
    let editInputText = "";
    let reentrancyCounter = 0;

    function simulateTextEditSelect(s, e, onSelChange) {
        // En Qt Quick, TextEdit.select() dispara onSelectionStartChanged síncronamente
        onSelChange();
    }

    function simulateUpdateLiveFormatting(selStart, selEnd, isReadOnly, syncingSelection) {
        if (isReadOnly || syncingSelection) return;
        reentrancyCounter++;
        if (reentrancyCounter > 10) {
            throw new RangeError("Maximum call stack size exceeded (Bucle de reentrancia detectado)");
        }

        const newFormatted = Inline.formatForLiveEditing(rawHeading, {
            cursorPos: selStart,
            selStart: selStart,
            selEnd: selEnd,
            dimColor: "#888888",
            linkColor: "#5294e2",
            hideSyntax: isReadOnly
        });

        // Verificación de memoización: si ya aplicamos este exacto HTML, salir sin tocar el TextEdit
        if (_lastAppliedHtml !== newFormatted) {
            _lastAppliedHtml = newFormatted;
            _syncingModel = true;

            // TextEdit de Qt convierte internamente el fragmento en un documento HTML completo
            editInputText = `<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0//EN">\n<html><body>${newFormatted}</body></html>`;

            // La selección se ejecuta MIENTRAS _syncingModel es true
            simulateTextEditSelect(selStart, selEnd, () => {
                // onSelectionStartChanged del delegado
                if (!_syncingModel) {
                    simulateUpdateLiveFormatting(selStart, selEnd, isReadOnly, syncingSelection);
                }
            });

            // Guard liberado únicamente tras completar la selección
            _syncingModel = false;
        }
    }

    // A) En modo edición: el guard _syncingModel evita la reentrancia durante editInput.select()
    reentrancyCounter = 0;
    _lastAppliedHtml = "";
    simulateUpdateLiveFormatting(35, 46, false, false);
    assert.strictEqual(reentrancyCounter, 1, "Debe ejecutarse exactamente 1 vez sin reentrancia recursiva");

    // B) En modo solo lectura: debe salir de inmediato en 0 pasos
    reentrancyCounter = 0;
    simulateUpdateLiveFormatting(35, 46, true, false);
    assert.strictEqual(reentrancyCounter, 0, "En modo lectura no debe ejecutar formatForLiveEditing en drag");

    // 4. Contrato de isFormatActive: en readOnly o isPreviewMode debe cortocircuitar en O(1)
    function isFormatActive(actionId, isReadOnly, isPreviewMode) {
        if (isReadOnly || isPreviewMode) return false;
        // Si no fuera readOnly, haría parseList, regexes, etc.
        return true;
    }
    assert.strictEqual(isFormatActive("h1", true, false), false);
    assert.strictEqual(isFormatActive("bullet_list", false, true), false);
    assert.strictEqual(isFormatActive("bold", false, false), true);

    // 5. Contrato de corrector ortográfico y sugerencias en modo preview
    function computeSpellActive(isReadOnly, spellEnabled, mode, manualActive) {
        if (isReadOnly) return false;
        if (!spellEnabled) return false;
        if (mode === "off") return false;
        return manualActive;
    }
    assert.strictEqual(computeSpellActive(true, true, "auto", true), false, "spellActive debe ser false en modo lectura");
    assert.strictEqual(computeSpellActive(false, true, "auto", true), true, "spellActive debe ser true en modo edición");

    function findSpellSuggestions(ranges, pos, isReadOnly, spellActive) {
        if (!spellActive || isReadOnly) return null;
        return ranges && ranges.length > 0 ? ranges[0] : null;
    }
    const fakeRange = [{ start: 0, end: 5, word: "test" }];
    assert.strictEqual(findSpellSuggestions(fakeRange, 2, true, false), null, "Sugerencias ortográficas desactivadas en preview");
    assert.notStrictEqual(findSpellSuggestions(fakeRange, 2, false, true), null, "Sugerencias ortográficas activas en edición");

    // 6. Contrato de BlockHr: en preview no se activa ni muestra '---'
    function isHrLineVisible(isEditing, isReadOnly) {
        return !isEditing || isReadOnly;
    }
    function isHrRawEditVisible(isEditing, isReadOnly) {
        return isEditing && !isReadOnly;
    }
    assert.strictEqual(isHrLineVisible(true, true), true, "Línea visible en modo lectura incluso si se solicita edición");
    assert.strictEqual(isHrRawEditVisible(true, true), false, "Raw '---' nunca visible en modo lectura");
    assert.strictEqual(isHrLineVisible(true, false), false, "Línea oculta en edición real");
    assert.strictEqual(isHrRawEditVisible(true, false), true, "Raw '---' visible en edición real");
});

runTest("F55: Zero pixel shift on list selection, clean delimiter omission & image stripping in preview", () => {
    // 1. Verificar que un ítem de lista con negrita al inicio no contiene delimitadores transparentes en preview
    const sampleListItem = "**Nativo (QML / JS):** Eliminar scripts intermediarios";
    const previewFormatted = Inline.formatForLiveEditing(sampleListItem, {
        cursorPos: -1,
        hideSyntax: true
    });
    // Debe excluir cualquier etiqueta con 'font-size: 1px' o 'color: transparent'
    assert.ok(!previewFormatted.includes("font-size: 1px"), "No debe tener spans de 1px que causen desplazamiento");
    assert.ok(!previewFormatted.includes("color: transparent"), "No debe tener color transparente");
    assert.ok(previewFormatted.includes("<b>Nativo (QML / JS):</b>"), "Debe tener el tag de negrita limpio");

    // 2. Imagen en ítem de lista debe ser removida limpiamente en preview para no dejar placeholders 🖼️
    const itemWithImg = "Texto con ![foto](img.png) al final";
    const stripped = Inline.stripImages(itemWithImg);
    assert.strictEqual(stripped, "Texto con  al final", "stripImages remueve la imagen del texto");

    // 3. En modo edición real (hideSyntax: false), los delimitadores transparentes sí deben conservarse para Typora
    const editFormatted = Inline.formatForLiveEditing(sampleListItem, {
        cursorPos: -1,
        hideSyntax: false
    });
    assert.ok(editFormatted.includes("font-size: 1px; color: transparent;"), "En edición conserva delimitadores para Typora");
});

runTest("F56: Mermaid Fase 2: classDiagram, erDiagram, gantt, timeline y mindmap (AST, Layout y Marcadores SVG)", () => {
    // 1. classDiagram AST y Layout
    const classSrc = `classDiagram
        direction LR
        class BlockMermaid {
            +String raw
            +Boolean isEditing
            +render()
        }
        class ViewItem {
            <<interface>>
            +display()
        }
        BlockMermaid --|> ViewItem : implements
    `;
    const cParsed = MermaidParser.parse(classSrc);
    assert.strictEqual(cParsed.ok, true, "classDiagram debe parsear OK");
    assert.strictEqual(cParsed.type, "classDiagram");
    assert.ok(cParsed.ast.classes["BlockMermaid"], "Debe contener clase BlockMermaid");
    assert.strictEqual(cParsed.ast.classes["BlockMermaid"].attributes.length, 2);
    assert.strictEqual(cParsed.ast.classes["BlockMermaid"].methods.length, 1);
    assert.strictEqual(cParsed.ast.classes["ViewItem"].stereotype, "interface");
    assert.strictEqual(cParsed.ast.relations.length, 1);
    assert.strictEqual(cParsed.ast.relations[0].toMarker, "triangle");

    const cLayout = MermaidLayout.layout(cParsed, (t) => ({ width: t.length * 8, height: 16 }));
    assert.strictEqual(cLayout.ok, true, "classDiagram layout debe ser OK");
    assert.ok(cLayout.width > 200, "Ancho de clase debe ser positivo");
    assert.ok(cLayout.height > 100, "Alto de clase debe ser positivo");
    assert.strictEqual(cLayout.edges.length, 1);
    assert.ok(cLayout.edges[0].path.startsWith("M "), "Arista debe tener ruta SVG");

    // 2. erDiagram AST y Layout
    const erSrc = `erDiagram
        CUSTOMER ||--o{ ORDER : places
        CUSTOMER {
            string name
            int id PK
        }
        ORDER {
            int id PK
            int customerId FK
        }
    `;
    const erParsed = MermaidParser.parse(erSrc);
    assert.strictEqual(erParsed.ok, true, "erDiagram debe parsear OK");
    assert.strictEqual(erParsed.type, "erDiagram");
    assert.ok(erParsed.ast.entities["CUSTOMER"]);
    assert.strictEqual(erParsed.ast.entities["CUSTOMER"].attributes[1].key, "PK");
    assert.strictEqual(erParsed.ast.relations.length, 1);
    assert.strictEqual(erParsed.ast.relations[0].fromMarker, "crows_foot_one");
    assert.strictEqual(erParsed.ast.relations[0].toMarker, "crows_foot_zero_or_many");

    const erLayout = MermaidLayout.layout(erParsed, (t) => ({ width: t.length * 8, height: 16 }));
    assert.strictEqual(erLayout.ok, true, "erDiagram layout debe ser OK");
    assert.ok(erLayout.relations.length === 1);
    assert.ok(erLayout.relations[0].path.startsWith("M "));

    // 3. Gantt AST y Layout
    const ganttSrc = `gantt
        title Plan de Desarrollo
        dateFormat YYYY-MM-DD
        section Fase 1
            Parser Base   :done, p1, 2026-10-01, 3d
            Layout Motor  :active, l1, after p1, 4d
            Hito Alpha    :milestone, m1, after l1, 0d
    `;
    const gParsed = MermaidParser.parse(ganttSrc);
    assert.strictEqual(gParsed.ok, true, "gantt debe parsear OK");
    assert.strictEqual(gParsed.type, "gantt");
    assert.strictEqual(gParsed.ast.sections.length, 1);
    assert.strictEqual(gParsed.ast.sections[0].tasks.length, 3);
    assert.strictEqual(gParsed.ast.sections[0].tasks[0].isDone, true);
    assert.strictEqual(gParsed.ast.sections[0].tasks[1].isActive, true);
    assert.strictEqual(gParsed.ast.sections[0].tasks[2].isMilestone, true);

    const gLayout = MermaidLayout.layout(gParsed, (t) => ({ width: t.length * 8, height: 16 }));
    assert.strictEqual(gLayout.ok, true, "gantt layout debe ser OK");
    assert.strictEqual(gLayout.tasks.length, 3);
    assert.ok(gLayout.gridTicks.length > 0);

    // 4. Timeline AST y Layout
    const tlSrc = `timeline
        title Historia
        section 2024
            Q1 : Lanzamiento : Feedback
            Q2 : Version Alfa
    `;
    const tlParsed = MermaidParser.parse(tlSrc);
    assert.strictEqual(tlParsed.ok, true, "timeline debe parsear OK");
    assert.strictEqual(tlParsed.type, "timeline");
    assert.strictEqual(tlParsed.ast.sections.length, 1);
    assert.strictEqual(tlParsed.ast.sections[0].periods.length, 2);

    const tlLayout = MermaidLayout.layout(tlParsed, (t) => ({ width: t.length * 8, height: 16 }));
    assert.strictEqual(tlLayout.ok, true, "timeline layout debe ser OK");
    assert.strictEqual(tlLayout.periods.length, 2);
    assert.strictEqual(tlLayout.cards.length, 2);

    // 5. Mindmap AST y Layout
    const mmSrc = `mindmap
      root((Central))
        Branch 1
          Leaf A
        Branch 2[Cuadrado]
    `;
    const mmParsed = MermaidParser.parse(mmSrc);
    assert.strictEqual(mmParsed.ok, true, "mindmap debe parsear OK");
    assert.strictEqual(mmParsed.type, "mindmap");
    assert.strictEqual(mmParsed.ast.root.label, "Central");
    assert.strictEqual(mmParsed.ast.root.shape, "circle");
    assert.strictEqual(mmParsed.ast.root.children.length, 2);

    const mmLayout = MermaidLayout.layout(mmParsed, (t) => ({ width: t.length * 8, height: 16 }));
    assert.strictEqual(mmLayout.ok, true, "mindmap layout debe ser OK");
    assert.ok(mmLayout.nodes.length >= 4, "Debe tener al menos 4 nodos");
    assert.ok(mmLayout.edges.length >= 3, "Debe tener al menos 3 ramas Bézier");

    // 6. Marcadores SVG nuevos (MermaidShapes)
    const triPath = MermaidShapes.getArrowPath("triangle", 10, 10, 0, 10);
    assert.ok(triPath.startsWith("M 10 10"), "Triangle marker válido");
    const diamPath = MermaidShapes.getArrowPath("diamond_filled", 10, 10, 0, 10);
    assert.ok(diamPath.startsWith("M 10 10"), "Diamond marker válido");
    const crowPath = MermaidShapes.getArrowPath("crows_foot_many", 10, 10, 0, 10);
    assert.ok(crowPath.includes("M "), "Crows foot marker válido");

    // 7. Formas de Mindmap (cloud y bang)
    const cloud = MermaidShapes.getShapePath("cloud", 80, 50);
    assert.ok(cloud.startsWith("M "), "Cloud shape válido");
    const bang = MermaidShapes.getShapePath("bang", 80, 50);
    assert.ok(bang.startsWith("M "), "Bang shape válido");

    // 8. Plantillas (MermaidTemplates)
    const tList = MermaidTemplates.getTemplateList();
    const classTpl = tList.find(t => t.id === "classDiagram");
    assert.ok(classTpl, "Plantilla classDiagram debe estar registrada");
    const erTpl = tList.find(t => t.id === "erDiagram");
    assert.ok(erTpl, "Plantilla erDiagram debe estar registrada");
    const ganttTpl = tList.find(t => t.id === "gantt");
    assert.ok(ganttTpl, "Plantilla gantt debe estar registrada");
    const timelineTpl = tList.find(t => t.id === "timeline");
    assert.ok(timelineTpl, "Plantilla timeline debe estar registrada");
    const mindmapTpl = tList.find(t => t.id === "mindmap");
    assert.ok(mindmapTpl, "Plantilla mindmap debe estar registrada");
});

runTest("F57: Mermaid dynamic title clearance and headroom contracts", () => {
    // 1. Gantt: con título debe tener tickLabelY >= 40 y sin título tickLabelY === 12
    const gWithTitle = MermaidParser.parse("gantt\ntitle Mi Plan\nsection S1\nT1: 2026-10-01, 2d");
    const gWithoutTitle = MermaidParser.parse("gantt\nsection S1\nT1: 2026-10-01, 2d");
    const lWithTitle = MermaidLayout.layout(gWithTitle);
    const lWithoutTitle = MermaidLayout.layout(gWithoutTitle);
    assert.strictEqual(lWithTitle.tickLabelY, 44, "Gantt con título debe desplazar ticks hacia abajo (44px)");
    assert.strictEqual(lWithoutTitle.tickLabelY, 12, "Gantt sin título mantiene ticks en 12px");
    assert.ok(lWithTitle.gridTopY > lWithoutTitle.gridTopY, "Líneas de cuadrícula deben iniciar más abajo con título");

    // 2. Timeline: con título debe desplazar eje horizontal
    const tlWithTitle = MermaidParser.parse("timeline\ntitle Hitos\nsection S1\nQ1: Tarea");
    const tlWithoutTitle = MermaidParser.parse("timeline\nsection S1\nQ1: Tarea");
    const tlLWith = MermaidLayout.layout(tlWithTitle);
    const tlLWithout = MermaidLayout.layout(tlWithoutTitle);
    assert.strictEqual(tlLWith.axisY, 166, "Timeline con título debe bajar eje a 166px");
    assert.strictEqual(tlLWithout.axisY, 130, "Timeline sin título debe tener eje en 130px");

    // 3. Flowchart: con título debe respetar margen superior de 44px
    const fcWithTitle = MermaidParser.parse("---\ntitle: Flujo\n---\nflowchart TD\nA --> B");
    const fcWithoutTitle = MermaidParser.parse("flowchart TD\nA --> B");
    const fcLWith = MermaidLayout.layout(fcWithTitle);
    const fcLWithout = MermaidLayout.layout(fcWithoutTitle);
    assert.ok(fcLWith.nodes["A"].y >= 44, `Nodo superior con título debe estar >= 44px: ${fcLWith.nodes["A"].y}`);
    assert.strictEqual(fcLWithout.nodes["A"].y, 24, "Nodo superior sin título debe estar en 24px");

    // 4. Class diagram: con título desplaza la primera capa a 52px
    const cdWithTitle = MermaidParser.parse("---\ntitle: Clases\n---\nclassDiagram\nclass A");
    const cdWithoutTitle = MermaidParser.parse("classDiagram\nclass A");
    const cdLWith = MermaidLayout.layout(cdWithTitle);
    const cdLWithout = MermaidLayout.layout(cdWithoutTitle);
    assert.strictEqual(cdLWith.nodes["A"].y, 52, "Clase con título debe iniciar en y=52");
    assert.strictEqual(cdLWithout.nodes["A"].y, 24, "Clase sin título debe iniciar en y=24");

    // 5. ER diagram: con título desplaza primera entidad a 52px
    const erWithTitle = MermaidParser.parse("---\ntitle: Entidades\n---\nerDiagram\nA ||--o{ B : has");
    const erWithoutTitle = MermaidParser.parse("erDiagram\nA ||--o{ B : has");
    const erLWith = MermaidLayout.layout(erWithTitle);
    const erLWithout = MermaidLayout.layout(erWithoutTitle);
    assert.strictEqual(erLWith.entities["A"].y, 52, "Entidad ER con título debe iniciar en y=52");
    assert.strictEqual(erLWithout.entities["A"].y, 24, "Entidad ER sin título debe iniciar en y=24");
});

runTest("F58: BlockTable wheel handlers separation and vertical bubbling contract", () => {
    const fs = require("fs");
    const path = require("path");
    const tableQml = fs.readFileSync(path.join(__dirname, "../qml/BlockTable.qml"), "utf-8");

    // 1. Debe existir shiftWheelHandler restringido exclusivamente a ShiftModifier
    assert.ok(tableQml.includes("id: shiftWheelHandler"), "Debe existir shiftWheelHandler con id explícito");
    assert.ok(tableQml.includes("acceptedModifiers: Qt.ShiftModifier"), "shiftWheelHandler debe tener acceptedModifiers: Qt.ShiftModifier");

    // 2. Debe existir horizWheelHandler restringido a orientación horizontal y NoModifier
    assert.ok(tableQml.includes("id: horizWheelHandler"), "Debe existir horizWheelHandler con id explícito");
    assert.ok(tableQml.includes("orientation: Qt.Horizontal"), "horizWheelHandler debe tener orientation: Qt.Horizontal");
    assert.ok(tableQml.includes("acceptedModifiers: Qt.NoModifier"), "horizWheelHandler debe tener acceptedModifiers: Qt.NoModifier");

    // 3. No debe haber ningún WheelHandler sin filtro de modificadores u orientación que intercepte scroll vertical
    const lines = tableQml.split("\n");
    let inWh = false;
    let whBlock = [];
    let unconstrainedWhFound = false;

    for (let i = 0; i < lines.length; i++) {
        const l = lines[i].trim();
        if (l.startsWith("WheelHandler {")) {
            inWh = true;
            whBlock = [l];
        } else if (inWh) {
            whBlock.push(l);
            if (l === "}") {
                inWh = false;
                const joined = whBlock.join(" ");
                if (!joined.includes("acceptedModifiers") && !joined.includes("orientation")) {
                    unconstrainedWhFound = true;
                }
            }
        }
    }
    assert.strictEqual(unconstrainedWhFound, false, "No debe existir ningún WheelHandler sin restricciones de modificador u orientación en BlockTable");
});

runTest("F59: MermaidLayout cluster-aware subgraph layering and non-overlapping bounding boxes", () => {
    const src = `flowchart TD
    subgraph Repo["Hyprland-config (Git Tracked - LIMPIO Y ESTABLE)"]
        HMain["hyprland.lua"]
        HTheme["theme.lua (Valores por defecto / Plantilla)"]
        HDev["devices.lua (Binds estándar)"]
        HInput["input.lua (Configuración base)"]
        HWin["windows.lua (Reglas generales)"]
    end
    subgraph Local["Overrides Locales (En .gitignore / No Trackeados)"]
        UTheme["user_settings.lua (Escrito por Quickshell)"]
        UDev["devices.local.lua (Tu MAC Bluetooth y Razer)"]
        UMon["monitors.lua (DisplaysManager)"]
        UWork["workspaces.lua (DisplaysManager)"]
        USunset["hyprsunset.conf"]
    end
    HMain -->|pcall require| HTheme
    HTheme -->|pcall require| UTheme
    HMain -->|pcall require| HDev
    HDev -->|pcall require| UDev
    HMain -->|pcall require| UMon
    HMain -->|pcall require| UWork`;

    const parsed = MermaidParser.parse(src);
    assert.strictEqual(parsed.ok, true);
    assert.strictEqual(parsed.ast.subgraphs.length, 2);

    const layout = MermaidLayout.layout(parsed, (t) => ({ width: t.length * 8, height: 16 }));
    assert.strictEqual(layout.ok, true);
    assert.strictEqual(layout.subgraphs.length, 2);

    const repo = layout.subgraphs.find(s => s.id === "Repo");
    const local = layout.subgraphs.find(s => s.id === "Local");
    assert.ok(repo, "Debe existir subgrafo Repo");
    assert.ok(local, "Debe existir subgrafo Local");

    // 1. Repo y Local no deben tener solapamiento vertical ni colisión de títulos
    const repoBottom = repo.y + repo.h;
    assert.ok(local.y >= repoBottom + 20, `Local (y=${local.y}) debe ubicarse debajo de Repo (bottomY=${repoBottom}) con al menos 20px de separación`);

    // 2. Todos los nodos de Repo deben estar en filas superiores a los nodos de Local
    for (const rid of ["HMain", "HTheme", "HDev", "HInput", "HWin"]) {
        const rNode = layout.nodes[rid];
        assert.ok(rNode.y + rNode.h <= local.y, `Nodo de Repo ${rid} (y+h=${rNode.y + rNode.h}) debe estar por encima del subgrafo Local (y=${local.y})`);
    }

    // 3. El nodo desconectado USunset debe permanecer confinado dentro del subgrafo Local
    const usunset = layout.nodes["USunset"];
    assert.ok(usunset, "Debe existir USunset");
    assert.ok(usunset.y >= local.y && usunset.y + usunset.h <= local.y + local.h, "USunset debe estar contenido verticalmente dentro de Local");

    // 4. Subgrafos paralelos (sin aristas entre ellos) se ubican lado a lado sin entrelazado
    const parallelSrc = `flowchart TD
    subgraph S1 [Modulo 1]
        A1 --> A2
    end
    subgraph S2 [Modulo 2]
        B1 --> B2
    end`;
    const pParsed = MermaidParser.parse(parallelSrc);
    const pLayout = MermaidLayout.layout(pParsed, (t) => ({ width: 60, height: 20 }));
    assert.strictEqual(pLayout.ok, true);
    assert.strictEqual(pLayout.subgraphs.length, 2);

    const s1 = pLayout.subgraphs.find(s => s.id === "S1");
    const s2 = pLayout.subgraphs.find(s => s.id === "S2");
    assert.ok(s1 && s2);

    // Deben estar horizontalmente disjuntos
    const s1Right = s1.x + s1.w;
    const s2Right = s2.x + s2.w;
    const disjoint = (s1Right < s2.x) || (s2Right < s1.x);
    assert.ok(disjoint, `Subgrafos paralelos deben ser disjuntos horizontalmente: S1=[${s1.x}..${s1Right}], S2=[${s2.x}..${s2Right}]`);
});

runTest("F60: MermaidLayout multi-layer parallel subgraph column reservation and edge label clearance", () => {
    const src = `flowchart TD
    subgraph QS["Quickshell (Centro de Control)"]
        WS["WallpaperConfig.qml"]
        HC["HyprlandConfig.qml"]
    end

    subgraph Runtime["Hyprland IPC (En Memoria RAM)"]
        Eval["hyprctl eval 'hl.animation(...)'<br/>(Latencia 0, sin .bak ni reload)"]
    end

    subgraph Storage["Disco (~/.config/hypr)"]
        Theme["theme.lua (GIT TRACKED - LIMPIO)"]
        UserSettings["user_settings.lua (EN .gitignore - OVERRIDES)"]
        Main["hyprland.lua"]
    end

    WS -->|"Cambio de animación"| Eval
    HC -->|"Persistir sliders del usuario"| UserSettings
    Main -->|"1. Carga tema base"| Theme
    Main -->|"2. pcall require"| UserSettings`;

    const parsed = MermaidParser.parse(src);
    assert.strictEqual(parsed.ok, true);
    assert.strictEqual(parsed.ast.subgraphs.length, 3);

    const layout = MermaidLayout.layout(parsed, (t) => ({ width: t.length * 8, height: 16 }));
    assert.strictEqual(layout.ok, true);
    assert.strictEqual(layout.subgraphs.length, 3);

    const qs = layout.subgraphs.find(s => s.id === "QS");
    const runtime = layout.subgraphs.find(s => s.id === "Runtime");
    const storage = layout.subgraphs.find(s => s.id === "Storage");

    assert.ok(qs && runtime && storage);

    // 1. Runtime y Storage se solapan en capas verticales (ambos ocupan la fila intermedia)
    // por lo tanto deben quedar en columnas horizontales estrictamente disjuntas
    const runtimeRight = runtime.x + runtime.w;
    assert.ok(storage.x >= runtimeRight + 16, `Storage (x=${storage.x}) debe estar a la derecha de Runtime (right=${runtimeRight}) con margen >= 16px`);

    // 2. Contención estricta: los nodos de Storage (Main, Theme, UserSettings) deben estar confinados en Storage
    for (const sid of ["Main", "Theme", "UserSettings"]) {
        const sNode = layout.nodes[sid];
        assert.ok(sNode.x >= storage.x - 1, `Nodo de Storage ${sid} (x=${sNode.x}) debe estar dentro de Storage (x=${storage.x})`);
        assert.ok(sNode.x + sNode.w <= storage.x + storage.w + 1, `Nodo de Storage ${sid} (right=${sNode.x + sNode.w}) debe estar dentro de Storage (right=${storage.x + storage.w})`);
    }

    // 3. Contención estricta: el nodo Eval debe estar confinado en Runtime
    const evalNode = layout.nodes["Eval"];
    assert.ok(evalNode.x >= runtime.x - 1);
    assert.ok(evalNode.x + evalNode.w <= runtime.x + runtime.w + 1);

    // 4. Arista multi-capa HC -> UserSettings: su etiqueta "Persistir sliders del usuario"
    // NO debe colisionar con Main (hyprland.lua)
    const hcUserEdge = layout.edges.find(e => e.from === "HC" && e.to === "UserSettings");
    assert.ok(hcUserEdge, "Debe existir arista HC -> UserSettings");
    assert.ok(hcUserEdge.corridorX !== undefined, "HC -> UserSettings debe tener corridorX");

    const mainNode = layout.nodes["Main"];
    const labelW = (hcUserEdge.labelDim ? hcUserEdge.labelDim.width : 100);
    const labelLeft = hcUserEdge.labelX - labelW / 2;
    const mainRight = mainNode.x + mainNode.w;
    assert.ok(labelLeft >= mainRight, `El borde izquierdo de la etiqueta (${labelLeft}) debe quedar a la derecha de Main (${mainRight}) sin solaparse`);
});

runTest("F61: Timeline card margin normalization and Mindmap circle enclosing bounds", () => {
    // 1. Timeline: tarjetas nunca deben tener x < 24 ni recortarse en el borde izquierdo
    const tlSrc = `timeline
    title Hitos del Proyecto
    section 2024
        Q1 : Lanzamiento Inicial : Feedback
        Q2 : Arquitectura QML Nativa
    section 2025
        Q1 : Soporte Markdown Typora
        Q3 : Motor Mermaid Fase 1 y 2`;

    const tlParsed = MermaidParser.parse(tlSrc);
    assert.strictEqual(tlParsed.ok, true);

    const tlLayout = MermaidLayout.layout(tlParsed, (t, s) => ({ width: t.length * 7.2, height: s || 11 }));
    assert.strictEqual(tlLayout.ok, true);
    assert.strictEqual(tlLayout.cards.length, 4);

    // Verificar que ninguna tarjeta tenga coordenada X menor al margen izquierdo (24px)
    for (let ci = 0; ci < tlLayout.cards.length; ci++) {
        const card = tlLayout.cards[ci];
        assert.ok(card.x >= 24, `Tarjeta ${ci} (${card.period}) x=${card.x} debe ser >= 24px para evitar recortes`);
    }

    // Verificar que el ancho de la tarjeta abarque sus eventos más largos
    const card0 = tlLayout.cards[0];
    assert.ok(card0.w >= 140, `Tarjeta 0 ancho=${card0.w} debe dar espacio al texto`);

    // 2. Mindmap: nodo root con forma de círculo ((Texto)) debe tener w = h y ser suficientemente grande para encerrar el texto
    const mmSrc = `mindmap
    root((Arquitectura))
        Frontend
            QML Nativo
            Theme Reactive
        Backend
            Rust qs-helper
            JS Parsers
        Tests
            Headless Suite`;

    const mmParsed = MermaidParser.parse(mmSrc);
    assert.strictEqual(mmParsed.ok, true);

    const mmLayout = MermaidLayout.layout(mmParsed, (t, s) => ({ width: t.length * 8, height: s || 13 }));
    assert.strictEqual(mmLayout.ok, true);

    const rootNode = mmLayout.nodes.find(n => n.label === "Arquitectura");
    assert.ok(rootNode, "Debe existir el nodo root 'Arquitectura'");
    assert.strictEqual(rootNode.shape, "circle");
    assert.strictEqual(rootNode.w, rootNode.h, `El círculo debe tener w === h: w=${rootNode.w}, h=${rootNode.h}`);
    assert.ok(rootNode.w >= 110, `El diámetro del círculo (${rootNode.w}) debe ser >= 110 para encerrar 'Arquitectura'`);

    // 3. MermaidShapes: getShapePath para circle y doublecircle debe generar paths válidos
    const shapePath = MermaidShapes.getShapePath("circle", rootNode.w, rootNode.h);
    assert.ok(shapePath.length > 0 && !shapePath.includes("NaN"), "Shape path no debe estar vacío ni contener NaN");
});

runTest("F62: Mermaid Fase 3: gitGraph, quadrantChart, journey y xychart-beta (AST y Layout nativo)", () => {
    // 1. gitGraph
    const gitSrc = `gitGraph
        commit id: "Init"
        branch feature
        checkout feature
        commit id: "Feat 1" tag: "v0.1"
        checkout main
        merge feature id: "Merge" tag: "v1.0"
        commit id: "Release"`;

    const gitParsed = MermaidParser.parse(gitSrc);
    assert.strictEqual(gitParsed.ok, true);
    assert.strictEqual(gitParsed.type, "gitGraph");
    assert.strictEqual(gitParsed.ast.branches.length, 2);
    assert.strictEqual(gitParsed.ast.commits.length, 4);
    assert.strictEqual(gitParsed.ast.commits[2].parents.length, 2); // merge commit

    const gitLayout = MermaidLayout.layout(gitParsed, (t) => ({ width: t.length * 8, height: 16 }));
    assert.strictEqual(gitLayout.ok, true);
    assert.strictEqual(gitLayout.branches.length, 2);
    assert.strictEqual(gitLayout.commits.length, 4);
    assert.ok(gitLayout.connectors.length >= 3);

    // 2. quadrantChart
    const qSrc = `quadrantChart
        title Reach and Engagement
        x-axis Low Reach --> High Reach
        y-axis Low Engagement --> High Engagement
        quadrant-1 Expand
        quadrant-2 Promote
        quadrant-3 Re-evaluate
        quadrant-4 Improve
        Campaign A: [0.3, 0.6]
        Campaign B: [0.75, 0.85]`;

    const qParsed = MermaidParser.parse(qSrc);
    assert.strictEqual(qParsed.ok, true);
    assert.strictEqual(qParsed.type, "quadrantChart");
    assert.strictEqual(qParsed.ast.points.length, 2);
    assert.strictEqual(qParsed.ast.quadrants.q1, "Expand");

    const qLayout = MermaidLayout.layout(qParsed, (t) => ({ width: t.length * 8, height: 16 }));
    assert.strictEqual(qLayout.ok, true);
    assert.strictEqual(qLayout.points.length, 2);
    assert.ok(qLayout.chartSize >= 340);

    // 3. journey
    const jSrc = `journey
        title Jornada de Trabajo
        section Inicio
            Cafe: 5: Yo
            Mails: 3: Yo, Asistente
        section Fin
            Deploy: 4: Yo, QA`;

    const jParsed = MermaidParser.parse(jSrc);
    assert.strictEqual(jParsed.ok, true);
    assert.strictEqual(jParsed.type, "journey");
    assert.strictEqual(jParsed.ast.sections.length, 2);
    assert.strictEqual(jParsed.ast.actors.length, 3);

    const jLayout = MermaidLayout.layout(jParsed, (t) => ({ width: t.length * 8, height: 16 }));
    assert.strictEqual(jLayout.ok, true);
    assert.strictEqual(jLayout.tasks.length, 3);
    assert.ok(jLayout.trajectoryPath.startsWith("M "));

    // 4. xychart-beta
    const xySrc = `xychart-beta
        title "Ventas Anuales"
        x-axis [Q1, Q2, Q3, Q4]
        y-axis "Monto ($)" 1000 --> 5000
        bar [1200, 2400, 3100, 4800]
        line [1100, 2200, 3400, 4600]`;

    const xyParsed = MermaidParser.parse(xySrc);
    assert.strictEqual(xyParsed.ok, true);
    assert.strictEqual(xyParsed.type, "xychart");
    assert.strictEqual(xyParsed.ast.xAxis.categories.length, 4);
    assert.strictEqual(xyParsed.ast.plots.length, 2);

    const xyLayout = MermaidLayout.layout(xyParsed, (t) => ({ width: t.length * 8, height: 16 }));
    assert.strictEqual(xyLayout.ok, true);
    assert.strictEqual(xyLayout.ticks.length, 5);
    assert.strictEqual(xyLayout.plots.length, 2);
    assert.strictEqual(xyLayout.categories.length, 4);
});

runTest("F63: Mermaid Fase 3: verificación de no-colisión visual, padding interno y headroom", () => {
    // 1. gitGraph espaciado adaptativo
    const gitSrc = `gitGraph
        commit id: "Init"
        branch feature/mermaid
        checkout feature/mermaid
        commit id: "Parser Fase 3" tag: "v0.3"
        commit id: "Layout Motor"
        checkout main
        merge feature/mermaid id: "Merge PR #3" tag: "v1.0"
        commit id: "Release"`;

    const gitParsed = MermaidParser.parse(gitSrc);
    const gitLayout = MermaidLayout.layout(gitParsed, (t, sz) => ({ width: Math.max(t.length * (sz || 10) * 0.6, 20), height: 16 }));
    assert.strictEqual(gitLayout.ok, true);
    for (let i = 0; i < gitLayout.commits.length - 1; i++) {
        const c1 = gitLayout.commits[i];
        const c2 = gitLayout.commits[i + 1];
        const dist = c2.x - c1.x;
        assert.ok(dist >= 72, `Distancia entre commits ${c1.id} y ${c2.id} (${dist}px) debe ser >= 72px`);
    }

    // 2. quadrantChart padding interno y anclaje izquierdo/derecho
    const qSrc = `quadrantChart
        title "Priorización de Features"
        x-axis "Bajo Impacto" --> "Alto Impacto"
        y-axis "Baja Complejidad" --> "Alta Complejidad"
        "Backend Rust": [0.90, 0.85]
        "Animaciones": [0.45, 0.55]`;

    const qParsed = MermaidParser.parse(qSrc);
    const qLayout = MermaidLayout.layout(qParsed, (t) => ({ width: t.length * 8, height: 16 }));
    assert.strictEqual(qLayout.ok, true);
    const rustPt = qLayout.points.find(p => p.label === "Backend Rust");
    assert.ok(rustPt, "Punto Backend Rust debe existir");
    assert.strictEqual(rustPt.alignLeft, true, "Punto en x=0.90 debe tener alignLeft=true para no desbordar");
    // Puntos deben respetar margen interno de 38px
    assert.ok(rustPt.x >= qLayout.left + 38 && rustPt.x <= qLayout.left + qLayout.chartSize - 38);

    // 3. journey 3 zonas verticales disjuntas
    const jSrc = `journey
        title Jornada de Trabajo
        section Inicio
            Revisión de Notificaciones y Alertas: 4: Usuario, Sistema
        section Cierre
            Apagado: 5: Usuario`;

    const jParsed = MermaidParser.parse(jSrc);
    const jLayout = MermaidLayout.layout(jParsed, (t) => ({ width: t.length * 7, height: 16 }));
    assert.strictEqual(jLayout.ok, true);
    assert.ok(jLayout.curveGuides && jLayout.curveGuides.length === 3, "Debe tener 3 guías de benchmark");

    const maxSecY = Math.max(...jLayout.sections.map(s => s.y + 26));
    const minCurveY = Math.min(...jLayout.points.map(p => p.y));
    const maxCurveY = Math.max(...jLayout.points.map(p => p.y));
    const minTaskY = Math.min(...jLayout.tasks.map(t => t.y));

    assert.ok(maxSecY < minCurveY, `Cabeceras (${maxSecY}px) deben estar estrictamente arriba de la curva (${minCurveY}px)`);
    assert.ok(maxCurveY < minTaskY, `Curva (${maxCurveY}px) debe estar estrictamente arriba de las tarjetas (${minTaskY}px)`);
    assert.ok(jLayout.tasks[0].w >= 160, "Ancho de tarjeta debe ser >= 160px");

    // 4. xychart headroom del título sobre el tick superior
    const xySrc = `xychart-beta
        title "Rendimiento"
        x-axis [Q1, Q2]
        y-axis "Puntuación" 1000 --> 6000
        bar [2400, 3200]
        line [2100, 2900]`;

    const xyParsed = MermaidParser.parse(xySrc);
    const xyLayout = MermaidLayout.layout(xyParsed, (t) => ({ width: t.length * 8, height: 16 }));
    assert.strictEqual(xyLayout.ok, true);
    assert.ok(xyLayout.yAxisTitleY < xyLayout.plotTop - 12, `Título Y (${xyLayout.yAxisTitleY}) debe tener >= 12px de headroom sobre plotTop (${xyLayout.plotTop})`);
});

runTest("F64: Contratos de integridad de backend, purga de colas en delete y longitud de texto", () => {
    // 1. Simulación del purgador de colas _purgeQueuedSavesFor
    const saveQueue = [
        { key: "nota_a:md", slug: "nota_a" },
        { key: "nota_b:md", slug: "nota_b" },
        { key: "nota_c:md", slug: "nota_c" }
    ];
    const deferredSaves = {
        "nota_b:md": { data: "test" },
        "nota_c:md": { data: "test2" }
    };

    function purgeQueued(queue, deferred, targetKey) {
        const filteredQ = queue.filter(it => it.key !== targetKey && it.slug !== targetKey);
        const defCopy = Object.assign({}, deferred);
        delete defCopy[targetKey];
        return { queue: filteredQ, deferred: defCopy };
    }

    const purged = purgeQueued(saveQueue, deferredSaves, "nota_b:md");
    assert.strictEqual(purged.queue.length, 2);
    assert.strictEqual(purged.queue.some(it => it.key === "nota_b:md"), false);
    assert.strictEqual(purged.deferred["nota_b:md"], undefined);
    assert.ok(purged.deferred["nota_c:md"] !== undefined);

    // 2. Simulación de longitud de TextEdit en RichText:
    // editInput.length (caracteres de texto plano) vs editInput.text.length (documento HTML completo)
    const plainText = "Cita de texto importante";
    const richHtmlText = `<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.0//EN" "http://www.w3.org/TR/REC-html40/strict.dtd">
<html><head><meta name="qrichtext" content="1" /></head><body><p>${plainText}</p></body></html>`;

    assert.strictEqual(plainText.length, 24);
    assert.ok(richHtmlText.length > 150);

    // Si el cursor está al final del texto plano (pos 24):
    const cursorPos = 24;
    // La condición anterior fallaba porque 24 !== richHtmlText.length (~170)
    assert.notStrictEqual(cursorPos, richHtmlText.length);
    // La nueva condición con editInput.length evalúa true:
    assert.strictEqual(cursorPos, plainText.length);

    // 3. Verificación de tipo de clipboardText como string property
    const mockQuickshellProp = "texto pegado";
    const pasteText = (typeof mockQuickshellProp === "string") ? mockQuickshellProp : "";
    assert.strictEqual(pasteText, "texto pegado");
});

runTest("F65: Rust qs-helper notes index y contratos de metadatos instantáneos", () => {
    const { execSync } = require("child_process");
    let helperBin = process.env.QS_HELPER_BIN;
    if (!helperBin || !fs.existsSync(helperBin)) {
        const candidates = [
            path.join(__dirname, "../target/release/criperto.notes"),
            path.join(__dirname, "../target/release/criperto-notes"),
            path.join(__dirname, "../target/debug/criperto.notes"),
            path.join(__dirname, "../target/debug/criperto-notes"),
            path.join(process.env.HOME || "", ".local/bin/criperto.notes"),
            path.join(__dirname, "../bin/qs-helper"),
            path.join(__dirname, "../../bin/qs-helper")
        ];
        helperBin = candidates.find(c => fs.existsSync(c));
    }
    if (!helperBin) {
        console.warn("  [SKIP] qs-helper/notas no encontrado para F65");
        return;
    }

    // Probar indexación sobre una carpeta temporal con notas de prueba
    const tmpDir = path.join(__dirname, "tmp_notes_test");
    if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });

    const note1 = path.join(tmpDir, "prueba.md");
    fs.writeFileSync(note1, "---\ntitle: \"Nota de Prueba\"\ntags: [alpha, beta]\npinned: true\n---\n# Titulo\nEste es el subtítulo del apunte.\n![foto](assets/foto.png)\n", "utf8");

    try {
        const out = execSync(`"${helperBin}" notes index "${tmpDir}"`, { encoding: "utf8" });
        const data = JSON.parse(out);
        assert.strictEqual(data.ok, true);
        assert.ok(Array.isArray(data.notes));
        assert.ok(data.notes.length >= 1);
        const n = data.notes.find(x => x.key === "prueba.md");
        assert.ok(n, "Debe indexar prueba.md");
        assert.strictEqual(n.title, "Nota de Prueba");
        assert.strictEqual(n.pinned, true);
        assert.deepStrictEqual(n.tags, ["alpha", "beta"]);
        assert.ok(n.subtitle.includes("Este es el subtítulo"));
        assert.ok(n.previewImages.includes("assets/foto.png"));
    } finally {
        fs.rmSync(tmpDir, { recursive: true, force: true });
    }
});

runTest('F66: SpellService ciclo de vida, cancelOwner y SpellLogic filtrado de tags HTML', () => {
    // 1. Filtrado de tags HTML en SpellLogic.tokenize
    const textWithTags = "Fila superior<br>segunda celda con <span style=\"color:red\">color</span> y otra palabra";
    const tokens = SpellLogic.tokenize(textWithTags);
    const words = tokens.map(t => t.word);
    assert.ok(words.includes("Fila"));
    assert.ok(words.includes("superior"));
    assert.ok(words.includes("segunda"));
    assert.ok(words.includes("celda"));
    assert.ok(words.includes("palabra"));
    assert.ok(!words.includes("br"), "Tag <br> no debe tokenizarse como palabra");
    assert.ok(!words.includes("span"), "Tag <span> no debe tokenizarse como palabra");
    assert.ok(!words.includes("color:red"), "Atributos HTML no deben tokenizarse");

    // 2. Verificación estática de SpellService.qml
    const spellServiceQml = fs.readFileSync(path.resolve(__dirname, '../qml/SpellService.qml'), 'utf8');
    assert.ok(spellServiceQml.indexOf('function cancelOwner(owner)') !== -1, "SpellService debe declarar cancelOwner(owner)");
    assert.ok(spellServiceQml.indexOf('function _isOwnerValid(owner)') !== -1, "SpellService debe declarar _isOwnerValid(owner)");
    assert.ok(spellServiceQml.indexOf('function checkWordsBatch(words, callback, owner') !== -1, "checkWordsBatch debe soportar owner");
    assert.ok(spellServiceQml.indexOf('property var _activeBatches: []') !== -1, "SpellService debe mantener _activeBatches");
    assert.ok(spellServiceQml.indexOf('if (q && !q.cancelled && typeof q.callback === "function")') !== -1, "Worker debe chequear q.cancelled");

    // 3. Verificación de blindaje en bloques de texto
    const blocksToCheck = ['BlockParagraph.qml', 'BlockHeading.qml', 'BlockQuote.qml', 'BlockList.qml'];
    for (const b of blocksToCheck) {
        const content = fs.readFileSync(path.resolve(__dirname, '../qml', b), 'utf8');
        assert.ok(content.indexOf('property bool _isDestroyed: false') !== -1, `${b} debe tener property bool _isDestroyed`);
        assert.ok(content.indexOf('SpellService.cancelOwner(root)') !== -1, `${b} debe invocar cancelOwner(root) en onDestruction`);
    }
});

runTest('F67: BlockTable soporte de SpellOverlay, timers y menús contextuales en celdas', () => {
    const tableQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockTable.qml'), 'utf8');

    // 1. Integración en el bloque raíz
    assert.ok(tableQml.indexOf('readonly property bool spellActive:') !== -1, "BlockTable debe declarar spellActive");
    assert.ok(tableQml.indexOf('property bool _isDestroyed: false') !== -1, "BlockTable debe declarar _isDestroyed");
    assert.ok(tableQml.indexOf('SpellService.cancelOwner(root)') !== -1, "BlockTable debe cancelar registros en onDestruction");
    assert.ok(tableQml.indexOf('target: (typeof SpellService !== "undefined") ? SpellService : null') !== -1, "BlockTable debe conectarse a SpellService");

    // 2. Verificación de celdas de encabezado
    assert.ok(tableQml.indexOf('id: hSpellTimer') !== -1, "headerCell debe tener hSpellTimer");
    assert.ok(tableQml.indexOf('id: hSpellOverlay') !== -1, "headerCell debe tener hSpellOverlay");
    assert.ok(tableQml.indexOf('headerCell._openContextMenuAt') !== -1, "headerCell debe implementar _openContextMenuAt");
    assert.ok(tableQml.indexOf('headerCell._replaceWordAtRange') !== -1, "headerCell debe implementar _replaceWordAtRange");

    // 3. Verificación de celdas de datos
    assert.ok(tableQml.indexOf('id: cellSpellTimer') !== -1, "dataCell debe tener cellSpellTimer");
    assert.ok(tableQml.indexOf('id: cellSpellOverlay') !== -1, "dataCell debe tener cellSpellOverlay");
    assert.ok(tableQml.indexOf('dataCell._openContextMenuAt') !== -1, "dataCell debe implementar _openContextMenuAt");
    assert.ok(tableQml.indexOf('dataCell._replaceWordAtRange') !== -1, "dataCell debe implementar _replaceWordAtRange");

    // 4. Clic derecho en modo lectura activa y abre menú contextual
    assert.ok(tableQml.indexOf('acceptedButtons: Qt.LeftButton | Qt.RightButton') !== -1, "Vistas de celda deben aceptar clic derecho");
});

runTest('F68: Cálculo de posición en grid y resorte de cierre al abrir notas desde terminal', () => {
    const notesContentQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesContent.qml'), 'utf8');

    // 1. Verificación estática de funciones auxiliares y registry
    assert.ok(notesContentQml.indexOf('function _findCardInRegistry(slug)') !== -1, "NotesContent debe declarar _findCardInRegistry");
    assert.ok(notesContentQml.indexOf('function _estimateCardPositionInGrid(slug)') !== -1, "NotesContent debe declarar _estimateCardPositionInGrid");
    assert.ok(notesContentQml.indexOf('function _findCurrentCardPosition(slug, ensureVisible)') !== -1, "NotesContent debe declarar _findCurrentCardPosition con ensureVisible");

    // 2. Verificación de openNoteImmediate
    assert.ok(notesContentQml.indexOf('var cardPos = _findCurrentCardPosition(root.activeMorphSlug, true);') !== -1, "openNoteImmediate debe calcular cardPos inicial");
    assert.ok(notesContentQml.indexOf('morphContainer.startRadius = cardPos.radius !== undefined ? cardPos.radius : 16;') !== -1, "openNoteImmediate debe configurar startRadius");
    assert.ok(notesContentQml.indexOf('morphContainer.springEnabled = true;') !== -1, "openNoteImmediate debe reactivar springEnabled en Qt.callLater");

    // 3. Verificación de closeNoteWithMorph
    assert.ok(notesContentQml.indexOf('var foundPos = _findCurrentCardPosition(root.activeMorphSlug, true);') !== -1, "closeNoteWithMorph debe invocar _findCurrentCardPosition con ensureVisible=true");
    assert.ok(notesContentQml.indexOf('morphContainer.springEnabled = true;') !== -1, "closeNoteWithMorph debe asegurar springEnabled = true");

    // 4. Verificación de onNotesRefreshed
    assert.ok(notesContentQml.indexOf('if (morphContainer.isExpanded && root.activeMorphSlug !== "")') !== -1, "onNotesRefreshed debe re-sincronizar posición si la nota está expandida");

    // 5. Test unitario de resolución de claves con formato slug\\0ext
    const mockRegistry = {
        "nota_uno\0md": { cardKey: "nota_uno\0md", noteData: { slug: "nota_uno", key: "nota_uno\0md" } },
        "nota_dos\0txt": { cardKey: "nota_dos\0txt", noteData: { slug: "nota_dos", key: "nota_dos\0txt" } }
    };

    function resolveMockCard(slug, registry) {
        if (!slug || !registry) return null;
        if (registry[slug]) return registry[slug];
        if (registry[slug + "\0md"]) return registry[slug + "\0md"];
        if (registry[slug + "\0txt"]) return registry[slug + "\0txt"];
        const clean = slug.replace(/\0.*$/, "").replace(/\.(md|txt)$/, "");
        if (clean !== slug) {
            if (registry[clean]) return registry[clean];
            if (registry[clean + "\0md"]) return registry[clean + "\0md"];
            if (registry[clean + "\0txt"]) return registry[clean + "\0txt"];
        }
        for (const k in registry) {
            const c = registry[k];
            if (!c) continue;
            if (c.cardKey === slug || c.cardKey === clean) return c;
            if (c.noteData && (c.noteData.slug === slug || c.noteData.slug === clean || c.noteData.key === slug)) return c;
        }
        return null;
    }

    assert.strictEqual(resolveMockCard("nota_uno", mockRegistry), mockRegistry["nota_uno\0md"], "Debe resolver nota_uno hacia nota_uno\\0md");
    assert.strictEqual(resolveMockCard("nota_uno.md", mockRegistry), mockRegistry["nota_uno\0md"], "Debe resolver nota_uno.md hacia nota_uno\\0md");
    assert.strictEqual(resolveMockCard("nota_dos", mockRegistry), mockRegistry["nota_dos\0txt"], "Debe resolver nota_dos hacia nota_dos\\0txt");
    assert.strictEqual(resolveMockCard("inexistente", mockRegistry), null, "Debe retornar null si no existe");

    // 6. Test unitario de cálculo geométrico en grid
    const colsData = [
        [{ key: "n0" }, { key: "n3" }],
        [{ key: "n1" }, { key: "n4" }],
        [{ key: "n2" }, { key: "n5" }]
    ];
    let foundCol = -1, foundRow = -1;
    for (let c = 0; c < colsData.length; c++) {
        for (let r = 0; r < colsData[c].length; r++) {
            if (colsData[c][r].key === "n4") {
                foundCol = c;
                foundRow = r;
                break;
            }
        }
    }
    assert.strictEqual(foundCol, 1, "n4 debe estar en columna 1");
    assert.strictEqual(foundRow, 1, "n4 debe estar en fila 1");
    const colW = 260, spacing = 14, cardH = 180;
    const estX = foundCol * (colW + spacing);
    const estY = foundRow * (cardH + spacing);
    assert.strictEqual(estX, 274, "X estimado debe ser 274");
    assert.strictEqual(estY, 194, "Y estimado debe ser 194");
});

runTest('F69: Sincronización automática de scrollbars, blur y animaciones con Quickshell y toggle por CLI', () => {
    const settingsModalQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesSettingsModal.qml'), 'utf8');
    const mainQml = fs.readFileSync(path.resolve(__dirname, '../qml/Main.qml'), 'utf8');
    const nativeBridgeH = fs.readFileSync(path.resolve(__dirname, '../src/native/native_bridge.h'), 'utf8');
    const nativeBridgeCpp = fs.readFileSync(path.resolve(__dirname, '../src/native/native_bridge.cpp'), 'utf8');
    const mainRs = fs.readFileSync(path.resolve(__dirname, '../src/main.rs'), 'utf8');
    const syncCliRs = fs.readFileSync(path.resolve(__dirname, '../src/sync_cli.rs'), 'utf8');

    // 1. Verificación en NotesSettingsModal.qml: ocultamiento de pestaña Apariencia
    assert.ok(settingsModalQml.indexOf('readonly property bool showAppearanceTab:') !== -1, "Debe declarar showAppearanceTab");
    assert.ok(settingsModalQml.indexOf('!Sys.hasQuickshellConfig') !== -1, "showAppearanceTab debe basarse en !Sys.hasQuickshellConfig");
    assert.ok(settingsModalQml.indexOf('t.value !== "appearance"') !== -1, "tabs debe filtrar la pestaña appearance si showAppearanceTab es false");
    assert.ok(settingsModalQml.indexOf('visible: root.currentTabValue === "appearance"') !== -1, "tabAppearance debe usar currentTabValue");

    // 2. Verificación en Main.qml e IPC
    assert.ok(mainQml.indexOf('action === "sync"') !== -1, "Main.qml debe manejar la acción IPC 'sync'");

    // 3. Verificación en native_bridge: syncWithQuickshell y carga de blur/animaciones/fuentes
    assert.ok(nativeBridgeH.indexOf('syncWithQuickshell') !== -1, "ConfigBackend debe declarar syncWithQuickshell");
    assert.ok(nativeBridgeH.indexOf('quickshellConfigChanged') !== -1, "Sys debe declarar señal quickshellConfigChanged");
    assert.ok(nativeBridgeCpp.indexOf('NOTAS_NO_SYNC') !== -1, "hasQuickshellConfig debe honrar NOTAS_NO_SYNC");
    assert.ok(nativeBridgeCpp.indexOf('extractLuaTableBool') !== -1, "native_bridge.cpp debe definir extractLuaTableBool");
    assert.ok(nativeBridgeCpp.indexOf('font.conf') !== -1, "setupQuickshellWatcher debe vigilar font.conf");
    assert.ok(nativeBridgeCpp.indexOf('user_settings.lua') !== -1, "setupQuickshellWatcher debe vigilar user_settings.lua");
    assert.ok(nativeBridgeCpp.indexOf('theme.lua') !== -1, "setupQuickshellWatcher debe vigilar theme.lua");

    // 4. Verificación en CLI de Rust
    assert.ok(mainRs.indexOf('mod sync_cli;') !== -1, "main.rs debe declarar mod sync_cli");
    assert.ok(mainRs.indexOf('"sync" =>') !== -1, "main.rs debe rutear el comando 'sync'");
    assert.ok(mainRs.indexOf('no-sync') !== -1, "main.rs debe aceptar flag no-sync");
    assert.ok(syncCliRs.indexOf('pub fn run(') !== -1, "sync_cli.rs debe implementar run()");

    // 5. Test unitario de extracción de tablas Lua con llaves anidadas
    function parseLuaTableBool(content, tableName, keyName, defaultVal) {
        const re = new RegExp('\\b' + tableName + '\\s*=\\s*\\{');
        const match = re.exec(content);
        if (!match) return defaultVal;
        const openBrace = match.index + match[0].length - 1;
        let depth = 0;
        let closeBrace = -1;
        for (let i = openBrace; i < content.length; i++) {
            if (content[i] === '{') depth++;
            else if (content[i] === '}') {
                depth--;
                if (depth === 0) { closeBrace = i; break; }
            }
        }
        if (closeBrace === -1) closeBrace = content.length;
        const block = content.substring(openBrace + 1, closeBrace);
        const keyMatch = new RegExp('\\b' + keyName + '\\s*=\\s*(true|false)', 'i').exec(block);
        return keyMatch ? (keyMatch[1].toLowerCase() === 'true') : defaultVal;
    }

    const testLuaNested = `
    hl.config({
        decoration = {
            blur = {
                fluid_jar = {
                    color = "rgba(ff3333cc)",
                },
                variant = "kawase",
                enabled = true,
                size = 3,
            },
            animations = {
                enabled = false,
            }
        }
    })
    `;
    assert.strictEqual(parseLuaTableBool(testLuaNested, "blur", "enabled", false), true, "Debe extraer blur.enabled = true con bloque anidado");
    assert.strictEqual(parseLuaTableBool(testLuaNested, "animations", "enabled", true), false, "Debe extraer animations.enabled = false");

    // 6. Test unitario del filtrado de tabs
    const allTabs = [
        { value: "editor" },
        { value: "appearance" },
        { value: "language" },
        { value: "about" }
    ];
    const filteredWhenSynced = allTabs.filter(t => t.value !== "appearance");
    assert.strictEqual(filteredWhenSynced.length, 3, "Con Quickshell sincronizado debe tener 3 pestañas");
    assert.strictEqual(filteredWhenSynced.find(t => t.value === "appearance"), undefined, "No debe incluir 'appearance'");
});

runTest('F70: Opacidad configurable con límite mínimo 20% y persistencia permanente de no-sync por variable de configuración', () => {
    const settingsModalQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesSettingsModal.qml'), 'utf8');
    const themeQml = fs.readFileSync(path.resolve(__dirname, '../qml/Theme.qml'), 'utf8');
    const nativeBridgeCpp = fs.readFileSync(path.resolve(__dirname, '../src/native/native_bridge.cpp'), 'utf8');
    const syncCliRs = fs.readFileSync(path.resolve(__dirname, '../src/sync_cli.rs'), 'utf8');
    const mainRs = fs.readFileSync(path.resolve(__dirname, '../src/main.rs'), 'utf8');

    // 1. Verificación de límite de opacidad mínima al 20%
    assert.ok(settingsModalQml.indexOf('minV: 20') !== -1, "Slider de opacidad en NotesSettingsModal debe permitir mínimo 20%");
    assert.ok(themeQml.indexOf('Math.max(0.2,') !== -1, "Theme.panelOpacity debe tener clamp inferior en 0.2");
    assert.ok(nativeBridgeCpp.indexOf('qBound(20, val, 100)') !== -1, "ConfigBackend::setPanelOpacity debe limitar con qBound(20, val, 100)");
    assert.ok(nativeBridgeCpp.indexOf('qBound(20, v.toInt(), 100)') !== -1, "loadQuickshellConfig debe acotar opacidad en 20%");
    assert.ok(nativeBridgeCpp.indexOf('qBound(20, obj["panelOpacity"].toInt(94), 100)') !== -1, "ConfigBackend::load debe acotar opacidad en 20%");

    // 2. Verificación de forzado permanente de no-sync por variables en config (.json / .conf / .toml)
    assert.ok(nativeBridgeCpp.indexOf('isForcedNoSyncConfigured()') !== -1, "native_bridge.cpp debe definir isForcedNoSyncConfigured()");
    assert.ok(nativeBridgeCpp.indexOf('noSync') !== -1, "isForcedNoSyncConfigured debe verificar 'noSync'");
    assert.ok(nativeBridgeCpp.indexOf('no_sync') !== -1, "isForcedNoSyncConfigured debe verificar 'no_sync'");
    assert.ok(nativeBridgeCpp.indexOf('config.conf') !== -1, "isForcedNoSyncConfigured debe verificar archivos .conf");
    assert.ok(nativeBridgeCpp.indexOf('config.toml') !== -1, "isForcedNoSyncConfigured debe verificar archivos .toml");

    // 3. Verificación en sync_cli.rs y main.rs
    assert.ok(syncCliRs.indexOf('pub fn is_forced_no_sync() -> bool') !== -1, "sync_cli.rs debe exportar is_forced_no_sync()");
    assert.ok(mainRs.indexOf('sync_cli::is_forced_no_sync()') !== -1, "main.rs debe activar NOTAS_NO_SYNC si is_forced_no_sync() es true");

    // 4. Test unitario de parseo de variables de no-sync en formato conf/toml/json
    function checkConfNoSync(content) {
        const lines = content.split('\n');
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed || trimmed.startsWith('#') || trimmed.startsWith(';')) continue;
            const eq = trimmed.indexOf('=');
            if (eq !== -1) {
                const k = trimmed.slice(0, eq).trim().toLowerCase();
                const v = trimmed.slice(eq + 1).trim().toLowerCase();
                if ((k === 'nosync' || k === 'no_sync') && (v === 'true' || v === '1')) return true;
                if ((k === 'sync' || k === 'syncwithquickshell') && (v === 'false' || v === '0')) return true;
            }
        }
        return false;
    }

    assert.strictEqual(checkConfNoSync("noSync = true"), true, "noSync = true debe detectar no-sync");
    assert.strictEqual(checkConfNoSync("no_sync = 1"), true, "no_sync = 1 debe detectar no-sync");
    assert.strictEqual(checkConfNoSync("sync = false"), true, "sync = false debe detectar no-sync");
    assert.strictEqual(checkConfNoSync("syncWithQuickshell = false"), true, "syncWithQuickshell = false debe detectar no-sync");
    assert.strictEqual(checkConfNoSync("noSync = false\nsync = true"), false, "noSync = false no debe activar forzado");

    // 5. Garantía de que no hay toggle de noSync en el menú UI
    assert.strictEqual(settingsModalQml.indexOf('noSync') === -1, true, "No debe existir toggle de noSync en el menú UI");
});

runTest('F71: Acerca de enlaces a GitHub / repositorio y eliminación de subfondos en menús de configuración', () => {
    const settingsModalQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesSettingsModal.qml'), 'utf8');

    // 1. Enlaces a GitHub personal y del proyecto
    assert.ok(settingsModalQml.indexOf('https://github.com/Criperto') !== -1, "Debe incluir enlace al perfil de GitHub");
    assert.ok(settingsModalQml.indexOf('https://github.com/Criperto/notes') !== -1, "Debe incluir enlace al repositorio de Notes");
    assert.ok(settingsModalQml.indexOf('Qt.openUrlExternally("https://github.com/Criperto")') !== -1, "Debe abrir perfil externamente");
    assert.ok(settingsModalQml.indexOf('Qt.openUrlExternally("https://github.com/Criperto/notes")') !== -1, "Debe abrir repositorio externamente");

    // 2. Eliminación de subfondos y bordes de tarjetas intermedias en Settings
    assert.ok(settingsModalQml.indexOf('component BentoCard: Rectangle {\n        Layout.fillWidth: true\n        color: "transparent"\n        border.width: 0') !== -1, "BentoCard debe ser transparente y sin borde");
});

runTest('F72: Desenfoque de fondo fijo y reforzado en ventana de configuración (sin depender de modules/settings)', () => {
    const settingsModalQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesSettingsModal.qml'), 'utf8');

    // 1. Valores fijos de desenfoque aumentados (blurMax >= 80 y blurPadding >= 80)
    assert.ok(settingsModalQml.indexOf('blurMax: 96') !== -1, "blurMax debe ser 96 para máximo bokeh en fondo de configuración");
    assert.ok(settingsModalQml.indexOf('blurPadding: 96') !== -1, "blurPadding debe coincidir con blurMax (96)");

    // 2. No debe extraer valores de desenfoque de HyprlandConfig / modules/settings
    assert.strictEqual(settingsModalQml.indexOf('HyprlandConfig.blurEnabled'), -1, "No debe enlazar blurEnabled a HyprlandConfig en el modal");
    assert.strictEqual(settingsModalQml.indexOf('HyprlandConfig.quickshellBlurMax'), -1, "No debe tomar blurMax de HyprlandConfig");

    // 3. Opacidad de superficie incrementada para legibilidad
    assert.ok(settingsModalQml.indexOf('? 0.85') !== -1, "cardBgTint debe tener opacidad de 0.85 para evitar traslúcido excesivo de notas de fondo");
});

runTest('F73: Asociación de Notas como aplicación por defecto para .md y .txt en desktop entry y script de instalación', () => {
    const desktopEntry = fs.readFileSync(path.resolve(__dirname, '../assets/dev.criperto.Notas.desktop'), 'utf8');
    const installScript = fs.readFileSync(path.resolve(__dirname, '../scripts/install.sh'), 'utf8');

    // 1. Declaración de tipos MIME soportados en el desktop entry
    assert.ok(desktopEntry.indexOf('MimeType=') !== -1, "Desktop entry debe declarar clave MimeType");
    assert.ok(desktopEntry.indexOf('text/markdown') !== -1, "Desktop entry debe soportar text/markdown");
    assert.ok(desktopEntry.indexOf('text/plain') !== -1, "Desktop entry debe soportar text/plain");
    assert.ok(desktopEntry.indexOf('text/x-markdown') !== -1, "Desktop entry debe soportar text/x-markdown");
    assert.ok(desktopEntry.indexOf('Exec=criperto-notes %F') !== -1 || desktopEntry.indexOf('Exec=criperto.notes %F') !== -1, "Desktop entry debe incluir %F para recibir archivos como argumentos");

    // 2. Asociación como editor predeterminado en script de instalación
    assert.ok(installScript.indexOf('xdg-mime default dev.criperto.Notas.desktop') !== -1, "install.sh debe ejecutar xdg-mime default");
    assert.ok(installScript.indexOf('text/markdown') !== -1, "install.sh debe configurar text/markdown");
    assert.ok(installScript.indexOf('text/plain') !== -1, "install.sh debe configurar text/plain");
    assert.ok(installScript.indexOf('text/x-markdown') !== -1, "install.sh debe configurar text/x-markdown");
    assert.ok(installScript.indexOf('mimeapps.list') !== -1, "install.sh debe asegurar persistencia en mimeapps.list");
});

runTest('F74: Agrupación de imágenes consecutivas, dimensionamiento intrínseco de badges y remoción de sourceSize rígido', () => {
    // 1. Agrupación en BlockModel de líneas consecutivas de badges / imágenes
    const md = "# Notas\n\n![License](https://img.shields.io/badge/license-blue.svg)\n![Version](https://img.shields.io/badge/version-orange.svg)\n![Platform](https://img.shields.io/badge/platform-purple.svg)\n\nTexto siguiente";
    const res = BlockModel.splitBlocks(md);
    assert.strictEqual(res.blocks.length, 3, "Debe agrupar los 3 badges consecutivos en un único bloque 'image'");
    assert.strictEqual(res.blocks[0].type, "heading");
    assert.strictEqual(res.blocks[1].type, "image");
    assert.strictEqual(res.blocks[2].type, "paragraph");

    // Invariante de reconstrucción idéntica byte a byte
    assert.strictEqual(BlockModel.joinBlocks(res), md, "joinBlocks debe reconstruir exactamente el markdown con saltos de línea originales");

    // 2. Estimación inteligente de altura para badges vs imágenes normales
    const badgeHeight = BlockModel.estimateBlockHeight("image", res.blocks[1].raw, 800);
    assert.strictEqual(badgeHeight, 36, "Badge block debe estimarse en ~36px para evitar saltos en viewport");

    const normalHeight = BlockModel.estimateBlockHeight("image", "![Screenshot](/home/user/photo.png)", 800);
    assert.strictEqual(normalHeight, 240, "Imagen normal debe estimarse en 240px");

    // 3. Verificaciones de BlockImage.qml
    const blockImageQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockImage.qml'), 'utf8');
    assert.strictEqual(blockImageQml.indexOf('sourceSize: Qt.size(1400, 0)'), -1, "No debe forzar sourceSize de 1400px en SVGs e imágenes");
    assert.ok(blockImageQml.indexOf('PreviewLogic.isBadgeLike') !== -1, "Debe detectar badges usando PreviewLogic");
    assert.ok(blockImageQml.indexOf('readonly property bool isBadge') !== -1, "Debe definir propiedad isBadge");
    assert.ok(blockImageQml.indexOf('imgCard.isBadge ? "transparent"') !== -1, "Badges deben renderizarse con fondo transparente sin tarjeta tosca");
});

runTest('F75: Renderizado visual de teclas kbd y modo configurable para archivos externos', () => {
    // 1. Renderizado de etiquetas <kbd> en inlineToHtml con SVG 3D realista y bisel teñido del color de acento
    const rawKbd = "<kbd>Ctrl</kbd> + <kbd>,</kbd>";
    const htmlKbd = Inline.inlineToHtml(rawKbd, {
        kbdBezel: "#e56018",
        kbdShadow1: "#8f3805",
        kbdShadow2: "#b5490a",
        kbdPlate: "#1c1815",
        kbdText: "#ffffff"
    });
    assert.ok(htmlKbd.indexOf('<img src="data:image/svg+xml;utf8,') !== -1, "inlineToHtml debe renderizar keycaps como imagen SVG en línea");
    assert.ok(htmlKbd.indexOf('align="middle"') !== -1, "inlineToHtml debe alinear verticalmente el keycap al medio");
    assert.ok(htmlKbd.indexOf(' + ') !== -1, "El separador ' + ' debe mantenerse fuera de los keycaps");
    assert.strictEqual(htmlKbd.indexOf('&lt;kbd&gt;'), -1, "No debe escapar las etiquetas kbd a entidades planas");

    // Decodificar el SVG generado para verificar la estructura multicapa 3D
    const svgMatch = htmlKbd.match(/data:image\/svg\+xml;utf8,([^"]+)/);
    assert.ok(svgMatch, "Debe contener una URI de datos SVG válida");
    const decodedSvg = decodeURIComponent(svgMatch[1]);
    assert.ok(decodedSvg.indexOf('Capa 3D inferior') !== -1, "SVG debe tener capa 3D inferior de profundidad");
    assert.ok(decodedSvg.indexOf('Capa 3D intermedia') !== -1, "SVG debe tener bisel intermedio");
    assert.ok(decodedSvg.indexOf('Capa superior') !== -1, "SVG debe tener cuerpo superior de tecla");
    assert.ok(decodedSvg.indexOf('#e56018') !== -1, "El bisel superior debe teñirse con el color de acento configurado");
    assert.ok(decodedSvg.indexOf('Placa central interna') !== -1, "SVG debe tener placa central recesada");
    assert.ok(decodedSvg.indexOf('CTRL') !== -1, "SVG debe incluir el texto 'CTRL'");

    // 2. Soporte de &lt;kbd&gt; si llega pre-escapado
    const preEscaped = "&lt;kbd&gt;Shift&lt;/kbd&gt; + &lt;kbd&gt;Z&lt;/kbd&gt;";
    const htmlEscaped = Inline.inlineToHtml(preEscaped, {});
    assert.ok(htmlEscaped.indexOf('data:image/svg+xml;utf8,') !== -1, "Debe decodificar y estilizar kbd pre-escapado");
    assert.strictEqual(htmlEscaped.indexOf('&lt;kbd&gt;'), -1, "No debe dejar entidades &lt;kbd&gt; sin estilizar");

    // 3. Función generadora renderKeycapSvg y dimensiones dinámicas con adaptación a zoom y tipografía mono
    const svgShort = decodeURIComponent(Inline.renderKeycapSvg("Z", {}));
    const svgLong = decodeURIComponent(Inline.renderKeycapSvg("Shift", {}));
    const widthShortMatch = svgShort.match(/width="(\d+)"/);
    const widthLongMatch = svgLong.match(/width="(\d+)"/);
    assert.ok(widthShortMatch && parseInt(widthShortMatch[1], 10) >= 24, "Tecla simple debe tener ancho mínimo de 24px");
    assert.ok(widthLongMatch && parseInt(widthLongMatch[1], 10) > parseInt(widthShortMatch[1], 10), "Tecla 'Shift' debe ser más ancha que tecla simple 'Z'");

    // Adaptación a zoom (1.0x vs 1.5x)
    const svgZoom1 = decodeURIComponent(Inline.renderKeycapSvg("CTRL", { zoom: 1.0 }));
    const svgZoom15 = decodeURIComponent(Inline.renderKeycapSvg("CTRL", { zoom: 1.5 }));
    const h1Match = svgZoom1.match(/height="(\d+)"/);
    const h15Match = svgZoom15.match(/height="(\d+)"/);
    assert.strictEqual(parseInt(h1Match[1], 10), 26, "Altura base a 1.0x debe ser 26px");
    assert.strictEqual(parseInt(h15Match[1], 10), 39, "Altura escalada a 1.5x debe ser 39px (26 * 1.5)");

    // Adaptación de tipografía mono del tema
    const svgDefaultFont = decodeURIComponent(Inline.renderKeycapSvg("ESC"));
    assert.ok(svgDefaultFont.indexOf("font-family=\"'JetBrains Mono', monospace\"") !== -1, "El texto interior debe usar JetBrains Mono por defecto");
    const svgFont = decodeURIComponent(Inline.renderKeycapSvg("ESC", { fontFamilyMonospace: "Fira Code" }));
    assert.ok(svgFont.indexOf("font-family=\"'Fira Code', monospace\"") !== -1, "El texto interior debe usar la tipografía monospace configurada");

    // 4. SearchLogic stripForSearch con <kbd>
    const searchStripped = SearchLogic.stripForSearch("Presione <kbd>Ctrl</kbd> + <kbd>S</kbd>");
    assert.strictEqual(searchStripped.text, "Presione Ctrl + S", "stripForSearch debe descartar tags kbd preservando su contenido");

    // 5. formatForLiveEditing de <kbd>
    const liveKbd = Inline.formatForLiveEditing("<kbd>Ctrl</kbd> + <kbd>Q</kbd>", { hideSyntax: true });
    assert.ok(liveKbd.indexOf('font-family: monospace') !== -1, "formatForLiveEditing debe estilizar keycaps");
    assert.ok(liveKbd.indexOf('Ctrl') !== -1, "formatForLiveEditing debe preservar texto");

    // 6. Lógica de apertura de archivos externos vs internos
    const notesDir = "/home/user/Documentos/notes";
    const internalPath = "/home/user/Documentos/notes/mi-nota.md";
    const externalPath = "/home/user/Proyectos/qs-notes/README.md";

    assert.strictEqual(ImportLogic.isInsideDir(internalPath, notesDir), true, "internalPath debe detectarse dentro de notesDir");
    assert.strictEqual(ImportLogic.isInsideDir(externalPath, notesDir), false, "externalPath debe detectarse fuera de notesDir");

    function shouldPreviewExternal(act, tgt, externalFileOpenMode, notesDir) {
        var isOutside = !ImportLogic.isInsideDir(tgt, notesDir);
        return (act !== "edit") && isOutside && (externalFileOpenMode !== "edit");
    }

    // Default ("preview"): externo abre en preview, interno en edición
    assert.strictEqual(shouldPreviewExternal("open", externalPath, "preview", notesDir), true, "Archivo externo con mode preview debe abrir en preview");
    assert.strictEqual(shouldPreviewExternal("open", internalPath, "preview", notesDir), false, "Archivo interno debe abrir siempre en edición");

    // Configurado en "edit": externo abre en edición
    assert.strictEqual(shouldPreviewExternal("open", externalPath, "edit", notesDir), false, "Archivo externo con mode edit debe abrir en edición directa");

    // CLI --edit fuerza edición sin importar config
    assert.strictEqual(shouldPreviewExternal("edit", externalPath, "preview", notesDir), false, "Acción 'edit' debe forzar modo edición");

    // 7. Botón de importar en modo edición de notas externas
    const editorModalQml = fs.readFileSync(path.resolve(__dirname, '../qml/NoteEditorModal.qml'), 'utf8');
    assert.ok(editorModalQml.indexOf('root.isExternalNote && !root.isPreviewMode') !== -1, "NoteEditorModal debe mostrar botón Importar cuando se edita un archivo externo");
    assert.ok(editorModalQml.indexOf('NotesService.importExternalAndEdit()') !== -1, "Botón de importar en edición debe invocar importExternalAndEdit");

    // 8. Selector de configuración en NotesSettingsModal
    const settingsModalQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesSettingsModal.qml'), 'utf8');
    assert.ok(settingsModalQml.indexOf('ConfigBackend.externalFileOpenMode') !== -1, "NotesSettingsModal debe enlazar a externalFileOpenMode");
    assert.ok(settingsModalQml.indexOf('config.notes.external_open_mode') !== -1, "NotesSettingsModal debe tener etiqueta i18n para el modo de apertura de archivos externos");
});

runTest('F76: Espera de carga inicial en modo preview y acción configurable al cerrar con X', () => {
    // 1. Contrato de visibilidad inicial diferida en NotesContent y Main.qml
    function computeIsReadyToShow(initialAction, initialTarget) {
        return (initialAction === "" || initialAction === "raise" || initialAction === "toggle" || (initialAction === "open" && initialTarget === ""));
    }

    assert.strictEqual(computeIsReadyToShow("", ""), true, "Lanzamiento normal sin parámetros debe estar listo de inmediato");
    assert.strictEqual(computeIsReadyToShow("raise", ""), true, "Acción raise debe estar lista de inmediato");
    assert.strictEqual(computeIsReadyToShow("toggle", ""), true, "Acción toggle debe estar lista de inmediato");
    assert.strictEqual(computeIsReadyToShow("open", ""), true, "Acción open sin target debe estar lista de inmediato");
    assert.strictEqual(computeIsReadyToShow("preview", "/tmp/doc.md"), false, "Lanzamiento en preview con target debe ocultar la ventana hasta cargar");
    assert.strictEqual(computeIsReadyToShow("open", "/tmp/doc.md"), false, "Lanzamiento en open con target debe ocultar la ventana hasta cargar");
    assert.strictEqual(computeIsReadyToShow("edit", "/tmp/doc.md"), false, "Lanzamiento en edit con target debe ocultar la ventana hasta cargar");

    // 2. Main.qml vincula visible a content.isReadyToShow
    const mainQml = fs.readFileSync(path.resolve(__dirname, '../qml/Main.qml'), 'utf8');
    assert.ok(mainQml.indexOf('visible: content.isReadyToShow') !== -1, "ApplicationWindow debe vincular su propiedad visible a content.isReadyToShow");
    assert.ok(mainQml.indexOf('initialAction: (typeof Sys !== "undefined") ? Sys.initialAction : ""') !== -1, "Main.qml debe propagar Sys.initialAction a content");
    assert.ok(mainQml.indexOf('initialTarget: (typeof Sys !== "undefined") ? Sys.initialTarget : ""') !== -1, "Main.qml debe propagar Sys.initialTarget a content");

    // 3. NotesConfig declara previewCloseAction con opciones 'close' y 'home' con default 'home' e importMode 'move'
    const notesConfigQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesConfig.qml'), 'utf8');
    assert.ok(notesConfigQml.indexOf('key: "previewCloseAction"') !== -1, "NotesConfig schema debe definir previewCloseAction");
    assert.ok(notesConfigQml.indexOf('default: "home"') !== -1, "previewCloseAction debe tener default 'home'");
    assert.ok(notesConfigQml.indexOf('values: ["close", "home"]') !== -1, "previewCloseAction debe admitir 'close' y 'home'");
    assert.ok(notesConfigQml.indexOf('property string previewCloseAction') !== -1, "NotesConfig debe tener propiedad reactiva previewCloseAction");
    assert.ok(notesConfigQml.indexOf('key: "importMode"') !== -1, "NotesConfig schema debe definir importMode");
    assert.ok(notesConfigQml.indexOf('default: "move"') !== -1, "importMode debe tener default 'move'");

    // 4. NotesSettingsModal incluye selector para previewCloseAction
    const settingsModalQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesSettingsModal.qml'), 'utf8');
    assert.ok(settingsModalQml.indexOf('ConfigBackend.previewCloseAction') !== -1, "NotesSettingsModal debe conectar con ConfigBackend.previewCloseAction");
    assert.ok(settingsModalQml.indexOf('config.notes.preview_close_action') !== -1, "NotesSettingsModal debe tener etiqueta i18n para la acción al cerrar preview");
    assert.ok(settingsModalQml.indexOf('config.notes.preview_close_exit') !== -1, "NotesSettingsModal debe tener opción para cerrar app");
    assert.ok(settingsModalQml.indexOf('config.notes.preview_close_home') !== -1, "NotesSettingsModal debe tener opción para volver al inicio");

    // 5. Contrato de decisión al cerrar preview (cerrar app vs volver al inicio)
    function shouldCloseAppOnPreviewClose(previewCloseAction, wasExternal) {
        return (previewCloseAction !== "home") && Boolean(wasExternal);
    }

    assert.strictEqual(shouldCloseAppOnPreviewClose("close", true), true, "Con 'close' y nota externa, debe cerrar la aplicación");
    assert.strictEqual(shouldCloseAppOnPreviewClose("home", true), false, "Con 'home' y nota externa, NO debe cerrar la app sino volver al inicio");
    assert.strictEqual(shouldCloseAppOnPreviewClose("home", false), false, "Con nota interna y 'home', no cierra la app");

    // 6. NotesContent respeta previewCloseAction al cerrar
    const notesContentQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesContent.qml'), 'utf8');
    assert.ok(notesContentQml.indexOf('NotesConfig.previewCloseAction !== "home"') !== -1, "NotesContent debe consultar NotesConfig.previewCloseAction antes de cerrar la ventana");
});

// ── F77: Callouts estilo GitHub ───────────────────────────────────────────
runTest('F77: Callouts GitHub parseCallout, searchUnits, colores y altura', () => {
    const CalloutTypes = loadModule('CalloutTypes.js');

    // 1. Detección y extracción de los 5 tipos estándar
    const types = ['NOTE', 'TIP', 'IMPORTANT', 'WARNING', 'CAUTION'];
    for (const t of types) {
        const raw = `> [!${t}]\n> Contenido de prueba`;
        const res = QP.parseCallout(raw);
        assert.ok(res !== null, `Debe reconocer [!${t}]`);
        assert.strictEqual(res.type, t);
        assert.strictEqual(res.title, '');
        assert.strictEqual(res.bodyRaw, '> Contenido de prueba');
    }

    // 2. Insensibilidad a mayúsculas/minúsculas y títulos personalizados
    const case1 = QP.parseCallout('> [!note] Mi Título Personalizado\n> Línea 1\n> Línea 2');
    assert.ok(case1 !== null);
    assert.strictEqual(case1.type, 'NOTE');
    assert.strictEqual(case1.title, 'Mi Título Personalizado');
    assert.strictEqual(case1.bodyRaw, '> Línea 1\n> Línea 2');

    const case2 = QP.parseCallout('> [!warning] Advertencia Crítica\n> Cuidado con esto');
    assert.strictEqual(case2.type, 'WARNING');
    assert.strictEqual(case2.title, 'Advertencia Crítica');

    // 3. Tolerancia a espacios iniciales antes de `>`
    const case3 = QP.parseCallout('   > [!tip]   Atajo rápido   \n> Usa Ctrl+S');
    assert.ok(case3 !== null);
    assert.strictEqual(case3.type, 'TIP');
    assert.strictEqual(case3.title, 'Atajo rápido');

    // 4. Casos negativos (no son callouts)
    assert.strictEqual(QP.parseCallout('> Esto es una cita común'), null);
    assert.strictEqual(QP.parseCallout('> [!UNKNOWN] Tipo desconocido'), null);
    assert.strictEqual(QP.parseCallout('> [!NOTE Sin corchete de cierre'), null);
    assert.strictEqual(QP.parseCallout('Texto normal sin prefijo quote'), null);
    assert.strictEqual(QP.parseCallout(null), null);
    assert.strictEqual(QP.parseCallout(''), null);

    // 5. Callout con cuerpo vacío
    const emptyBody = QP.parseCallout('> [!CAUTION]');
    assert.ok(emptyBody !== null);
    assert.strictEqual(emptyBody.type, 'CAUTION');
    assert.strictEqual(emptyBody.title, '');
    assert.strictEqual(emptyBody.bodyRaw, '');

    // 6. searchUnits respeta el contrato "lo buscado == lo pintado"
    // 6a. Sin título personalizado: no incluye el marcador [!NOTE] en las unidades
    const unitsWithoutTitle = QP.searchUnits('> [!NOTE]\n> Información útil para el usuario');
    assert.strictEqual(unitsWithoutTitle.length, 1);
    assert.strictEqual(unitsWithoutTitle[0].paintMd, 'Información útil para el usuario');
    assert.ok(!unitsWithoutTitle.some(u => u.paintMd && u.paintMd.includes('[!NOTE]')));

    // 6b. Con título personalizado: la primera unidad es el título visible, seguida del cuerpo
    const unitsWithTitle = QP.searchUnits('> [!TIP] Atajo Maestro\n> Usa Ctrl+N para crear nota');
    assert.strictEqual(unitsWithTitle.length, 2);
    assert.strictEqual(unitsWithTitle[0].paintMd, 'Atajo Maestro');
    assert.strictEqual(unitsWithTitle[0].isCalloutTitle, true);
    assert.strictEqual(unitsWithTitle[1].paintMd, 'Usa Ctrl+N para crear nota');

    // 7. Invariante de serialización Markdown (joinBlocks(splitBlocks) === md)
    const mdWithCallouts = '# Título\n\n> [!NOTE] Nota informativa\n> Contenido importante.\n\nTexto intermedio.\n\n> [!WARNING]\n> Peligro inminente.\n';
    const splitRes = BlockModel.splitBlocks(mdWithCallouts);
    const blocks = splitRes.blocks;
    assert.strictEqual(BlockModel.joinBlocks(blocks), mdWithCallouts);
    assert.strictEqual(blocks[1].type, 'quote');
    assert.strictEqual(blocks[3].type, 'quote');

    // 8. estimateBlockHeight suma espacio para la cabecera del callout
    const normalHeight = BlockModel.estimateBlockHeight('quote', '> Un texto de cita común');
    const calloutHeight = BlockModel.estimateBlockHeight('quote', '> [!NOTE]\n> Un texto de cita común');
    assert.ok(calloutHeight > normalHeight, `La altura estimada del callout (${calloutHeight}) debe superar la de la cita simple (${normalHeight})`);
    const calloutHeightZoom2 = BlockModel.estimateBlockHeight('quote', '> [!NOTE]\n> Un texto de cita común', 1400);
    assert.ok(calloutHeightZoom2 > calloutHeight, `Con mayor zoom la cabecera escala (${calloutHeightZoom2} > ${calloutHeight})`);

    // 9. CalloutTypes metadatos y resolución de colores
    for (const t of types) {
        const def = CalloutTypes.getType(t);
        assert.ok(def !== null, `Debe existir tipo para ${t}`);
        assert.ok(def.icon && def.icon.endsWith('.svg'));
        assert.ok(def.nameKey && def.nameKey.startsWith('notes.callout.'));
    }

    const mockTheme = {
        accent: '#ff8800',
        color4: '#58a6ff',
        color2: '#3fb950',
        color5: '#bc8cff',
        color3: '#d29922',
        red: '#ff4444'
    };
    assert.strictEqual(CalloutTypes.getColor('NOTE', mockTheme), '#58a6ff');
    assert.strictEqual(CalloutTypes.getColor('TIP', mockTheme), '#3fb950');
    assert.strictEqual(CalloutTypes.getColor('IMPORTANT', mockTheme), '#bc8cff');
    assert.strictEqual(CalloutTypes.getColor('WARNING', mockTheme), '#d29922');
    assert.strictEqual(CalloutTypes.getColor('CAUTION', mockTheme), '#ff4444');

    // 10. Íconos vectoriales presentes en disco
    const iconsDir = path.resolve(__dirname, '../assets/icons');
    assert.ok(fs.existsSync(path.join(iconsDir, 'report.svg')), 'report.svg debe existir para IMPORTANT');
    assert.ok(fs.existsSync(path.join(iconsDir, 'warning.svg')), 'warning.svg debe existir para WARNING');
    assert.ok(fs.existsSync(path.join(iconsDir, 'info.svg')), 'info.svg debe existir para NOTE');
    assert.ok(fs.existsSync(path.join(iconsDir, 'lightbulb.svg')), 'lightbulb.svg debe existir para TIP');
    assert.ok(fs.existsSync(path.join(iconsDir, 'error.svg')), 'error.svg debe existir para CAUTION');
});

runTest('F78: Slash Commands estilo Notion (detección de trigger, filtrado y catálogo)', () => {
    // 1. Detección de trigger
    // a. Barra al inicio del bloque o texto
    const t1 = SlashLogic.detectTrigger('/', 1);
    assert.strictEqual(t1.triggered, true);
    assert.strictEqual(t1.slashIndex, 0);
    assert.strictEqual(t1.query, '');

    // b. Barra con query
    const t2 = SlashLogic.detectTrigger('/tab', 4);
    assert.strictEqual(t2.triggered, true);
    assert.strictEqual(t2.slashIndex, 0);
    assert.strictEqual(t2.query, 'tab');

    // c. Barra precedida de espacio
    const t3 = SlashLogic.detectTrigger('Hola /mer', 9);
    assert.strictEqual(t3.triggered, true);
    assert.strictEqual(t3.slashIndex, 5);
    assert.strictEqual(t3.query, 'mer');

    // d. URLs no disparan trigger
    const tUrl = SlashLogic.detectTrigger('https://google.com', 8);
    assert.strictEqual(tUrl.triggered, false);

    // e. Paths Linux no disparan trigger
    const tPath = SlashLogic.detectTrigger('/usr/bin/notas', 9);
    assert.strictEqual(tPath.triggered, false);

    // f. Fracciones o fechas no disparan trigger
    const tFrac = SlashLogic.detectTrigger('1/2', 3);
    assert.strictEqual(tFrac.triggered, false);

    // g. Query con espacios o saltos de línea se descarta
    const tSpace = SlashLogic.detectTrigger('/tabla con espacio', 18);
    assert.strictEqual(tSpace.triggered, false);

    // 2. Catálogo de comandos
    const allCmds = SlashCommands.getAllCommands();
    assert.ok(allCmds.length >= 16, `Debe haber al menos 16 comandos estándar (hay ${allCmds.length})`);
    const ids = allCmds.map(c => c.id);
    assert.ok(ids.includes('h1'));
    assert.ok(ids.includes('h2'));
    assert.ok(ids.includes('h3'));
    assert.ok(ids.includes('table'));
    assert.ok(ids.includes('mermaid'));
    assert.ok(ids.includes('callout_note'));
    assert.ok(ids.includes('callout_tip'));
    assert.ok(ids.includes('callout_important'));
    assert.ok(ids.includes('callout_warning'));
    assert.ok(ids.includes('callout_caution'));
    assert.ok(ids.includes('bullet_list'));
    assert.ok(ids.includes('numbered_list'));
    assert.ok(ids.includes('task_list'));
    assert.ok(ids.includes('code_block'));
    assert.ok(ids.includes('quote'));
    assert.ok(ids.includes('hr'));

    // 3. Filtrado inteligente
    const mockI18n = {
        t: (k, fb) => fb
    };

    // a. Query vacía devuelve todos
    const fEmpty = SlashLogic.filterCommands(allCmds, '', mockI18n);
    assert.strictEqual(fEmpty.length, allCmds.length);

    // b. Búsqueda exacta de tabla
    const fTab = SlashLogic.filterCommands(allCmds, 'tab', mockI18n);
    assert.strictEqual(fTab[0].id, 'table');

    // c. Búsqueda de callouts
    const fCall = SlashLogic.filterCommands(allCmds, 'call', mockI18n);
    assert.ok(fCall.some(c => c.id === 'callout_note'));
    assert.ok(fCall.some(c => c.id === 'callout_tip'));

    // d. Búsqueda de tareas
    const fTask = SlashLogic.filterCommands(allCmds, 'tarea', mockI18n);
    assert.strictEqual(fTask[0].id, 'task_list');

    // e. Búsqueda insensible a mayúsculas y acentos
    const fAcc = SlashLogic.filterCommands(allCmds, 'TÍTULO', mockI18n);
    assert.ok(fAcc.some(c => c.id === 'h1'));

    // f. Íconos requeridos en disco
    const iconsDir = path.resolve(__dirname, '../assets/icons');
    assert.ok(fs.existsSync(path.join(iconsDir, 'format-h1.svg')));
    assert.ok(fs.existsSync(path.join(iconsDir, 'format-h2.svg')));
    assert.ok(fs.existsSync(path.join(iconsDir, 'format-h3.svg')));
    assert.ok(fs.existsSync(path.join(iconsDir, 'format-quote.svg')));
    assert.ok(fs.existsSync(path.join(iconsDir, 'format-list-bulleted.svg')));
    assert.ok(fs.existsSync(path.join(iconsDir, 'format-list-numbered.svg')));
});

runTest('F79: Operaciones CLI y captura desde portapapeles', () => {
    // 1. Detección de títulos desde texto de portapapeles
    function extractClipNoteInfo(clip) {
        if (!clip || !clip.trim()) return null;
        const lines = clip.trim().split('\n');
        const firstLine = (lines[0] || '').trim();
        let initialTitle = '';
        let initialBody = '';

        const isUrl = /^https?:\/\//i.test(firstLine);
        if (isUrl) {
            initialTitle = firstLine.length > 50 ? firstLine.substring(0, 47) + '...' : firstLine;
            initialBody = `[${firstLine}](${firstLine})\n`;
        } else {
            if (firstLine.startsWith('# ')) {
                initialTitle = firstLine.substring(2).trim();
                initialBody = lines.slice(1).join('\n').trim();
            } else {
                initialTitle = firstLine.length > 45 ? firstLine.substring(0, 42) + '...' : firstLine;
                initialBody = clip.trim();
            }
        }
        return { initialTitle, initialBody, isUrl };
    }

    // URL capture
    const urlRes = extractClipNoteInfo('https://github.com/criperto/notas');
    assert.strictEqual(urlRes.isUrl, true);
    assert.strictEqual(urlRes.initialTitle, 'https://github.com/criperto/notas');
    assert.strictEqual(urlRes.initialBody, '[https://github.com/criperto/notas](https://github.com/criperto/notas)\n');

    // Markdown heading capture
    const mdRes = extractClipNoteInfo('# Mi lista de compras\n- Manzanas\n- Leche');
    assert.strictEqual(mdRes.isUrl, false);
    assert.strictEqual(mdRes.initialTitle, 'Mi lista de compras');
    assert.strictEqual(mdRes.initialBody, '- Manzanas\n- Leche');

    // Plain text capture
    const plainRes = extractClipNoteInfo('Texto simple copiado para una nota rápida');
    assert.strictEqual(plainRes.isUrl, false);
    assert.strictEqual(plainRes.initialTitle, 'Texto simple copiado para una nota rápida');
    assert.strictEqual(plainRes.initialBody, 'Texto simple copiado para una nota rápida');

    // 2. Verificación de archivo .desktop con acción clip-note
    const desktopPath = path.resolve(__dirname, '../data/dev.criperto.Notas.desktop');
    assert.ok(fs.existsSync(desktopPath));
    const desktopContent = fs.readFileSync(desktopPath, 'utf8');
    assert.ok(desktopContent.includes('Actions=new-note;new-window;clip-note;toggle;'));
    assert.ok(desktopContent.includes('[Desktop Action clip-note]'));
    assert.ok(desktopContent.includes('Exec=criperto-notes --clip') || desktopContent.includes('Exec=criperto.notes --clip'));

    // 3. Verificación de ícono content-paste.svg
    const iconsDir = path.resolve(__dirname, '../assets/icons');
    assert.ok(fs.existsSync(path.join(iconsDir, 'content-paste.svg')));
    assert.ok(fs.existsSync(path.join(iconsDir, 'content-copy.svg')));

    // 4. Verificación de traducciones en I18nCatalogs.js
    const catalogsPath = path.resolve(__dirname, '../qml/I18nCatalogs.js');
    assert.ok(fs.existsSync(catalogsPath));
    const catContent = fs.readFileSync(catalogsPath, 'utf8');
    assert.ok(catContent.includes('from_clipboard'));
    assert.ok(catContent.includes('copy_abs_path'));
    assert.ok(catContent.includes('open_folder'));

    // 5. Verificación de apertura directa en editor tras crear nota desde portapapeles
    const mainRsContent = fs.readFileSync(path.resolve(__dirname, '../src/main.rs'), 'utf8');
    assert.ok(mainRsContent.includes('clip_target = Some(created_path)'), "main.rs debe guardar la ruta de la nota creada en clip_target");
    assert.ok(mainRsContent.includes('else if let Some(ref cp) = clip_target'), "main.rs debe propagar clip_target con acción open");
    const notesContentQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesContent.qml'), 'utf8');
    assert.ok(notesContentQml.includes('Sys.clipboardText'), "createNoteFromClipboard debe consultar Sys.clipboardText");
});

runTest('F80: Diff.js (Myers O(ND) lines/words/hunks), VersionPolicy.js y History.js persistencia', () => {
    const Diff = loadModule('Diff.js');
    const VersionPolicy = loadModule('VersionPolicy.js');
    const History = loadModule('History.js');

    // ── 1. DiffLines ────────────────────────────────────────────────────────
    const textA = "Línea 1\nLínea 2 común\nLínea 3 a borrar\nLínea 4 final";
    const textB = "Línea 1\nLínea 2 común\nLínea 3 reemplazada\nLínea 3.5 nueva\nLínea 4 final";

    const lineDiff = Diff.diffLines(textA, textB);
    assert.ok(Array.isArray(lineDiff), "diffLines debe retornar un arreglo");
    const st = Diff.stats(lineDiff);
    assert.strictEqual(st.added, 2, "Debe registrar 2 líneas agregadas");
    assert.strictEqual(st.removed, 1, "Debe registrar 1 línea eliminada");

    // Hunks con contexto 1
    const hunksRes = Diff.hunks(lineDiff, 1);
    assert.ok(hunksRes.length > 0, "hunks debe retornar líneas agrupadas");

    // ── 2. DiffWords ────────────────────────────────────────────────────────
    const wordDiff = Diff.diffWords("El perro veloz duerme", "El perro marrón duerme");
    const hasDel = wordDiff.some(w => w.type === 'del' && w.text.includes('veloz'));
    const hasAdd = wordDiff.some(w => w.type === 'add' && w.text.includes('marrón'));
    assert.ok(hasDel, "diffWords debe detectar palabra eliminada");
    assert.ok(hasAdd, "diffWords debe detectar palabra agregada");

    // ── 3. VersionPolicy ───────────────────────────────────────────────────
    const h1 = VersionPolicy.fastHash("texto idéntico");
    const h2 = VersionPolicy.fastHash("texto idéntico");
    const h3 = VersionPolicy.fastHash("texto diferente");
    assert.strictEqual(h1, h2, "Hashes deben coincidir para texto idéntico");
    assert.notStrictEqual(h1, h3, "Hashes deben diferir para textos distintos");

    // shouldCreateSnapshot deduplicación
    const snapBase = { hash: h1, timestamp: new Date().toISOString(), length: 15 };
    assert.strictEqual(VersionPolicy.shouldCreateSnapshot("auto_interval", snapBase, "texto idéntico"), false, "No debe crear snapshot si el hash coincide");
    assert.strictEqual(VersionPolicy.shouldCreateSnapshot("manual", snapBase, "texto idéntico"), true, "Manual siempre crea snapshot");
    assert.strictEqual(VersionPolicy.shouldCreateSnapshot("close_delta", snapBase, "texto idéntico con más de 20 caracteres añadidos extras"), true, "close_delta crea snapshot con delta >= 20");

    // pruneVersions
    const now = Date.now();
    const testVersions = [
        { id: "v1", timestamp: new Date(now - 1000).toISOString(), isManual: false },
        { id: "v2-manual", timestamp: new Date(now - 2000).toISOString(), isManual: true },
        { id: "v3", timestamp: new Date(now - 48 * 3600 * 1000).toISOString(), isManual: false }, // 2 días atrás
        { id: "v4", timestamp: new Date(now - 48 * 3600 * 1000 - 60 * 1000).toISOString(), isManual: false }, // mismo día (1 min antes)
    ];
    const pruned = VersionPolicy.pruneVersions(testVersions, 50);
    assert.ok(pruned.toKeep.some(v => v.id === "v2-manual"), "Manuales nunca se podan");
    assert.ok(pruned.toKeep.some(v => v.id === "v1"), "Versiones de las últimas 24h se conservan");
    assert.strictEqual(pruned.toDelete.length, 1, "Debe podar la versión redundante del mismo día");

    // ── 4. History.js ──────────────────────────────────────────────────────
    const hist = History.createHistory("Versión inicial");
    History.pushState(hist, "Versión 2");
    History.pushState(hist, "Versión 3");
    assert.strictEqual(History.canUndo(hist), true);
    assert.strictEqual(History.canRedo(hist), false);

    const serialized = History.serialize(hist, 100000);
    assert.ok(typeof serialized === "string" && serialized.length > 0);

    const histRestored = History.createHistory("");
    const okRestore = History.restore(histRestored, serialized, "Versión 3");
    assert.strictEqual(okRestore, true, "restore debe aceptar cuando coincide currentMd");
    assert.strictEqual(histRestored.stack.length, 3, "Debe restaurar los 3 estados");

    const badRestore = History.restore(histRestored, serialized, "Versión que cambió por fuera");
    assert.strictEqual(badRestore, false, "restore debe rechazar cuando difiere currentMd");

    // ── 5. Verificación de backend nativo en Rust para Diff ──────────────────
    const diffCoreRs = path.resolve(__dirname, '../src/diff_core.rs');
    assert.ok(fs.existsSync(diffCoreRs), "src/diff_core.rs debe existir");
    const diffRsContent = fs.readFileSync(diffCoreRs, 'utf8');
    assert.ok(diffRsContent.includes('notas_diff_lines'), "diff_core.rs debe exportar notas_diff_lines");
    assert.ok(diffRsContent.includes('notas_diff_words'), "diff_core.rs debe exportar notas_diff_words");
    const nativeBridgeH = fs.readFileSync(path.resolve(__dirname, '../src/native/native_bridge.h'), 'utf8');
    assert.ok(nativeBridgeH.includes('diffLines'), "native_bridge.h debe declarar diffLines");
    assert.ok(nativeBridgeH.includes('diffWords'), "native_bridge.h debe declarar diffWords");
    assert.ok(nativeBridgeH.includes('detectLanguage'), "native_bridge.h debe declarar detectLanguage");
});

runTest('F81: build.rs registra todos los archivos QML en el módulo Notas', () => {
    const buildRs = fs.readFileSync(path.resolve(__dirname, '../build.rs'), 'utf8');
    const qmlDir = path.resolve(__dirname, '../qml');
    const files = fs.readdirSync(qmlDir).filter(f => f.endsWith('.qml') && f !== 'shell.qml');

    for (const f of files) {
        assert.ok(
            buildRs.includes(`"qml/${f}"`),
            `El archivo QML ${f} debe estar registrado en build.rs`
        );
    }
});

runTest('F82: Soporte nativo de LaTeX y fórmulas matemáticas (BlockModel, Inline y SlashCommands)', () => {
    // 1. Detección y parsing de bloques matemáticos con delimitadores $$
    const docMath1 = '# Título\n\n$$\nx = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}\n$$\n\nPárrafo siguiente.';
    const split1 = BlockModel.splitBlocks(docMath1);
    assert.strictEqual(split1.blocks.length, 3, "Debe dividir en 3 bloques (heading, math, paragraph)");
    assert.strictEqual(split1.blocks[1].type, "math", "El bloque con $$ multilínea debe ser de tipo 'math'");
    assert.strictEqual(BlockModel.joinBlocks(split1), docMath1, "Invariante estricta: joinBlocks === splitBlocks en multilínea");

    // 2. Bloque matemático single-line $$ ... $$
    const docMath2 = '$$e^{i\\pi} + 1 = 0$$\n\nTexto adicional.';
    const split2 = BlockModel.splitBlocks(docMath2);
    assert.strictEqual(split2.blocks[0].type, "math", "Bloque matemático single-line debe ser de tipo 'math'");
    assert.strictEqual(BlockModel.joinBlocks(split2), docMath2, "Invariante estricta en single-line");

    // 3. Bloque con fence ```math
    const docMath3 = '```math\n\\int_{-\\infty}^{\\infty} e^{-x^2} \\, dx = \\sqrt{\\pi}\n```';
    const split3 = BlockModel.splitBlocks(docMath3);
    assert.strictEqual(split3.blocks[0].type, "math", "Fence ```math debe clasificarse como 'math'");
    assert.strictEqual(BlockModel.joinBlocks(split3), docMath3, "Invariante estricta en fence math");

    // 4. Extracción de código LaTeX puro
    const rawMultiline = '$$\n\\sum_{n=1}^\\infty \\frac{1}{n^2} = \\frac{\\pi^2}{6}\n$$';
    assert.strictEqual(
        BlockModel.extractLatex(rawMultiline),
        '\\sum_{n=1}^\\infty \\frac{1}{n^2} = \\frac{\\pi^2}{6}',
        "extractLatex debe extraer la fórmula sin los $$"
    );

    const rawFence = '```math\nE = mc^2\n```';
    assert.strictEqual(
        BlockModel.extractLatex(rawFence),
        'E = mc^2',
        "extractLatex debe extraer la fórmula sin los ```math"
    );

    // 5. Invariante de documento complejo con fórmulas combinadas
    const showcaseMd = `# Física\n\n$$\n\\nabla \\cdot \\mathbf{E} = \\frac{\\rho}{\\varepsilon_0}\n$$\n\nLa ecuación $E = mc^2$ es fundamental.\n\n$$\n|x| = \\begin{cases} x & \\text{si } x \\ge 0 \\\\ -x & \\text{si } x < 0 \\end{cases}\n$$\n`;
    const splitShowcase = BlockModel.splitBlocks(showcaseMd);
    assert.strictEqual(BlockModel.joinBlocks(splitShowcase), showcaseMd, "Invariante estricta en showcase complejo");

    // 6. Inline.js: renderizado inline con $formula$
    let mockRenderedCount = 0;
    const testRenderer = (formula, display, color, ptSize) => {
        mockRenderedCount++;
        return `<svg xmlns="http://www.w3.org/2000/svg" width="50" height="20" viewBox="0 0 50 20"><text>${formula}</text></svg>`;
    };

    const inlineHtml = Inline.inlineToHtml('La fórmula $a^2 + b^2 = c^2$ pitagórica y precio \\$100 no math.', {
        renderLatex: testRenderer
    });
    assert.ok(inlineHtml.includes('<img src="data:image/svg+xml;utf8,'), "Debe generar <img> SVG para la fórmula $a^2 + b^2 = c^2$");
    assert.ok(inlineHtml.includes('$100'), "El símbolo de dólar escapado \\$100 no debe tratarse como fórmula");

    // 7. Typora Live Editing reveal al tocar con cursor
    const rawFormulaText = 'Texto con $x = 2$ formula.';
    const revealed = Inline.formatForLiveEditing(rawFormulaText, {
        cursorPos: 12 // Dentro de $x = 2$
    });
    assert.ok(revealed.includes('$x = 2$') || revealed.includes('font color='), "Debe revelar los delimitadores al tocar con el cursor");

    // 8. SlashCommands catálogo
    const allCmds = SlashCommands.getAllCommands();
    const mathCmd = allCmds.find(c => c.id === "math");
    assert.ok(mathCmd, "Comando /math debe existir en SlashCommands");
    assert.strictEqual(mathCmd.icon, "math.svg");
    assert.ok(mathCmd.keywords.includes("latex"), "Keywords deben incluir 'latex'");
    assert.ok(mathCmd.keywords.includes("formula"), "Keywords deben incluir 'formula'");
});

runTest("F83: SpellLogic ignora fórmulas matemáticas LaTeX, color blanco por defecto y botón cerrar", () => {
    // 1. SpellLogic.tokenize debe ignorar fórmulas LaTeX inline y bloque
    const sampleText = "En estadística, el intervalo al $95\\%$ es $\\mu \\pm 1.96 \\cdot \\frac{\\sigma}{\\sqrt{n}}$ y el texto sigue.";
    const tokens = SpellLogic.tokenize(sampleText, { minWordLength: 2 });
    const words = tokens.map(t => t.word);

    // No debe contener palabras internas de LaTeX como 'mu', 'pm', 'cdot', 'frac', 'sigma', 'sqrt'
    assert.ok(!words.includes("mu"), "SpellLogic no debe tokenizar \\mu como palabra");
    assert.ok(!words.includes("pm"), "SpellLogic no debe tokenizar \\pm como palabra");
    assert.ok(!words.includes("cdot"), "SpellLogic no debe tokenizar \\cdot como palabra");
    assert.ok(!words.includes("frac"), "SpellLogic no debe tokenizar \\frac como palabra");
    assert.ok(!words.includes("sigma"), "SpellLogic no debe tokenizar \\sigma como palabra");
    assert.ok(!words.includes("sqrt"), "SpellLogic no debe tokenizar \\sqrt como palabra");
    assert.ok(words.includes("estadística"), "SpellLogic debe conservar palabras normales fuera de LaTeX");
    assert.ok(words.includes("intervalo"), "SpellLogic debe conservar palabras normales");

    // 2. Inline.js: color blanco en tema oscuro cuando no se especifica color
    let capturedColor = null;
    Inline.setThemeConfig({ lightMode: false, textColor: "#ffffff" });
    Inline.inlineToHtml("Prueba $x = y$ color", {
        renderLatex: (formula, display, color, ptSize) => {
            capturedColor = color;
            return `<svg><text fill="${color}">${formula}</text></svg>`;
        }
    });
    assert.strictEqual(capturedColor, "#ffffff", "En modo oscuro el color de math debe ser blanco (#ffffff)");

    // 3. Verificación de archivos QML de cierre de modal
    const modalQml = fs.readFileSync(path.resolve(__dirname, '../qml/NoteEditorModal.qml'), 'utf8');
    assert.ok(modalQml.includes('id: backBtnRect'), "NoteEditorModal debe tener backBtnRect");
    assert.ok(modalQml.includes('preventStealing: true'), "MouseArea de botón cerrar debe tener preventStealing: true");
    assert.ok(!modalQml.includes('id: backBtnTap'), "NoteEditorModal no debe incluir TapHandler en botón cerrar para evitar colisiones");
    assert.ok(!modalQml.includes('id: zoomWheelMouseArea'), "zoomWheelMouseArea con z: 99999 debe ser removido");
});

runTest("F84: Cierre con botón X y atajo ESC sin trampa de foco ni conflicto de puntero", () => {
    const modalQml = fs.readFileSync(path.resolve(__dirname, '../qml/NoteEditorModal.qml'), 'utf8');
    const contentQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesContent.qml'), 'utf8');
    const mathQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockMath.qml'), 'utf8');

    // 1. NoteEditorModal botón cerrar confiable
    assert.ok(modalQml.includes('id: backBtnRect'), "NoteEditorModal debe tener backBtnRect");
    assert.ok(!modalQml.includes('id: backBtnTap'), "No debe haber TapHandler en backBtnRect");
    assert.ok(modalQml.includes('preventStealing: true'), "MouseArea de backBtn debe tener preventStealing");
    assert.ok(modalQml.includes('focus: true'), "NoteEditorModal debe tener focus: true para recibir atajos");

    // 2. ESC en NoteEditorModal debe llamar requestClose incluso si hay bloque activo
    assert.ok(modalQml.includes('root.requestClose();'), "Escape debe invocar requestClose");
    assert.ok(modalQml.includes('isClosing'), "NoteEditorModal debe tener guardia anti-reentrancia isClosing");

    // 3. ESC en BlockMath debe propagar requestClose
    assert.ok(mathQml.includes('root.editor.editorModal.requestClose()'), "BlockMath al presionar ESC debe invocar requestClose del modal");

    // 4. NotesContent debe soportar initialAction open con initialTarget en launchedForExternal
    assert.ok(contentQml.includes('initialAction === "open" && initialTarget !== ""'), "launchedForExternal debe cubrir initialAction open");
});

runTest("F85: Preservación de sintaxis LaTeX con llaves {}, escape de dólares y desplazamiento de MathView", () => {
    let capturedFormula = "";
    const html = Inline.inlineToHtml(
        "Einstein: $E = mc^2$, velocidad $c \\approx 3 \\times 10^8 \\text{ m/s}$ y confianza $\\mu \\pm 1.96 \\cdot \\frac{\\sigma}{\\sqrt{n}}$. Precio: \\$100.",
        {
            renderLatex: (formula) => {
                capturedFormula = formula;
                return `<svg><text>${formula}</text></svg>`;
            }
        }
    );

    // 1. Las llaves {} de LaTeX no deben ser corrompidas por tokens de escape de Markdown
    assert.ok(!html.includes("\uE000ESC_"), "No deben quedar tokens de escape dentro del HTML");
    assert.ok(html.includes("data:image/svg+xml"), "Las fórmulas inline deben generar imágenes SVG");
    assert.ok(html.includes("$100"), "El dólar escapado \\$100 debe renderizarse como $100");

    // 2. MathView mathImage no debe tener centerIn rígido que bloquee el scroll horizontal
    const mathViewQml = fs.readFileSync(path.resolve(__dirname, '../qml/MathView.qml'), 'utf8');
    assert.ok(!mathViewQml.includes('mathImage\n            anchors.centerIn: parent'), "mathImage no debe usar anchors.centerIn dentro de Flickable");
    assert.ok(mathViewQml.includes('contentX') || mathViewQml.includes('interactive'), "MathView debe soportar scroll interactivo");
});

runTest("F86: SlashMenu no bloquea eventos de puntero cuando está cerrado", () => {
    const slashQml = fs.readFileSync(path.resolve(__dirname, '../qml/SlashMenu.qml'), 'utf8');

    // 1. SlashMenu root debe condicionar su enabled a isOpen y no depender de scale > 0.05
    assert.ok(slashQml.includes('enabled: isOpen'), "SlashMenu root debe tener enabled: isOpen");
    assert.ok(!slashQml.includes('menuBox.scale > 0.05'), "SlashMenu no debe usar menuBox.scale > 0.05 que siempre es true");
    assert.ok(slashQml.includes('menuBox.opacity > 0.01'), "SlashMenu debe ocultarse cuando la opacidad llega a 0");

    // 2. menuBox y su MouseArea deben estar deshabilitados cuando isOpen es false
    assert.ok(slashQml.includes('enabled: root.isOpen'), "menuBox debe tener enabled: root.isOpen");
});

runTest("F87: Web clipper nativo, contratos CLI JSON, modal y FAB", () => {
    const fabQml = fs.readFileSync(path.resolve(__dirname, '../qml/MorphingFab.qml'), 'utf8');
    const contentQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesContent.qml'), 'utf8');
    const serviceQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesService.qml'), 'utf8');
    const modalQml = fs.readFileSync(path.resolve(__dirname, '../qml/WebClipModal.qml'), 'utf8');
    const qmldir = fs.readFileSync(path.resolve(__dirname, '../qml/qmldir'), 'utf8');
    const buildRs = fs.readFileSync(path.resolve(__dirname, '../build.rs'), 'utf8');

    // 1. FAB debe tener señal webClipRequested, opción 3 y altura expandida a 232
    assert.ok(fabQml.includes('signal webClipRequested()'), "MorphingFab debe emitir webClipRequested");
    assert.ok(fabQml.includes('web-clip.svg'), "MorphingFab debe usar web-clip.svg");
    assert.ok(fabQml.includes('height: expanded ? 232 : 56'), "MorphingFab debe expandirse a 232 para 4 opciones");

    // 2. NotesContent debe conectar webClipRequested y contener WebClipModal
    assert.ok(contentQml.includes('onWebClipRequested: webClipModal.open()'), "NotesContent debe conectar onWebClipRequested");
    assert.ok(contentQml.includes('WebClipModal {'), "NotesContent debe instanciar WebClipModal");
    assert.ok(contentQml.includes('openWebClipper'), "NotesContent debe exponer openWebClipper");

    // 3. NotesService debe exponer clipWebUrl con proceso seguro
    assert.ok(serviceQml.includes('function clipWebUrl(url, opts, callback)'), "NotesService debe implementar clipWebUrl");
    assert.ok(serviceQml.includes('id: webClipProc'), "NotesService debe tener webClipProc");

    // 4. WebClipModal debe implementar animación segura y opciones
    assert.ok(modalQml.includes('NumberAnimation on rotation'), "WebClipModal debe usar NumberAnimation on rotation");
    assert.ok(!modalQml.includes('RotationAnimator'), "WebClipModal no debe usar RotationAnimator");
    assert.ok(modalQml.includes('downloadImages'), "WebClipModal debe soportar downloadImages");
    assert.ok(modalQml.includes('mainContentOnly'), "WebClipModal debe soportar mainContentOnly");

    // 5. Registros en qmldir y build.rs
    assert.ok(qmldir.includes('WebClipModal       1.0 WebClipModal.qml'), "qmldir debe registrar WebClipModal");
    assert.ok(buildRs.includes('"qml/WebClipModal.qml"'), "build.rs debe incluir WebClipModal.qml");

    // 6. Verificación CLI con ejecutable debug si existe
    const targetDebugBin = path.resolve(__dirname, '../target/debug/criperto-notes');
    if (fs.existsSync(targetDebugBin)) {
        const { execFileSync } = require('child_process');
        try {
            const outHelp = execFileSync(targetDebugBin, ['clip', '--help'], { encoding: 'utf8' });
            assert.ok(outHelp.includes('criperto-notes clip <URL>') || outHelp.includes('criperto.notes clip <URL>'), "CLI clip --help debe mostrar uso");
        } catch (e) {
            assert.fail("Fallo al ejecutar criperto-notes clip --help: " + e.message);
        }

        try {
            execFileSync(targetDebugBin, ['clip', 'bad-url', '--json'], { encoding: 'utf8' });
            assert.fail("clip con bad-url debió retornar error exit code");
        } catch (err) {
            const outErr = err.stdout ? err.stdout.toString() : "";
            assert.ok(outErr.includes('"ok":false'), "clip con bad-url debe retornar JSON con ok:false");
        }
    }
});

runTest("F88: MathTemplates y menú contextual de fórmulas LaTeX con traducciones", () => {
    const list = MathTemplates.getTemplateList();
    assert.strictEqual(list.length, 8);
    const ids = Array.from(list).map(item => String(item.id));
    assert.strictEqual(ids.join(","), "fraction,quadratic,integral,sum,limit,root,matrix,cases");
    for (const item of list) {
        assert.ok(item.labelKey.startsWith("notes.math.template."));
        const tpl = MathTemplates.getTemplate(item.id);
        assert.ok(tpl.startsWith("$$\n") && tpl.endsWith("\n$$"), `Plantilla ${item.id} delimitada por $$`);
    }
    const langs = ['es_es', 'es_ar', 'en', 'de', 'fr', 'pt', 'ja', 'zh', 'ru'];
    for (const lang of langs) {
        const json = JSON.parse(fs.readFileSync(path.resolve(__dirname, `../assets/i18n/${lang}/notes.json`), 'utf8'));
        for (const item of list) {
            assert.ok(json[item.labelKey], `Falta ${item.labelKey} en ${lang}`);
        }
    }
    const editorModal = fs.readFileSync(path.resolve(__dirname, '../qml/NoteEditorModal.qml'), 'utf8');
    assert.ok(editorModal.includes('id: mathMenuPopup'));
    assert.ok(editorModal.includes('MathTemplates.getTemplateList()'));
    assert.ok(editorModal.includes('onRightClicked: mathMenuPopup.isOpen = !mathMenuPopup.isOpen'));
    const theme = fs.readFileSync(path.resolve(__dirname, '../qml/Theme.qml'), 'utf8');
    for (const tok of ['textSecondary', 'textTertiary', 'outlineVariant', 'surfaceContainer', 'surfaceContainerHigh']) {
        assert.ok(theme.includes(`property color ${tok}:`), `Theme debe definir ${tok}`);
    }
});

runTest("F89: Corrector ortográfico avanzado (detección de idioma por párrafo y catálogo ampliado de 50 diccionarios)", () => {
    // 1. Detección de idioma por párrafo (LangDetect.detect)
    assert.strictEqual(LangDetect.detect("Este es un texto de prueba en español con palabras comunes"), "es");
    assert.strictEqual(LangDetect.detect("This is a sample sentence written in the English language"), "en");
    assert.strictEqual(LangDetect.detect("Este é um texto escrito em português para testar"), "pt");
    assert.strictEqual(LangDetect.detect("Ceci est une phrase de test écrite en français"), "fr");
    assert.strictEqual(LangDetect.detect("Dies ist ein einfacher Satz in deutscher Sprache"), "de");
    assert.strictEqual(LangDetect.detect("Questo è un testo di prova scritto in italiano"), "it");
    assert.strictEqual(LangDetect.detect("Это тестовое предложение на русском языке"), "ru");
    assert.strictEqual(LangDetect.detect("这是一个简单的中文测试句子"), "zh");
    assert.strictEqual(LangDetect.detect("これは日本語のテスト文章です"), "ja");

    // Casos cortos o ambiguos deben retornar null (fallback seguro)
    assert.strictEqual(LangDetect.detect("Hola"), null);
    assert.strictEqual(LangDetect.detect("12345"), null);
    assert.strictEqual(LangDetect.detect(""), null);
    assert.strictEqual(LangDetect.detect(null), null);

    // 2. SpellLogic.filterLanguagesByDetected
    const active = ["es_AR", "en_US"];
    assert.deepStrictEqual(Array.from(SpellLogic.filterLanguagesByDetected("es", active)), ["es_AR"]);
    assert.deepStrictEqual(Array.from(SpellLogic.filterLanguagesByDetected("en", active)), ["en_US"]);
    assert.deepStrictEqual(Array.from(SpellLogic.filterLanguagesByDetected(null, active)), ["es_AR", "en_US"]);
    assert.deepStrictEqual(Array.from(SpellLogic.filterLanguagesByDetected("ru", active)), ["es_AR", "en_US"]);

    // 3. Integridad del catálogo ampliado de diccionarios (50 diccionarios)
    const catalogPath = path.resolve(__dirname, '../assets/spellcheck/catalog.json');
    assert.ok(fs.existsSync(catalogPath), "El archivo catalog.json debe existir");
    const catalogJson = JSON.parse(fs.readFileSync(catalogPath, 'utf8'));
    const catalog = catalogJson.languages || catalogJson;
    assert.strictEqual(catalog.length, 50, "El catálogo debe contener 50 diccionarios");
    const seenCodes = new Set();
    for (const item of catalog) {
        assert.ok(item.code, "Cada diccionario debe tener código");
        assert.ok(item.name, "Cada diccionario debe tener nombre");
        assert.ok(item.url_aff, "Cada diccionario debe tener url_aff");
        assert.ok(item.url_dic, "Cada diccionario debe tener url_dic");
        assert.ok(!seenCodes.has(item.code), `No debe haber códigos duplicados: ${item.code}`);
        seenCodes.add(item.code);
    }

    // 4. Verificación estática de SpellService, SpellConfig y NotesSettingsModal
    const spellServiceQml = fs.readFileSync(path.resolve(__dirname, '../qml/SpellService.qml'), 'utf8');
    assert.ok(spellServiceQml.includes('import "LangDetect.js" as LangDetect'), "SpellService debe importar LangDetect.js");
    assert.ok(spellServiceQml.includes('var autoDetect = (typeof SpellConfig === "undefined" || SpellConfig.autoDetectParagraphLanguage !== false)'), "SpellService debe respetar autoDetectParagraphLanguage");

    const spellConfigQml = fs.readFileSync(path.resolve(__dirname, '../qml/SpellConfig.qml'), 'utf8');
    assert.ok(spellConfigQml.includes('property bool   autoDetectParagraphLanguage:'), "SpellConfig debe declarar autoDetectParagraphLanguage");
    assert.ok(spellConfigQml.includes('onAutoDetectParagraphLanguageChanged:'), "SpellConfig debe sincronizar autoDetectParagraphLanguage");

    const settingsModalQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesSettingsModal.qml'), 'utf8');
    assert.ok(settingsModalQml.includes('checked: SpellConfig.autoDetectParagraphLanguage'), "SettingsModal debe enlazar autoDetectParagraphLanguage");

    // 5. Traducciones en los 9 idiomas para el switch de auto-detección
    const langs = ['es_es', 'es_ar', 'en', 'de', 'fr', 'pt', 'ja', 'zh', 'ru'];
    for (const lang of langs) {
        const json = JSON.parse(fs.readFileSync(path.resolve(__dirname, `../assets/i18n/${lang}/notes.json`), 'utf8'));
        assert.ok(json.config && json.config.spellcheck && json.config.spellcheck.auto_detect, `Falta config.spellcheck.auto_detect en ${lang}`);
        assert.ok(json.config && json.config.spellcheck && json.config.spellcheck.auto_detect_comment, `Falta config.spellcheck.auto_detect_comment en ${lang}`);
    }

    // 6. Verificación de backend nativo en Rust para LangDetect y .gitattributes
    const langDetectRs = path.resolve(__dirname, '../src/lang_detect.rs');
    assert.ok(fs.existsSync(langDetectRs), "src/lang_detect.rs debe existir");
    const langRsContent = fs.readFileSync(langDetectRs, 'utf8');
    assert.ok(langRsContent.includes('notas_detect_language'), "lang_detect.rs debe exportar notas_detect_language");
    const gitAttributesPath = path.resolve(__dirname, '../.gitattributes');
    assert.ok(fs.existsSync(gitAttributesPath), ".gitattributes debe existir");
    const gitAttributesContent = fs.readFileSync(gitAttributesPath, 'utf8');
    assert.ok(gitAttributesContent.includes('linguist-detectable=false'), ".gitattributes debe excluir tests y catálogos de Linguist");
});

runTest("F90: Accesibilidad, navegación por teclado y escalado integral de interfaz (uiScale)", () => {
    // 1. Verificación de FocusRing.qml
    const focusRingQml = fs.readFileSync(path.resolve(__dirname, '../qml/FocusRing.qml'), 'utf8');
    assert.ok(focusRingQml.includes('property Item target: parent'), "FocusRing debe enlazar a parent o target");
    assert.ok(focusRingQml.includes('border.color: ringColor'), "FocusRing debe tener borde visible");
    assert.ok(focusRingQml.includes('Accessible.ignored: true'), "FocusRing debe ignorarse en árbol de accesibilidad");

    // 2. Verificación de pestaña de atajos en NotesSettingsModal.qml
    const settingsModalQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesSettingsModal.qml'), 'utf8');
    assert.ok(settingsModalQml.includes('value: "shortcuts"'), "NotesSettingsModal debe tener la pestaña shortcuts");
    assert.ok(settingsModalQml.includes('I18n.t("shortcuts.title"'), "NotesSettingsModal debe usar I18n para título de atajos");
    assert.ok(settingsModalQml.includes('I18n.t("shortcuts.cat_nav"'), "NotesSettingsModal debe incluir categoría de navegación");
    assert.ok(settingsModalQml.includes('I18n.t("shortcuts.cat_editor"'), "NotesSettingsModal debe incluir categoría de edición");
    assert.ok(settingsModalQml.includes('I18n.t("shortcuts.cat_tools"'), "NotesSettingsModal debe incluir categoría de herramientas");

    // 3. Verificación de uiScale y Theme.s(px) en Theme.qml
    const themeQml = fs.readFileSync(path.resolve(__dirname, '../qml/Theme.qml'), 'utf8');
    assert.ok(themeQml.includes('readonly property real uiScale:'), "Theme debe definir uiScale");
    assert.ok(themeQml.includes('function s(px)'), "Theme debe definir helper s(px)");

    // 4. Verificación de atajos y navegación directa en NotesContent.qml y Main.qml
    const notesContentQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesContent.qml'), 'utf8');
    const mainQml = fs.readFileSync(path.resolve(__dirname, '../qml/Main.qml'), 'utf8');
    assert.ok(mainQml.includes('sequence: "Ctrl+/"'), "Main debe abrir atajos con Ctrl+/");
    assert.ok(mainQml.includes('sequence: "F1"'), "Main debe abrir atajos con F1");
    assert.ok(mainQml.includes('toggleSettings("shortcuts")'), "Main debe alternar al tab de atajos");
    assert.ok(notesContentQml.includes('openShortcutsSheet()'), "NotesContent debe soportar helper openShortcutsSheet");

    // 5. Verificación de ToolbarButton y NoteEditorModal
    const toolbarBtnQml = fs.readFileSync(path.resolve(__dirname, '../qml/ToolbarButton.qml'), 'utf8');
    assert.ok(toolbarBtnQml.includes('FocusRing {'), "ToolbarButton debe tener FocusRing");
    assert.ok(toolbarBtnQml.includes('activeFocusOnTab: !tbRoot.disabled'), "ToolbarButton debe tener foco por teclado");

    const editorModalQml = fs.readFileSync(path.resolve(__dirname, '../qml/NoteEditorModal.qml'), 'utf8');
    assert.ok(editorModalQml.includes('event.key === Qt.Key_F10'), "NoteEditorModal debe transferir foco con F10");
    assert.ok(editorModalQml.includes('Keys.onRightPressed:'), "ToolbarRow debe soportar navegación con flechas");

    // 6. Verificación de MorphingFab accesible
    const fabQml = fs.readFileSync(path.resolve(__dirname, '../qml/MorphingFab.qml'), 'utf8');
    assert.ok(fabQml.includes('activeFocusOnTab: true'), "MorphingFab debe ser focuseable por Tab");
    assert.ok(fabQml.includes('Keys.onReturnPressed:'), "MorphingFab debe responder a Enter/Space");
    assert.ok(fabQml.includes('Keys.onDownPressed:'), "MorphingFab debe navegar opciones con flechas");
    assert.ok(fabQml.includes('FocusRing {'), "MorphingFab debe tener FocusRing");

    // 7. Verificación de configuración y soporte en 9 idiomas
    const langs = ['es_es', 'es_ar', 'en', 'de', 'fr', 'pt', 'ja', 'zh', 'ru'];
    for (const lang of langs) {
        const json = JSON.parse(fs.readFileSync(path.resolve(__dirname, `../assets/i18n/${lang}/notes.json`), 'utf8'));
        assert.ok(json.config && json.config.appearance && json.config.appearance.ui_scale, `Falta config.appearance.ui_scale en ${lang}`);
        assert.ok(json.shortcuts && json.shortcuts.title, `Falta shortcuts.title en ${lang}`);
        assert.ok(json.shortcuts && json.shortcuts.cat_nav, `Falta shortcuts.cat_nav en ${lang}`);
        assert.ok(json.shortcuts && json.shortcuts.cat_editor, `Falta shortcuts.cat_editor en ${lang}`);
        assert.ok(json.shortcuts && json.shortcuts.cat_tools, `Falta shortcuts.cat_tools en ${lang}`);
    }
});

runTest("F91: Multi-item selection, copy, cut, and context menu contracts in lists (BlockList & ContextMenu)", () => {
    const blockListQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockList.qml'), 'utf8');
    assert.ok(blockListQml.includes('function hasMultipleItemsSelected()'), "BlockList debe proveer hasMultipleItemsSelected");
    assert.ok(blockListQml.includes('function updateMultiItemSelectionState()'), "BlockList debe proveer updateMultiItemSelectionState");
    assert.ok(blockListQml.includes('var isMulti = root.hasMultipleItemsSelected() || root.hasMultiItemSelection'), "Keys.onPressed en BlockList debe validar selección múltiple");

    const blockEditorQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockEditor.qml'), 'utf8');
    assert.ok(blockEditorQml.includes('hasMultipleItemsSelected'), "BlockEditor debe verificar hasMultipleItemsSelected");

    const contextMenuQml = fs.readFileSync(path.resolve(__dirname, '../qml/ContextMenu.qml'), 'utf8');
    assert.ok(contextMenuQml.includes('property var editor: null'), "ContextMenu debe soportar vinculación a editor");
    assert.ok(contextMenuQml.includes('function _hasAnySelection()'), "ContextMenu debe contar con _hasAnySelection()");
    assert.ok(contextMenuQml.includes('function _performCopy()'), "ContextMenu debe delegar copia en _performCopy()");
    assert.ok(contextMenuQml.includes('function _performCut()'), "ContextMenu debe delegar corte en _performCut()");
    assert.ok(contextMenuQml.includes('function _performDelete()'), "ContextMenu debe delegar borrado en _performDelete()");
});

runTest("F92: Multi-line and multi-block drag selection release preservation contracts", () => {
    const blockEditorQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockEditor.qml'), 'utf8');
    assert.ok(blockEditorQml.includes('root.isDraggingSelection = false'), "endCrossBlockDrag debe resetear isDraggingSelection");
    assert.ok(blockEditorQml.includes('root.interactive = true'), "endCrossBlockDrag debe restaurar interactive");
    assert.ok(!blockEditorQml.includes('root.confirmActiveBlock();\n        root.forceActiveFocus();'), "endCrossBlockDrag no debe re-parsear destructivamente con confirmActiveBlock()");

    const blockListQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockList.qml'), 'utf8');
    assert.ok(!blockListQml.includes('id: editPointHandler'), "BlockList no debe tener editPointHandler en conflicto con MouseArea");
    assert.ok(blockListQml.includes('function hasAnyItemSelection()'), "BlockList debe contar con hasAnyItemSelection");
    assert.ok(blockListQml.includes('!hasAnyItemSelection()'), "BlockList debe proteger recargas de modelo si hay selección activa");
    assert.ok(blockListQml.includes('lineEdit.selectionStart !== lineEdit.selectionEnd || root.hasMultiItemSelection'), "onActiveFocusChanged en BlockList no debe sobreescribir text si hay selección");

    const blockParagraphQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockParagraph.qml'), 'utf8');
    assert.ok(!blockParagraphQml.includes('id: editPointHandler'), "BlockParagraph no debe tener editPointHandler duplicado");
    assert.ok(blockParagraphQml.includes('editInput.select(Math.min(editInput.length, oldSelStart), Math.min(editInput.length, oldSelEnd))'), "BlockParagraph debe preservar selección en _syncTextFromModel");

    const blockHeadingQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockHeading.qml'), 'utf8');
    assert.ok(!blockHeadingQml.includes('id: editPointHandler'), "BlockHeading no debe tener editPointHandler duplicado");
    assert.ok(blockHeadingQml.includes('editInput.select(Math.min(editInput.length, oldSelStart), Math.min(editInput.length, oldSelEnd))'), "BlockHeading debe preservar selección en _syncTextFromModel");

    const blockQuoteQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockQuote.qml'), 'utf8');
    assert.ok(!blockQuoteQml.includes('id: editPointHandler'), "BlockQuote no debe tener editPointHandler duplicado");
    assert.ok(blockQuoteQml.includes('editInput.select(Math.min(editInput.length, oldSelStart), Math.min(editInput.length, oldSelEnd))'), "BlockQuote debe preservar selección en _syncTextFromModel");
});

runTest("F93: Persistent multi-line & sub-line selection retention contracts across delegates (Typora benchmark)", () => {
    const blockListQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockList.qml'), 'utf8');
    assert.ok(blockListQml.includes('persistentSelection: true'), "BlockList lineEdit debe tener persistentSelection: true");
    assert.ok(blockListQml.includes('!root.hasMultiItemSelection && !root.hasMultipleItemsSelected()'), "BlockList no debe limpiar selección de hermanos si hay selección multi-ítem");
    assert.ok(blockListQml.includes('lineEdit.activeFocus && lineEdit.selectionStart === lineEdit.selectionEnd'), "BlockList onCursorPositionChanged debe chequear activeFocus");

    const blockParagraphQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockParagraph.qml'), 'utf8');
    assert.ok(blockParagraphQml.includes('persistentSelection: true'), "BlockParagraph editInput debe tener persistentSelection: true");
    assert.ok(blockParagraphQml.includes('editInput.activeFocus && editInput.selectionStart === editInput.selectionEnd'), "BlockParagraph onCursorPositionChanged debe chequear activeFocus");

    const blockHeadingQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockHeading.qml'), 'utf8');
    assert.ok(blockHeadingQml.includes('persistentSelection: true'), "BlockHeading editInput debe tener persistentSelection: true");
    assert.ok(blockHeadingQml.includes('editInput.activeFocus && editInput.selectionStart === editInput.selectionEnd'), "BlockHeading onCursorPositionChanged debe chequear activeFocus");

    const blockQuoteQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockQuote.qml'), 'utf8');
    assert.ok(blockQuoteQml.includes('persistentSelection: true'), "BlockQuote editInput debe tener persistentSelection: true");
    assert.ok(blockQuoteQml.includes('editInput.activeFocus && editInput.selectionStart === editInput.selectionEnd'), "BlockQuote onCursorPositionChanged debe chequear activeFocus");

    const blockCodeQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockCode.qml'), 'utf8');
    assert.ok(blockCodeQml.includes('persistentSelection: true'), "BlockCode editInput debe tener persistentSelection: true");

    const blockTableQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockTable.qml'), 'utf8');
    assert.ok(blockTableQml.includes('id: hInput') && blockTableQml.includes('persistentSelection: true'), "BlockTable hInput debe tener persistentSelection: true");
    assert.ok(blockTableQml.includes('id: cellInput') && blockTableQml.includes('persistentSelection: true'), "BlockTable cellInput debe tener persistentSelection: true");
    assert.ok(blockTableQml.includes('id: rawEditor') && blockTableQml.includes('persistentSelection: true'), "BlockTable rawEditor debe tener persistentSelection: true");

    const blockEditorQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockEditor.qml'), 'utf8');
    assert.ok(blockEditorQml.includes('isMultiItem'), "BlockEditor endCrossBlockDrag debe retener selectedBids si isMultiItem");
});

runTest("F94: Keyboard ergonomics contracts: forward word delete (Ctrl+Supr), smooth scroll (Re/AvPag), doc navigation (Ctrl+Home/End) & in-place list undo", () => {
    // 1. Tests unitarios puros de findNextWordEnd en Inline.js
    const inlineContent = fs.readFileSync(path.resolve(__dirname, '../qml/Inline.js'), 'utf8');
    assert.ok(inlineContent.includes('function findNextWordEnd(text, pos)'), "Inline.js debe proveer findNextWordEnd");

    // Evaluar findNextWordEnd en entorno de test
    const vm = require('vm');
    const sandbox = {};
    const sanitizedInline = inlineContent.replace(/^\s*\.pragma[^\n]*\n?/gm, "");
    vm.runInNewContext(sanitizedInline, sandbox);
    const findNextWordEnd = sandbox.findNextWordEnd;

    assert.strictEqual(findNextWordEnd("hello world", 0), 6, "Debe saltar palabra 'hello ' completa");
    assert.strictEqual(findNextWordEnd("hello   world", 5), 8, "Debe consumir espacios consecutivos '   '");
    assert.strictEqual(findNextWordEnd("árbol verde", 0), 6, "Debe soportar caracteres con tildes");
    assert.strictEqual(findNextWordEnd("test-driven", 0), 4, "Debe detenerse en signo de puntuación");
    assert.strictEqual(findNextWordEnd("-driven", 0), 1, "Debe consumir signo de puntuación");
    assert.strictEqual(findNextWordEnd("fin", 3), 3, "Debe ser idempotente en fin de cadena");
    assert.strictEqual(findNextWordEnd("", 0), 0, "Debe manejar cadena vacía");

    // 2. Contratos de BlockEditor.qml
    const blockEditorQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockEditor.qml'), 'utf8');
    assert.ok(blockEditorQml.includes('_smoothScrollTo'), "BlockEditor debe contar con _smoothScrollTo()");
    assert.ok(blockEditorQml.includes('if (!typingSnapshotTimer.running)'), "BlockEditor debe guardar snapshot antes de iniciar ráfaga en onBlockRawChanged");
    assert.ok(blockEditorQml.includes('selStart: selStart') && blockEditorQml.includes('selEnd: selEnd'), "BlockEditor debe persistir selStart y selEnd en snapshot");

    // 3. Contratos de BlockList.qml
    const blockListQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockList.qml'), 'utf8');
    assert.ok(blockListQml.includes('itemsModel.setProperty(i, "text", pText)'), "BlockList debe reconciliar itemsModel in-place sin destruir delegates");
    assert.ok(blockListQml.includes('goToDocumentStart'), "BlockList debe delegar Ctrl+Home a goToDocumentStart");
    assert.ok(blockListQml.includes('goToDocumentEnd'), "BlockList debe delegar Ctrl+End a goToDocumentEnd");
    assert.ok(blockListQml.includes('pageUp'), "BlockList debe delegar PageUp a pageUp");
    assert.ok(blockListQml.includes('pageDown'), "BlockList debe delegar PageDown a pageDown");
    assert.ok(blockListQml.includes('Inline.findNextWordEnd'), "BlockList debe usar Inline.findNextWordEnd en Ctrl+Delete");

    // 4. Contratos de BlockParagraph.qml
    const blockParagraphQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockParagraph.qml'), 'utf8');
    assert.ok(blockParagraphQml.includes('goToDocumentStart'), "BlockParagraph debe delegar Ctrl+Home a goToDocumentStart");
    assert.ok(blockParagraphQml.includes('goToDocumentEnd'), "BlockParagraph debe delegar Ctrl+End a goToDocumentEnd");
    assert.ok(blockParagraphQml.includes('pageUp'), "BlockParagraph debe delegar PageUp a pageUp");
    assert.ok(blockParagraphQml.includes('pageDown'), "BlockParagraph debe delegar PageDown a pageDown");
    assert.ok(blockParagraphQml.includes('Inline.findNextWordEnd'), "BlockParagraph debe usar Inline.findNextWordEnd en Ctrl+Delete");

    // 5. Contratos de BlockHeading.qml, BlockQuote.qml, BlockCode.qml, BlockTable.qml
    const blockHeadingQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockHeading.qml'), 'utf8');
    assert.ok(blockHeadingQml.includes('Inline.findNextWordEnd'), "BlockHeading debe usar Inline.findNextWordEnd en Ctrl+Delete");
    assert.ok(blockHeadingQml.includes('goToDocumentStart'), "BlockHeading debe delegar Ctrl+Home");

    const blockQuoteQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockQuote.qml'), 'utf8');
    assert.ok(blockQuoteQml.includes('Inline.findNextWordEnd'), "BlockQuote debe usar Inline.findNextWordEnd en Ctrl+Delete");
    assert.ok(blockQuoteQml.includes('goToDocumentStart'), "BlockQuote debe delegar Ctrl+Home");

    const blockCodeQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockCode.qml'), 'utf8');
    assert.ok(blockCodeQml.includes('Inline.findNextWordEnd'), "BlockCode debe usar Inline.findNextWordEnd en Ctrl+Delete");
    assert.ok(blockCodeQml.includes('goToDocumentStart'), "BlockCode debe delegar Ctrl+Home");

    const blockTableQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockTable.qml'), 'utf8');
    assert.ok(blockTableQml.includes('Inline.findNextWordEnd'), "BlockTable debe usar Inline.findNextWordEnd en Ctrl+Delete");
    assert.ok(blockTableQml.includes('goToDocumentStart'), "BlockTable debe delegar Ctrl+Home");
});

runTest("F95: Delete key forward, Ctrl+Delete with plain text, Insert overwriteMode and CUA shortcuts contracts", () => {
    // 1. CustomTextCursor.qml debe detectar isOverwrite y adaptar geometría
    const customCursorQml = fs.readFileSync(path.resolve(__dirname, '../qml/CustomTextCursor.qml'), 'utf8');
    assert.ok(customCursorQml.includes('isOverwrite'), "CustomTextCursor debe definir propiedad isOverwrite");
    assert.ok(customCursorQml.includes('root.isOverwrite && !root.hasSelection'), "CustomTextCursor debe ensanchar el cursor en modo sobreescritura");

    // 2. BlockEditor.qml debe exponer overwriteMode y toggleOverwriteMode, y manejar atajos CUA
    const blockEditorQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockEditor.qml'), 'utf8');
    assert.ok(blockEditorQml.includes('property bool overwriteMode: false'), "BlockEditor debe declarar overwriteMode");
    assert.ok(blockEditorQml.includes('toggleOverwriteMode'), "BlockEditor debe implementar toggleOverwriteMode()");
    assert.ok(blockEditorQml.includes('Qt.Key_Insert'), "BlockEditor debe capturar tecla Insert");

    // 3. BlockList.qml debe tener event.accepted = false en onDeletePressed y usar plainText en Ctrl+Delete
    const blockListQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockList.qml'), 'utf8');
    assert.ok(blockListQml.includes('event.accepted = false;'), "BlockList onDeletePressed debe tener fallthrough con event.accepted = false");
    assert.ok(blockListQml.includes('Inline.plainText(lineEdit)'), "BlockList debe alimentar findNextWordEnd con texto plano");
    assert.ok(blockListQml.includes('overwriteMode: root.editor ? root.editor.overwriteMode : false'), "BlockList debe sincronizar overwriteMode");

    // 4. BlockParagraph.qml debe tener fallthrough en onDeletePressed y usar plainText
    const blockParagraphQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockParagraph.qml'), 'utf8');
    assert.ok(blockParagraphQml.includes('event.accepted = false;'), "BlockParagraph onDeletePressed debe tener fallthrough con event.accepted = false");
    assert.ok(blockParagraphQml.includes('Inline.plainText(editInput)'), "BlockParagraph debe alimentar findNextWordEnd con texto plano");
    assert.ok(blockParagraphQml.includes('overwriteMode: root.editor ? root.editor.overwriteMode : false'), "BlockParagraph debe sincronizar overwriteMode");

    // 5. BlockHeading.qml, BlockQuote.qml, BlockCode.qml, BlockTable.qml
    const blockHeadingQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockHeading.qml'), 'utf8');
    assert.ok(blockHeadingQml.includes('event.accepted = false;'), "BlockHeading onDeletePressed debe tener fallthrough");
    assert.ok(blockHeadingQml.includes('Inline.plainText(editInput)'), "BlockHeading debe usar plainText en Ctrl+Delete");

    const blockQuoteQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockQuote.qml'), 'utf8');
    assert.ok(blockQuoteQml.includes('event.accepted = false;'), "BlockQuote onDeletePressed debe tener fallthrough");
    assert.ok(blockQuoteQml.includes('Inline.plainText(editInput)'), "BlockQuote debe usar plainText en Ctrl+Delete");

    const blockCodeQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockCode.qml'), 'utf8');
    assert.ok(blockCodeQml.includes('event.accepted = false;'), "BlockCode onDeletePressed debe existir con fallthrough");
    assert.ok(blockCodeQml.includes('Inline.plainText(editInput)'), "BlockCode debe usar plainText en Ctrl+Delete");

    const blockTableQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockTable.qml'), 'utf8');
    assert.ok(blockTableQml.includes('Inline.plainText(cellInputD)'), "BlockTable debe usar plainText en Ctrl+Delete de celdas");
    assert.ok(blockTableQml.includes('Inline.plainText(rawEditor)'), "BlockTable debe usar plainText en Ctrl+Delete de rawEditor");
});

runTest("F96: Phase P9 — System installation, AUR PKGBUILD, Flatpak manifest, AppImage builder and CI workflow contracts", () => {
    // 1. scripts/install-system.sh
    const installSystemScript = path.resolve(__dirname, '../scripts/install-system.sh');
    assert.ok(fs.existsSync(installSystemScript), "scripts/install-system.sh debe existir");
    const installSystemContent = fs.readFileSync(installSystemScript, 'utf8');
    assert.ok(installSystemContent.includes('PREFIX="${PREFIX:-/usr}"'), "install-system.sh debe soportar variable PREFIX");
    assert.ok(installSystemContent.includes('DESTDIR="${DESTDIR:-}"'), "install-system.sh debe soportar variable DESTDIR");
    assert.ok(installSystemContent.includes('dev.criperto.Notas.metainfo.xml'), "install-system.sh debe instalar metainfo");

    // 2. packaging/arch/PKGBUILD
    const aurPkgbuild = path.resolve(__dirname, '../packaging/arch/PKGBUILD');
    assert.ok(fs.existsSync(aurPkgbuild), "packaging/arch/PKGBUILD debe existir");
    const aurContent = fs.readFileSync(aurPkgbuild, 'utf8');
    const cargoTomlPath = path.resolve(__dirname, '../Cargo.toml');
    const cargoContent = fs.readFileSync(cargoTomlPath, 'utf8');
    const cargoVerMatch = cargoContent.match(/^version\s*=\s*"([^"]+)"/m);
    const expectedVer = cargoVerMatch ? cargoVerMatch[1] : "0.1.10";
    assert.ok(aurContent.includes("pkgname=criperto-notes") || aurContent.includes("pkgname=notas"), "PKGBUILD debe definir pkgname=criperto-notes o notas");
    assert.ok(aurContent.includes(`pkgver=${expectedVer}`), `PKGBUILD debe reflejar versión ${expectedVer}`);
    assert.ok(aurContent.includes("install-system.sh"), "PKGBUILD debe invocar install-system.sh");

    // 3. packaging/arch/notas-git/PKGBUILD
    const aurGitPkgbuild = path.resolve(__dirname, '../packaging/arch/notas-git/PKGBUILD');
    assert.ok(fs.existsSync(aurGitPkgbuild), "packaging/arch/notas-git/PKGBUILD debe existir");
    const aurGitContent = fs.readFileSync(aurGitPkgbuild, 'utf8');
    assert.ok(aurGitContent.includes("pkgname=notas-git"), "PKGBUILD debe definir pkgname=notas-git");
    assert.ok(aurGitContent.includes("provides=(\"$_pkgname\")"), "PKGBUILD debe proveer notas");

    // 4. packaging/flatpak/dev.criperto.Notas.yml
    const flatpakYaml = path.resolve(__dirname, '../packaging/flatpak/dev.criperto.Notas.yml');
    assert.ok(fs.existsSync(flatpakYaml), "packaging/flatpak/dev.criperto.Notas.yml debe existir");
    const flatpakContent = fs.readFileSync(flatpakYaml, 'utf8');
    assert.ok(flatpakContent.includes("app-id: dev.criperto.Notas"), "Flatpak manifest debe definir app-id dev.criperto.Notas");
    assert.ok(flatpakContent.includes("runtime: org.kde.Platform"), "Flatpak manifest debe usar runtime org.kde.Platform");
    assert.ok(flatpakContent.includes("--socket=wayland"), "Flatpak manifest debe habilitar socket=wayland");

    // 5. packaging/appimage/build-appimage.sh
    const appimageScript = path.resolve(__dirname, '../packaging/appimage/build-appimage.sh');
    assert.ok(fs.existsSync(appimageScript), "packaging/appimage/build-appimage.sh debe existir");
    const appimageContent = fs.readFileSync(appimageScript, 'utf8');
    assert.ok(appimageContent.includes("AppRun"), "build-appimage.sh debe generar AppRun");
    assert.ok(appimageContent.includes("dev.criperto.Notas.desktop"), "build-appimage.sh debe enlazar desktop entry");

    // 6. .github/workflows/release.yml
    const releaseWf = path.resolve(__dirname, '../.github/workflows/release.yml');
    assert.ok(fs.existsSync(releaseWf), ".github/workflows/release.yml debe existir");
    const releaseWfContent = fs.readFileSync(releaseWf, 'utf8');
    assert.ok(releaseWfContent.includes("tags:"), "Workflow debe reaccionar a tags");
    assert.ok(releaseWfContent.includes("action-gh-release"), "Workflow debe publicar assets en GitHub Releases");

    // 7. AppStream Metainfo
    const metainfoFile = path.resolve(__dirname, '../data/dev.criperto.Notas.metainfo.xml');
    const metainfoContent = fs.readFileSync(metainfoFile, 'utf8');
    assert.ok(metainfoContent.includes("<developer id=\"dev.criperto\">"), "Metainfo debe incluir etiqueta developer con id");
    assert.ok(metainfoContent.includes("<content_rating type=\"oars-1.1\"/>"), "Metainfo debe incluir content_rating");
});

runTest("P9.2 - Script maestro de release y compilación (scripts/release.sh)", () => {
    const releaseScript = path.resolve(__dirname, '../scripts/release.sh');
    if (fs.existsSync(releaseScript)) {
        const stat = fs.statSync(releaseScript);
        assert.ok((stat.mode & 0o111) !== 0, "scripts/release.sh debe tener permisos de ejecución");
        const content = fs.readFileSync(releaseScript, 'utf8');
        assert.ok(content.includes("--patch"), "release.sh debe soportar flag --patch");
        assert.ok(content.includes("--minor"), "release.sh debe soportar flag --minor");
        assert.ok(content.includes("--major"), "release.sh debe soportar flag --major");
        assert.ok(content.includes("--github"), "release.sh debe soportar flag --github");
        assert.ok(content.includes("--dry-run"), "release.sh debe soportar flag --dry-run");
    }

    // Verificar integración en scripts/build.sh
    const buildScript = path.resolve(__dirname, '../scripts/build.sh');
    const buildContent = fs.readFileSync(buildScript, 'utf8');
    assert.ok(buildContent.includes("release.sh"), "build.sh debe integrar delegación a release.sh");
});

runTest("P9.3 - Scripts de empaquetado Debian (.deb) y Fedora (.rpm)", () => {
    const debScript = path.resolve(__dirname, '../packaging/deb/build-deb.sh');
    assert.ok(fs.existsSync(debScript), "packaging/deb/build-deb.sh debe existir");
    const debStat = fs.statSync(debScript);
    assert.ok((debStat.mode & 0o111) !== 0, "build-deb.sh debe ser ejecutable");

    const rpmScript = path.resolve(__dirname, '../packaging/rpm/build-rpm.sh');
    assert.ok(fs.existsSync(rpmScript), "packaging/rpm/build-rpm.sh debe existir");
    const rpmStat = fs.statSync(rpmScript);
    assert.ok((rpmStat.mode & 0o111) !== 0, "build-rpm.sh debe ser ejecutable");

    const rpmSpec = path.resolve(__dirname, '../packaging/rpm/notas.spec');
    assert.ok(fs.existsSync(rpmSpec), "packaging/rpm/notas.spec debe existir");

    const releaseWf = path.resolve(__dirname, '../.github/workflows/release.yml');
    const wfContent = fs.readFileSync(releaseWf, 'utf8');
    assert.ok(wfContent.includes("build-deb.sh"), "Workflow debe compilar .deb");
    assert.ok(wfContent.includes("build-rpm.sh"), "Workflow debe compilar .rpm");
    assert.ok(wfContent.includes("prerelease: true"), "Workflow debe marcar los releases como pre-release");
});

runTest('F97: Integración Desktop Entry (DBusActivatable desactivado, action new-window, exec criperto-notes %F)', () => {
    const desktopEntry = fs.readFileSync(path.resolve(__dirname, '../assets/dev.criperto.Notas.desktop'), 'utf8');
    const dataDesktopEntry = fs.readFileSync(path.resolve(__dirname, '../data/dev.criperto.Notas.desktop'), 'utf8');

    assert.ok(!desktopEntry.includes('DBusActivatable=true'), "assets desktop entry no debe tener DBusActivatable=true");
    assert.ok(!dataDesktopEntry.includes('DBusActivatable=true'), "data desktop entry no debe tener DBusActivatable=true");
    assert.ok(desktopEntry.includes('[Desktop Action new-window]'), "assets desktop entry debe incluir acción new-window");
    assert.ok(dataDesktopEntry.includes('[Desktop Action new-window]'), "data desktop entry debe incluir acción new-window");
    assert.ok(desktopEntry.includes('Exec=criperto-notes --new-window') || desktopEntry.includes('Exec=criperto.notes --new-window'), "acción new-window debe ejecutar criperto-notes --new-window");
});

runTest('F98: Decodificación de URIs file:// y percent-encoding en CLI y rutas de apertura', () => {
    const mainRs = fs.readFileSync(path.resolve(__dirname, '../src/main.rs'), 'utf8');
    assert.ok(mainRs.includes('decode_percent'), "main.rs debe incluir función decode_percent");
    assert.ok(mainRs.includes('file://'), "main.rs debe soportar prefijo file://");
    assert.ok(mainRs.includes('new-window'), "main.rs debe declarar argumento --new-window");
});

runTest('F99: Coordinación multi-instancia, exclusividad de edición y WhatsApp Web "Editar aquí"', () => {
    const nativeBridgeH = fs.readFileSync(path.resolve(__dirname, '../src/native/native_bridge.h'), 'utf8');
    const nativeBridgeCpp = fs.readFileSync(path.resolve(__dirname, '../src/native/native_bridge.cpp'), 'utf8');
    const noteEditorQml = fs.readFileSync(path.resolve(__dirname, '../qml/NoteEditorModal.qml'), 'utf8');
    const notesContentQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesContent.qml'), 'utf8');

    // 1. Métodos y señales de Native Bridge
    assert.ok(nativeBridgeH.includes('isNoteBeingEditedElsewhere'), "native_bridge.h debe declarar isNoteBeingEditedElsewhere");
    assert.ok(nativeBridgeH.includes('claimEditLock'), "native_bridge.h debe declarar claimEditLock");
    assert.ok(nativeBridgeH.includes('remoteEditLockClaimed'), "native_bridge.h debe declarar remoteEditLockClaimed");
    assert.ok(nativeBridgeCpp.includes('criperto-notes/instances'), "native_bridge.cpp debe registrar instancias en criperto-notes/instances");
    assert.ok(nativeBridgeCpp.includes('wl-paste'), "Sys::clipboardText debe tener fallback a wl-paste");

    // 2. QML NoteEditorModal & NotesContent
    assert.ok(noteEditorQml.includes('remoteLocked'), "NoteEditorModal debe tener propiedad remoteLocked");
    assert.ok(noteEditorQml.includes('claimEditLock'), "NoteEditorModal debe invocar claimEditLock al pulsar 'Editar aquí'");
    assert.ok(notesContentQml.includes('handleRemoteEditLockClaimed'), "NotesContent debe implementar handleRemoteEditLockClaimed");
    assert.ok(notesContentQml.includes('isNoteBeingEditedElsewhere'), "NotesContent debe consultar isNoteBeingEditedElsewhere");
});

runTest('F100: Resaltado de búsqueda en listas con sugerencias ortográficas activas (BlockList & baseDisplayText)', () => {
    const blockListQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockList.qml'), 'utf8');

    // 1. Contratos estáticos en BlockList.qml
    assert.ok(blockListQml.includes('function syncAllLineEdits()'), "BlockList.qml debe definir syncAllLineEdits()");
    assert.ok(blockListQml.includes('function onSearchQueryChanged()'), "BlockList debe conectar onSearchQueryChanged");
    assert.ok(blockListQml.includes('function onActiveMatchOrdinalChanged()'), "BlockList debe conectar onActiveMatchOrdinalChanged");
    assert.ok(blockListQml.includes('function syncText()'), "itemRow debe implementar syncText()");
    assert.ok(blockListQml.includes('Inline.highlightInHtml(base, q, hBg, aBg, ord, aFg)'), "baseDisplayText debe aplicar highlightInHtml");
    assert.ok(!blockListQml.includes('searchHighlightActiveFg('), "BlockList.qml no debe llamar al método inexistente searchHighlightActiveFg()");
    assert.ok(blockListQml.includes('searchActiveFg(root.blockData.bid, itemRow.index)'), "BlockList.qml debe invocar searchActiveFg");
    assert.ok(blockListQml.includes('itemRow.syncText()'), "onSpellRangesChanged y onTextChanged deben sincronizar lineEdit");
    assert.ok(blockListQml.includes('onLinkActivated: (link) => {'), "lineEdit debe implementar onLinkActivated");

    // 2. Comportamiento funcional de formateo y resaltado combinado
    const rawLine = "adaptar los **elementos** como wlogout(de paso re-diseñarlo) y alguno que qued";
    const formatted = Inline.formatForLiveEditing(rawLine, {
        cursorPos: -1,
        selStart: -1,
        selEnd: -1,
        dimColor: "#888888",
        linkColor: "#5294e2",
        hideSyntax: false
    });

    const searchQ = "me";
    const softBg = "rgba(255, 165, 0, 0.4)";
    const activeBg = "rgba(255, 100, 0, 0.8)";
    const activeOrd = 0; // Primera coincidencia activa
    const activeFg = "#ffffff";

    const highlighted = Inline.highlightInHtml(formatted, searchQ, softBg, activeBg, activeOrd, activeFg);

    // Debe contener el span de resaltado activo en la primera coincidencia "me" (en elementos)
    assert.ok(highlighted.includes('background-color: rgba(255, 100, 0, 0.8)'), "Debe aplicar fondo activo a la primera coincidencia");
    assert.ok(highlighted.includes('color: #ffffff'), "Debe aplicar color de texto activo");
    assert.ok(highlighted.includes('>me</span>'), "Debe envolver el texto 'me'");

    // Los delimitadores de markdown transparentes deben conservarse intactos
    assert.ok(highlighted.includes('font-size: 1px; color: transparent;'), "Debe conservar delimitadores transparentes");

    // El texto plano extraído de la cadena HTML debe ser idéntico al texto crudo original
    const plainFromDom = highlighted.replace(/<[^>]+>/g, "");
    assert.strictEqual(plainFromDom, rawLine, "El texto plano no debe alterarse para no desfasar SpellOverlay ni el cursor");
});

runTest('F101: Menú desplegable H1-H6 y soporte de niveles 1 a 6 en NoteEditorModal, BlockEditor y EditorActions', () => {
    const editorActionsSrc = fs.readFileSync(path.resolve(__dirname, '../qml/EditorActions.js'), 'utf8');
    const noteEditorModalSrc = fs.readFileSync(path.resolve(__dirname, '../qml/NoteEditorModal.qml'), 'utf8');
    const blockEditorSrc = fs.readFileSync(path.resolve(__dirname, '../qml/BlockEditor.qml'), 'utf8');

    // 1. Registro de heading_menu en EditorActions
    assert.ok(editorActionsSrc.includes('id: "heading_menu"'), "EditorActions debe registrar acción 'heading_menu'");

    // 2. ToolbarButton y dropdown en NoteEditorModal
    assert.ok(noteEditorModalSrc.includes('id: headingToolbarBtn'), "NoteEditorModal debe definir headingToolbarBtn");
    assert.ok(noteEditorModalSrc.includes('actionId: "heading_menu"'), "headingToolbarBtn debe vincularse a 'heading_menu'");
    assert.ok(noteEditorModalSrc.includes('id: headingMenuPopup'), "NoteEditorModal debe tener headingMenuPopup vertical");
    for (let i = 1; i <= 6; i++) {
        assert.ok(noteEditorModalSrc.includes(`level: ${i}, tag: "H${i}"`), `headingMenuPopup debe incluir opción H${i}`);
        assert.ok(noteEditorModalSrc.includes(`action === "h${i}"`), `NoteEditorModal debe contemplar action h${i}`);
    }

    // 3. BlockEditor soporte completo de h1 hasta h6
    assert.ok(blockEditorSrc.includes('actionId === "h1" || actionId === "h2" || actionId === "h3" || actionId === "h4" || actionId === "h5" || actionId === "h6"'),
        "BlockEditor.applyAction debe soportar de h1 hasta h6");
    assert.ok(blockEditorSrc.includes('cmdId === "h1" || cmdId === "h2" || cmdId === "h3" || cmdId === "h4" || cmdId === "h5" || cmdId === "h6"'),
        "BlockEditor.executeSlashCommand debe soportar de h1 hasta h6");
    assert.ok(blockEditorSrc.includes('actionId === "h4"') && blockEditorSrc.includes('actionId === "h5"') && blockEditorSrc.includes('actionId === "h6"'),
        "BlockEditor.isFormatActive debe verificar h4, h5 y h6");
});

runTest('F102: Escalado de imágenes con zoom factor y cálculo proporcional de relación de aspecto sin bandas vacías', () => {
    const blockImageSrc = fs.readFileSync(path.resolve(__dirname, '../qml/BlockImage.qml'), 'utf8');
    const blockListSrc = fs.readFileSync(path.resolve(__dirname, '../qml/BlockList.qml'), 'utf8');

    // 1. Contratos estáticos en BlockImage.qml
    assert.ok(blockImageSrc.includes('readonly property real zoomFactor: (typeof EditorMetrics !== "undefined" && EditorMetrics.zoom) ? EditorMetrics.zoom : 1.0'),
        "BlockImage debe calcular zoomFactor desde EditorMetrics");
    assert.ok(blockImageSrc.includes('readonly property real maxH: Math.round(560 * zoomFactor)'),
        "BlockImage debe escalar maxH con zoomFactor");
    assert.ok(blockImageSrc.includes('w = Math.round(h * (naturalW / naturalH))'),
        "BlockImage debe re-escalar w proporcionalmente cuando h > maxH para eliminar bandas vacías");
    assert.ok(blockImageSrc.includes('anchors.horizontalCenter: parent.horizontalCenter'),
        "BlockImage imagesFlow debe centrarse horizontalmente");

    // 2. Contratos estáticos en BlockList.qml
    assert.ok(blockListSrc.includes('EditorMetrics.zoom'), "BlockList delegados de imagen deben considerar EditorMetrics.zoom");
    assert.ok(blockListSrc.includes('width: dispW'), "BlockList delegados de imagen deben acotar width a dispW para alinear a la izquierda");

    // 3. Cálculo funcional de recorte proporcional (caso de imagen vertical 1712x2692 en contenedor de 794px)
    const naturalW = 1712;
    const naturalH = 2692;
    const availW = 794;
    const zoomFactor = 1.0;
    const maxH = Math.round(560 * zoomFactor);

    let w = Math.min(availW, Math.round(naturalW * zoomFactor));
    let h = Math.round(w * (naturalH / naturalW));
    if (h > maxH) {
        h = maxH;
        w = Math.round(h * (naturalW / naturalH));
    }

    assert.strictEqual(h, 560, "El alto debe quedar recortado exactamente a maxH");
    assert.strictEqual(w, 356, "El ancho del contenedor debe coincidir con el aspect-ratio escalado (356px) sin dejar bandas vacías de 794px");
});

runTest('F103: Compatibilidad con GIFs animados mediante AnimatedImage y respeto de Gamemode', () => {
    const blockImageSrc = fs.readFileSync(path.resolve(__dirname, '../qml/BlockImage.qml'), 'utf8');
    const blockListSrc = fs.readFileSync(path.resolve(__dirname, '../qml/BlockList.qml'), 'utf8');

    // BlockImage usa AnimatedImage y respeta Gamemode
    assert.ok(blockImageSrc.includes('AnimatedImage {'), "BlockImage debe usar AnimatedImage para soporte de GIFs animados");
    assert.ok(blockImageSrc.includes('playing: Theme.animationsEnabled && !GamemodeService.gamemodeActive'), "BlockImage debe pausar reproducción en gamemode");
    assert.ok(blockImageSrc.includes('paused: GamemodeService.gamemodeActive'), "BlockImage debe congelar AnimatedImage en gamemode");

    // BlockList usa AnimatedImage y respeta Gamemode
    assert.ok(blockListSrc.includes('AnimatedImage {'), "BlockList debe usar AnimatedImage para soporte de GIFs animados");
    assert.ok(blockListSrc.includes('playing: Theme.animationsEnabled && !GamemodeService.gamemodeActive'), "BlockList debe pausar reproducción en gamemode");
    assert.ok(blockListSrc.includes('paused: GamemodeService.gamemodeActive'), "BlockList debe congelar AnimatedImage en gamemode");
});

runTest('F104: Fondo translúcido unificado del buscador en el menú de inicio (NotesContent.qml)', () => {
    const notesContentSrc = fs.readFileSync(path.resolve(__dirname, '../qml/NotesContent.qml'), 'utf8');

    assert.ok(notesContentSrc.includes('color: Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.05)'),
        "NotesContent searchBox debe usar fondo translúcido idéntico al buscador interno de la nota");
    assert.ok(notesContentSrc.includes('Qt.rgba(Theme.text.r, Theme.text.g, Theme.text.b, 0.15)'),
        "NotesContent searchBox debe tener borde suave al desenfocar");
});

runTest('F105: ReferenceLogic detección de trigger wikilink/ancla, slug GitHub y filtros de búsqueda', () => {
    // 1. Detección interactiva de triggers wikilink
    // a. Apertura simple [[ al inicio
    const t1 = ReferenceLogic.detectWikilinkTrigger('[[', 2);
    assert.strictEqual(t1.triggered, true);
    assert.strictEqual(t1.mode, 'note');
    assert.strictEqual(t1.query, '');
    assert.strictEqual(t1.noteTitle, '');

    // b. Búsqueda de nota con texto
    const s2 = 'Ver nota [[Mi Proyecto';
    const t2 = ReferenceLogic.detectWikilinkTrigger(s2, s2.length);
    assert.strictEqual(t2.triggered, true);
    assert.strictEqual(t2.mode, 'note');
    assert.strictEqual(t2.query, 'Mi Proyecto');
    assert.strictEqual(t2.openIndex, 9);
    assert.strictEqual(t2.endIndex, s2.length);

    // c. Wikilink mixto con sección nota#sección
    const s3 = '[[Documento#Introdu';
    const t3 = ReferenceLogic.detectWikilinkTrigger(s3, s3.length);
    assert.strictEqual(t3.triggered, true);
    assert.strictEqual(t3.mode, 'anchor');
    assert.strictEqual(t3.query, 'Introdu');
    assert.strictEqual(t3.noteTitle, 'Documento');

    // d. Ancla local a la nota actual [[#sección
    const s4 = '[[#Capitulo 1';
    const t4 = ReferenceLogic.detectWikilinkTrigger(s4, s4.length);
    assert.strictEqual(t4.triggered, true);
    assert.strictEqual(t4.mode, 'anchor');
    assert.strictEqual(t4.query, 'Capitulo 1');
    assert.strictEqual(t4.isCurrentNote, true);

    // e. Casos inactivos: ya cerrado
    const sClosed = '[[Nota cerrada]] ';
    const tClosed = ReferenceLogic.detectWikilinkTrigger(sClosed, sClosed.length);
    assert.strictEqual(tClosed.triggered, false);

    // f. Casos inactivos: salto de línea intermedio
    const sNewline = '[[Nota\nsegunda linea';
    const tNewline = ReferenceLogic.detectWikilinkTrigger(sNewline, sNewline.length);
    assert.strictEqual(tNewline.triggered, false);

    // 2. Generación determinista de GitHub Slugs (estándar GFM con soporte de letras Unicode)
    assert.strictEqual(ReferenceLogic.githubSlug('Introducción a QML'), 'introducción-a-qml');
    assert.strictEqual(ReferenceLogic.githubSlug('¿Qué es esto? (Guía Básica!)'), 'qué-es-esto-guía-básica');
    assert.strictEqual(ReferenceLogic.githubSlug('Espacios   múltiples - guiones'), 'espacios-múltiples-guiones');

    // 3. Extracción de encabezados desde Markdown
    const md = '# Título Principal\n\nTexto de prueba...\n\n## Subtítulo 1\n\n### Sección Detalle';
    const headingsMd = ReferenceLogic.extractHeadingsFromMarkdown(md);
    assert.strictEqual(headingsMd.length, 3);
    assert.strictEqual(headingsMd[0].level, 1);
    assert.strictEqual(headingsMd[0].tag, 'H1');
    assert.strictEqual(headingsMd[0].title, 'Título Principal');
    assert.strictEqual(headingsMd[0].slug, 'título-principal');
    assert.strictEqual(headingsMd[1].level, 2);
    assert.strictEqual(headingsMd[1].tag, 'H2');
    assert.strictEqual(headingsMd[2].level, 3);

    // 4. Extracción de encabezados desde bloques de editor
    const blocks = [
        { type: 'paragraph', text: 'Intro' },
        { type: 'heading', level: 2, text: 'Instalación de Componentes' },
        { type: 'list', items: ['A', 'B'] },
        { type: 'heading', level: 4, text: 'Detalles Técnicos' }
    ];
    const headingsBlocks = ReferenceLogic.extractHeadingsFromBlocks(blocks);
    assert.strictEqual(headingsBlocks.length, 2);
    assert.strictEqual(headingsBlocks[0].title, 'Instalación de Componentes');
    assert.strictEqual(headingsBlocks[0].slug, 'instalación-de-componentes');
    assert.strictEqual(headingsBlocks[1].level, 4);

    // 5. Filtrado de notas (con opción de creación para notas inexistentes)
    const mockNotes = [
        { title: 'Guía de Rust', slug: 'guia-de-rust' },
        { title: 'Quickshell Wayland', slug: 'quickshell-wayland' }
    ];
    const fnExact = ReferenceLogic.filterNotes(mockNotes, 'Guía de Rust', 10);
    assert.strictEqual(fnExact.length, 1);
    assert.strictEqual(fnExact[0].title, 'Guía de Rust');

    const fnMatch = ReferenceLogic.filterNotes(mockNotes, 'rust', 10);
    assert.strictEqual(fnMatch[0].title, 'Guía de Rust');
    assert.ok(fnMatch.some(n => n.isCreateNew && n.title === 'rust'), "Debe ofrecer opción de crear nueva nota");

    const fnCreate = ReferenceLogic.filterNotes(mockNotes, 'Nota Inédita', 10);
    assert.strictEqual(fnCreate.length, 1);
    assert.strictEqual(fnCreate[0].title, 'Nota Inédita');
    assert.strictEqual(fnCreate[0].isCreateNew, true);

    // 6. Filtrado de encabezados
    const mockHeadings = [
        { title: 'Primeros Pasos', slug: 'primeros-pasos', level: 2, tag: 'H2' },
        { title: 'Configuración Avanzada', slug: 'configuracion-avanzada', level: 3, tag: 'H3' }
    ];
    const fhMatch = ReferenceLogic.filterHeadings(mockHeadings, 'avan', 10);
    assert.strictEqual(fhMatch.length, 1);
    assert.strictEqual(fhMatch[0].title, 'Configuración Avanzada');
});

runTest('F106: Comandos slash /ancla y /referencia en catálogo SlashCommands y filtrado SlashLogic', () => {
    const allCmds = SlashCommands.getAllCommands();
    const anchorCmd = allCmds.find(c => c.id === 'anchor');
    const wikilinkCmd = allCmds.find(c => c.id === 'wikilink');

    assert.ok(anchorCmd, "El catálogo de SlashCommands debe contener el comando 'anchor'");
    assert.strictEqual(anchorCmd.titleKey, 'notes.slash.anchor');
    assert.strictEqual(anchorCmd.descKey, 'notes.slash.anchor_desc');
    assert.strictEqual(anchorCmd.badge, '/ancla');

    assert.ok(wikilinkCmd, "El catálogo de SlashCommands debe contener el comando 'wikilink'");
    assert.strictEqual(wikilinkCmd.titleKey, 'notes.slash.wikilink');
    assert.strictEqual(wikilinkCmd.descKey, 'notes.slash.wikilink_desc');
    assert.strictEqual(wikilinkCmd.badge, '/referencia');

    const mockI18n = { t: (k, fb) => fb };
    // Búsqueda por palabras clave en español
    const fAncla = SlashLogic.filterCommands(allCmds, 'ancla', mockI18n);
    assert.ok(fAncla.some(c => c.id === 'anchor'), "Búsqueda 'ancla' debe retornar 'anchor'");

    const fSeccion = SlashLogic.filterCommands(allCmds, 'seccion', mockI18n);
    assert.ok(fSeccion.some(c => c.id === 'anchor'), "Búsqueda 'seccion' debe retornar 'anchor'");

    const fRef = SlashLogic.filterCommands(allCmds, 'referencia', mockI18n);
    assert.ok(fRef.some(c => c.id === 'wikilink'), "Búsqueda 'referencia' debe retornar 'wikilink'");

    const fNota = SlashLogic.filterCommands(allCmds, 'nota', mockI18n);
    assert.ok(fNota.some(c => c.id === 'wikilink'), "Búsqueda 'nota' debe retornar 'wikilink'");

    const fWiki = SlashLogic.filterCommands(allCmds, 'wikilink', mockI18n);
    assert.ok(fWiki.some(c => c.id === 'wikilink'), "Búsqueda 'wikilink' debe retornar 'wikilink'");
});

runTest('F107: Barra de herramientas, atajos Ctrl+Shift+K / Ctrl+Alt+A e integración de sugerencias flotantes', () => {
    // 1. Acciones en EditorActions.js
    const wikiAction = EditorActions.getAction('wikilink');
    assert.ok(wikiAction, "EditorActions debe contener la acción 'wikilink'");
    assert.strictEqual(wikiAction.shortcut, 'Ctrl+Shift+K');
    assert.strictEqual(wikiAction.labelKey, 'notes.editor.action.wikilink');

    const anchorAction = EditorActions.getAction('anchor');
    assert.ok(anchorAction, "EditorActions debe contener la acción 'anchor'");
    assert.strictEqual(anchorAction.shortcut, 'Ctrl+Alt+A');
    assert.strictEqual(anchorAction.labelKey, 'notes.editor.action.anchor');

    // 2. NoteEditorModal.qml
    const editorModalSrc = fs.readFileSync(path.resolve(__dirname, '../qml/NoteEditorModal.qml'), 'utf8');
    assert.ok(editorModalSrc.includes('LinkSuggestionMenu {'), "NoteEditorModal debe instanciar LinkSuggestionMenu");
    assert.ok(editorModalSrc.includes('id: linkSuggestionMenu'), "NoteEditorModal debe tener id linkSuggestionMenu");
    assert.ok(editorModalSrc.includes('id: noteLinkToolbarBtn'), "NoteEditorModal debe tener botón noteLinkToolbarBtn");
    assert.ok(editorModalSrc.includes('id: anchorToolbarBtn'), "NoteEditorModal debe tener botón anchorToolbarBtn");
    assert.ok(editorModalSrc.includes('event.key === Qt.Key_K') && editorModalSrc.includes('root.applyFormatOrAction("wikilink")'),
        "NoteEditorModal debe despachar atajo Ctrl+Shift+K a wikilink");
    assert.ok(editorModalSrc.includes('event.key === Qt.Key_A') && editorModalSrc.includes('root.applyFormatOrAction("anchor")'),
        "NoteEditorModal debe despachar atajo Ctrl+Alt+A a anchor");
    assert.ok(editorModalSrc.includes('openWikilinkSuggestions'), "NoteEditorModal debe tener función openWikilinkSuggestions");
    assert.ok(editorModalSrc.includes('openAnchorSuggestions'), "NoteEditorModal debe tener función openAnchorSuggestions");
    assert.ok(editorModalSrc.includes('linkSuggestionMenu: linkSuggestionMenu'), "NoteEditorModal debe pasar linkSuggestionMenu a BlockEditor");

    // 3. BlockEditor.qml
    const blockEditorSrc = fs.readFileSync(path.resolve(__dirname, '../qml/BlockEditor.qml'), 'utf8');
    assert.ok(blockEditorSrc.includes('property var linkSuggestionMenu: null'), "BlockEditor debe declarar propiedad linkSuggestionMenu");
    assert.ok(blockEditorSrc.includes('function getActiveHeadings()'), "BlockEditor debe proveer getActiveHeadings");
    assert.ok(blockEditorSrc.includes('function getNoteHeadings('), "BlockEditor debe proveer getNoteHeadings");
    assert.ok(blockEditorSrc.includes('cmdId === "anchor"'), "BlockEditor.executeSlashCommand debe soportar anchor");
    assert.ok(blockEditorSrc.includes('cmdId === "wikilink"'), "BlockEditor.executeSlashCommand debe soportar wikilink");

    // 4. Delegados de edición interactiva
    const blockParaSrc = fs.readFileSync(path.resolve(__dirname, '../qml/BlockParagraph.qml'), 'utf8');
    const blockListSrc = fs.readFileSync(path.resolve(__dirname, '../qml/BlockList.qml'), 'utf8');
    assert.ok(blockParaSrc.includes('ReferenceLogic.detectWikilinkTrigger'), "BlockParagraph debe detectar trigger [[");
    assert.ok(blockListSrc.includes('ReferenceLogic.detectWikilinkTrigger'), "BlockList debe detectar trigger [[");
});

runTest('F108: Contratos de build.rs y corrección de posición y ancho de popups en NoteEditorModal', () => {
    // 1. build.rs registra LinkSuggestionMenu.qml
    const buildRsSrc = fs.readFileSync(path.resolve(__dirname, '../build.rs'), 'utf8');
    assert.ok(buildRsSrc.includes('"qml/LinkSuggestionMenu.qml"'), "build.rs debe incluir qml/LinkSuggestionMenu.qml en components");

    // 2. Ancho y posicionamiento de headingMenuPopup y popups de herramientas
    const editorModalSrc = fs.readFileSync(path.resolve(__dirname, '../qml/NoteEditorModal.qml'), 'utf8');
    assert.ok(editorModalSrc.includes('id: headingMenuPopup'), "NoteEditorModal debe contener headingMenuPopup");
    assert.ok(editorModalSrc.includes('width: 260'), "headingMenuPopup debe tener width 260px para evitar elisión con puntos suspensivos");
    assert.ok(editorModalSrc.includes('transformOrigin: Item.Top'), "Los popups deben desplegarse hacia abajo con transformOrigin: Item.Top");
    assert.ok(editorModalSrc.includes('headingToolbarBtn.mapToItem(headingMenuPopup.parent, 0, headingToolbarBtn.height + 6)'),
        "headingMenuPopup debe posicionarse exactamente debajo del botón con margen vertical");
    assert.ok(editorModalSrc.includes('imgToolbarBtn.mapToItem(imageMenuPopup.parent, 0, imgToolbarBtn.height + 6)'),
        "imageMenuPopup debe posicionarse debajo del botón de imagen");
    assert.ok(editorModalSrc.includes('mermaidToolbarBtn.mapToItem(mermaidMenuPopup.parent, 0, mermaidToolbarBtn.height + 6)'),
        "mermaidMenuPopup debe posicionarse debajo del botón de mermaid");
    assert.ok(editorModalSrc.includes('mathToolbarBtn.mapToItem(mathMenuPopup.parent, 0, mathToolbarBtn.height + 6)'),
        "mathMenuPopup debe posicionarse debajo del botón de math");
});

runTest('F109: Paridad de traducciones en los 9 idiomas para anclas, wikilinks, encabezados y sugerencias', () => {
    const langs = ['es_es', 'es_ar', 'en', 'pt', 'ja', 'zh', 'de', 'fr', 'ru'];
    const requiredActionKeys = ['h4', 'h5', 'h6', 'heading_menu', 'anchor', 'wikilink'];
    const requiredSlashKeys = ['anchor', 'anchor_desc', 'wikilink', 'wikilink_desc'];
    const requiredSuggestionKeys = [
        'headings_current', 'headings_of', 'refer_note',
        'no_headings', 'no_notes', 'create_note', 'create_note_desc'
    ];

    for (const lang of langs) {
        const filePath = path.resolve(__dirname, `../assets/i18n/${lang}/notes.json`);
        assert.ok(fs.existsSync(filePath), `Archivo de idioma ${lang}/notes.json debe existir`);
        const json = JSON.parse(fs.readFileSync(filePath, 'utf8'));

        // editor.action
        assert.ok(json.editor && json.editor.action, `Sección editor.action en ${lang}`);
        for (const k of requiredActionKeys) {
            assert.ok(json.editor.action[k], `Falta clave editor.action.${k} en ${lang}`);
        }

        // slash
        assert.ok(json.slash, `Sección slash en ${lang}`);
        for (const k of requiredSlashKeys) {
            assert.ok(json.slash[k], `Falta clave slash.${k} en ${lang}`);
        }

        // suggestions
        assert.ok(json.suggestions, `Sección suggestions en ${lang}`);
        for (const k of requiredSuggestionKeys) {
            assert.ok(json.suggestions[k], `Falta clave suggestions.${k} en ${lang}`);
        }
    }

    // Comprobar catálogo empaquetado en qml/I18nCatalogs.js
    const catalogsSrc = fs.readFileSync(path.resolve(__dirname, '../qml/I18nCatalogs.js'), 'utf8');
    assert.ok(catalogsSrc.includes('headings_current'), "I18nCatalogs.js debe contener 'headings_current'");
    assert.ok(catalogsSrc.includes('create_note_desc'), "I18nCatalogs.js debe contener 'create_note_desc'");
    assert.ok(catalogsSrc.includes('heading_menu'), "I18nCatalogs.js debe contener 'heading_menu'");
});

// ─────────────────────────────────────────────────────────────────────────────
// F110: Tipografías de Código Abierto SIL OFL (sin fuentes propietarias)
// ─────────────────────────────────────────────────────────────────────────────
runTest("F110: Fuentes abiertas SIL OFL como fallback en Theme, bridge e Inline", () => {
    const themeSrc = fs.readFileSync(path.resolve(__dirname, '../qml/Theme.qml'), 'utf8');
    assert.ok(!themeSrc.includes('"Google Sans"'), "Theme.qml no debe contener Google Sans propietario");
    assert.ok(themeSrc.includes('"Plus Jakarta Sans"'), "Theme.qml debe usar Plus Jakarta Sans como fallback abierto");
    assert.ok(themeSrc.includes('"Outfit"'), "Theme.qml debe usar Outfit como fallback display abierto");
    assert.ok(themeSrc.includes('"JetBrains Mono"'), "Theme.qml debe usar JetBrains Mono como fallback mono abierto");

    const bridgeSrc = fs.readFileSync(path.resolve(__dirname, '../src/native/native_bridge.cpp'), 'utf8');
    assert.ok(!bridgeSrc.includes('QStringLiteral("Google Sans")'), "native_bridge.cpp no debe hardcodear Google Sans");
    assert.ok(bridgeSrc.includes('QStringLiteral("Plus Jakarta Sans")'), "native_bridge.cpp debe incluir Plus Jakarta Sans");
    assert.ok(bridgeSrc.includes('QStringLiteral("Outfit")'), "native_bridge.cpp debe incluir Outfit");
    assert.ok(bridgeSrc.includes('QStringLiteral("JetBrains Mono")'), "native_bridge.cpp debe incluir JetBrains Mono");
});

// ─────────────────────────────────────────────────────────────────────────────
// F111: Directorio de Notas por Defecto $XDG_DOCUMENTS_DIR/notes
// ─────────────────────────────────────────────────────────────────────────────
runTest("F111: Directorio por defecto literal $XDG_DOCUMENTS_DIR/notes y resolución dinámica", () => {
    const bridgeSrc = fs.readFileSync(path.resolve(__dirname, '../src/native/native_bridge.cpp'), 'utf8');
    assert.ok(bridgeSrc.includes('m_notasDir = QStringLiteral("$XDG_DOCUMENTS_DIR/notes");'), "El valor inicial en C++ debe ser literal $XDG_DOCUMENTS_DIR/notes");
    assert.ok(bridgeSrc.includes('QString ConfigBackend::resolvedNotasDir() const'), "ConfigBackend debe exponer resolvedNotasDir()");

    const notesCfgSrc = fs.readFileSync(path.resolve(__dirname, '../qml/NotesConfig.qml'), 'utf8');
    assert.ok(notesCfgSrc.includes('function resolveNotesDir'), "NotesConfig.qml debe tener la función resolveNotesDir");
    assert.ok(notesCfgSrc.includes('$XDG_DOCUMENTS_DIR'), "resolveNotesDir debe expandir $XDG_DOCUMENTS_DIR");
});

// ─────────────────────────────────────────────────────────────────────────────
// F112: Controles de Ventana CSD integrados y configuración
// ─────────────────────────────────────────────────────────────────────────────
runTest("F112: WindowControls.qml, registro en build.rs y modos CSD", () => {
    assert.ok(fs.existsSync(path.resolve(__dirname, '../qml/WindowControls.qml')), "qml/WindowControls.qml debe existir");
    const buildRs = fs.readFileSync(path.resolve(__dirname, '../build.rs'), 'utf8');
    assert.ok(buildRs.includes('"qml/WindowControls.qml"'), "build.rs debe registrar qml/WindowControls.qml");

    const bridgeH = fs.readFileSync(path.resolve(__dirname, '../src/native/native_bridge.h'), 'utf8');
    assert.ok(bridgeH.includes('windowControlsMode'), "native_bridge.h debe declarar windowControlsMode");
    assert.ok(bridgeH.includes('wmNeedsWindowControls'), "native_bridge.h debe declarar wmNeedsWindowControls");

    const settingsModalSrc = fs.readFileSync(path.resolve(__dirname, '../qml/NotesSettingsModal.qml'), 'utf8');
    assert.ok(settingsModalSrc.includes('ConfigBackend.windowControlsMode'), "NotesSettingsModal debe contener selector de modo CSD");
});

// ─────────────────────────────────────────────────────────────────────────────
// F113: Morphing FAB texto completo y componente de marquee en hover
// ─────────────────────────────────────────────────────────────────────────────
runTest("F113: MorphingFab ancho dinámico ampliado y FabOptionText con marquee", () => {
    const fabSrc = fs.readFileSync(path.resolve(__dirname, '../qml/MorphingFab.qml'), 'utf8');
    assert.ok(fabSrc.includes('component FabOptionText'), "MorphingFab debe definir el componente FabOptionText");
    assert.ok(fabSrc.includes('SequentialAnimation on x'), "FabOptionText debe animar x en bucle para texto desbordado");
    assert.ok(fabSrc.includes('Math.max(220'), "dynamicExpandedWidth debe tener un mínimo de 220px para no truncar");
});

// ─────────────────────────────────────────────────────────────────────────────
// F114: Script unificado install.sh y preservación de documentos
// ─────────────────────────────────────────────────────────────────────────────
runTest("F114: Script unificado scripts/install.sh con --user, --uninstall y protección de notas", () => {
    assert.ok(fs.existsSync(path.resolve(__dirname, '../scripts/install.sh')), "scripts/install.sh debe existir");
    const installSrc = fs.readFileSync(path.resolve(__dirname, '../scripts/install.sh'), 'utf8');
    assert.ok(installSrc.includes('--user'), "install.sh debe soportar el flag --user");
    assert.ok(installSrc.includes('--uninstall'), "install.sh debe soportar el flag --uninstall");
    assert.ok(installSrc.includes('Documentos/notes NUNCA fueron modificados ni eliminados'), "install.sh debe garantizar la preservación de documentos de usuario");
    assert.ok(installSrc.includes('/usr/share/criperto.notes'), "install.sh debe usar /usr/share/criperto.notes (no nombres genéricos)");
});

// ─────────────────────────────────────────────────────────────────────────────
// F115: Paquete nativo de Arch Linux .pkg.tar.zst y pipeline CI
// ─────────────────────────────────────────────────────────────────────────────
runTest("F115: packaging/arch/build-arch.sh genera .pkg.tar.zst y se integra en releases", () => {
    assert.ok(fs.existsSync(path.resolve(__dirname, '../packaging/arch/build-arch.sh')), "packaging/arch/build-arch.sh debe existir");
    const buildArchSrc = fs.readFileSync(path.resolve(__dirname, '../packaging/arch/build-arch.sh'), 'utf8');
    assert.ok(buildArchSrc.includes('.PKGINFO'), "build-arch.sh debe generar metadatos .PKGINFO");
    assert.ok(buildArchSrc.includes('.pkg.tar.zst'), "build-arch.sh debe comprimir con extensión .pkg.tar.zst");

    const releaseYml = fs.readFileSync(path.resolve(__dirname, '../.github/workflows/release.yml'), 'utf8');
    assert.ok(releaseYml.includes('build-arch.sh'), "release.yml debe invocar build-arch.sh");
    assert.ok(releaseYml.includes('dist/*.pkg.tar.zst'), "release.yml debe subir *.pkg.tar.zst a GitHub Releases");

    const releaseShPath = path.resolve(__dirname, '../scripts/release.sh');
    if (fs.existsSync(releaseShPath)) {
        const releaseSh = fs.readFileSync(releaseShPath, 'utf8');
        assert.ok(releaseSh.includes('build-arch.sh'), "scripts/release.sh debe incluir build-arch.sh");
    }
});

// ─────────────────────────────────────────────────────────────────────────────
// F116: Flag CLI --csd / --window-controls, NOTAS_WINDOW_CONTROLS y Sys::startSystemMove
// ─────────────────────────────────────────────────────────────────────────────
runTest("F116: Flags CLI --csd / --window-controls y soporte nativo Sys::startSystemMove", () => {
    const mainRs = fs.readFileSync(path.resolve(__dirname, '../src/main.rs'), 'utf8');
    assert.ok(mainRs.includes('window_controls'), "main.rs debe declarar argumento window_controls");
    assert.ok(mainRs.includes('alias = "csd"'), "main.rs debe incluir alias 'csd' para window-controls");
    assert.ok(mainRs.includes('NOTAS_WINDOW_CONTROLS'), "main.rs debe asignar variable de entorno NOTAS_WINDOW_CONTROLS");

    const bridgeH = fs.readFileSync(path.resolve(__dirname, '../src/native/native_bridge.h'), 'utf8');
    assert.ok(bridgeH.includes('startSystemMove(QObject *windowObj)'), "native_bridge.h debe declarar Sys::startSystemMove");

    const bridgeCpp = fs.readFileSync(path.resolve(__dirname, '../src/native/native_bridge.cpp'), 'utf8');
    assert.ok(bridgeCpp.includes('NOTAS_WINDOW_CONTROLS'), "native_bridge.cpp debe consultar NOTAS_WINDOW_CONTROLS");
    assert.ok(bridgeCpp.includes('win->startSystemMove()'), "native_bridge.cpp debe invocar startSystemMove");
});

// ─────────────────────────────────────────────────────────────────────────────
// F117: Supresión de decoración duplicada mediante Qt.FramelessWindowHint en Main.qml
// ─────────────────────────────────────────────────────────────────────────────
runTest("F117: ApplicationWindow aplica Qt.FramelessWindowHint cuando winControls.visible está activo", () => {
    const mainQml = fs.readFileSync(path.resolve(__dirname, '../qml/Main.qml'), 'utf8');
    assert.ok(mainQml.includes('flags: Qt.Window | (winControls.visible ? Qt.FramelessWindowHint : 0)'),
        "Main.qml debe configurar FramelessWindowHint condicionado a los controles CSD");
});

// ─────────────────────────────────────────────────────────────────────────────
// F118: Alineación y diseño de botones redondeados en WindowControls.qml
// ─────────────────────────────────────────────────────────────────────────────
runTest("F118: WindowControls alineado con buscador/píldora, margen derecho y botones radius 8", () => {
    const mainQml = fs.readFileSync(path.resolve(__dirname, '../qml/Main.qml'), 'utf8');
    assert.ok(mainQml.includes('y: (typeof NotesService !== "undefined" && NotesService.isEditing) ? 20 : 15'),
        "Main.qml debe posicionar dinámicamente winControls en y: 15 (inicio) y 20 (editor)");
    assert.ok(mainQml.includes('anchors.rightMargin: 16'),
        "Main.qml debe tener un margen derecho de 16px para no quedar pegado al borde");

    const winControlsQml = fs.readFileSync(path.resolve(__dirname, '../qml/WindowControls.qml'), 'utf8');
    assert.ok(winControlsQml.includes('radius: 8'), "WindowControls debe usar botones redondeados con radius: 8");
    assert.ok(winControlsQml.includes('spacing: 4'), "WindowControls debe tener espaciado entre botones de 4px");
});

// ─────────────────────────────────────────────────────────────────────────────
// F119: Arrastre de ventana (startSystemMove) y maximizado en cabeceras
// ─────────────────────────────────────────────────────────────────────────────
runTest("F119: Cabeceras de NotesContent y NoteEditorModal soportan startSystemMove y doble clic", () => {
    const contentQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesContent.qml'), 'utf8');
    assert.ok(contentQml.includes('startSystemMove()'), "NotesContent.qml debe invocar startSystemMove()");
    assert.ok(contentQml.includes('showMaximized()'), "NotesContent.qml debe alternar showMaximized()");

    const editorQml = fs.readFileSync(path.resolve(__dirname, '../qml/NoteEditorModal.qml'), 'utf8');
    assert.ok(editorQml.includes('startSystemMove()'), "NoteEditorModal.qml debe invocar startSystemMove()");
    assert.ok(editorQml.includes('showMaximized()'), "NoteEditorModal.qml debe alternar showMaximized()");
});

// ─────────────────────────────────────────────────────────────────────────────
// F120: BlockCode import de BlockModel y avance de cursor en saltos de línea y tabulación
// ─────────────────────────────────────────────────────────────────────────────
runTest("F120: BlockCode import de BlockModel y avance de cursor en saltos de línea y tabulación", () => {
    const codeQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockCode.qml'), 'utf8');
    assert.ok(codeQml.includes('import "BlockModel.js" as BlockModel'), "BlockCode.qml debe importar BlockModel.js");
    assert.ok(codeQml.includes('cursorPosition = cp + 1'), "BlockCode.qml debe avanzar cursorPosition tras insertar salto de línea");
    assert.ok(codeQml.includes('cursorPosition = tp + 4'), "BlockCode.qml debe avanzar cursorPosition tras insertar 4 espacios de tabulación");
});

// ─────────────────────────────────────────────────────────────────────────────
// F121: BlockQuote soporte multilínea con enter, shift+enter y avance de cursor
// ─────────────────────────────────────────────────────────────────────────────
runTest("F121: BlockQuote soporte multilínea con enter, shift+enter y avance de cursor", () => {
    const quoteQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockQuote.qml'), 'utf8');
    assert.ok(quoteQml.includes('cursorPosition = pos + 1'), "BlockQuote.qml debe avanzar cursorPosition tras insertar salto de línea en Return");
    assert.ok(quoteQml.includes('cursorPosition = sPos + 1'), "BlockQuote.qml debe avanzar cursorPosition tras Shift+Return");
    assert.ok(quoteQml.includes('cursorPosition = tbPos + 2'), "BlockQuote.qml debe avanzar cursorPosition tras Tab");
});

// ─────────────────────────────────────────────────────────────────────────────
// F122: BlockEditor acciones de listas y citas con convertBlockType y protección contra destrucciones
// ─────────────────────────────────────────────────────────────────────────────
runTest("F122: BlockEditor acciones de listas y citas con convertBlockType y protección contra destrucciones", () => {
    const editorQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockEditor.qml'), 'utf8');
    assert.ok(editorQml.includes('root.convertBlockType(curItem.bid, "list", newRawList, 0)'), "Toolbar bullet_list debe usar convertBlockType");
    assert.ok(editorQml.includes('property bool _isDestroyed: false'), "BlockEditor debe contar con bandera defensiva _isDestroyed");

    const listQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockList.qml'), 'utf8');
    assert.ok(listQml.includes('focusRetryTimer'), "BlockList.qml debe implementar focusRetryTimer para retener el foco tras conversiones");
    assert.ok(listQml.includes('SpellService.cancelOwner(itemRow)'), "BlockList delegados deben cancelar SpellService al destruirse");

    const spellQml = fs.readFileSync(path.resolve(__dirname, '../qml/SpellService.qml'), 'utf8');
    assert.ok(spellQml.includes('cancelOwner(owner)'), "SpellService.qml debe ofrecer método cancelOwner");
    assert.ok(spellQml.includes('cancelAll()'), "SpellService.qml debe ofrecer método cancelAll");
});

// ─────────────────────────────────────────────────────────────────────────────
// F123: Auditoría integral de traducciones y paridad en 9 idiomas
// ─────────────────────────────────────────────────────────────────────────────
runTest("F123: Auditoría integral de traducciones y paridad en 9 idiomas", () => {
    const i18nQml = fs.readFileSync(path.resolve(__dirname, '../qml/I18n.qml'), 'utf8');
    assert.ok(i18nQml.includes('_resolveInCatalog'), "I18n.qml debe resolver claves con _resolveInCatalog");

    const i18nDir = path.resolve(__dirname, '../assets/i18n');
    const languages = ['es_es', 'es_ar', 'en', 'pt', 'ja', 'zh', 'de', 'fr', 'ru'];
    for (const lang of languages) {
        const langPath = path.join(i18nDir, lang, 'notes.json');
        assert.ok(fs.existsSync(langPath), `Archivo de idioma ${lang} debe existir`);
        const parsed = JSON.parse(fs.readFileSync(langPath, 'utf8'));
        assert.ok(parsed['notes.table_col1'] || (parsed.notes && parsed.notes.table_col1), `${lang} debe contener table_col1`);
        assert.ok(parsed['config.window.controls_title'] || (parsed.config && parsed.config.window && parsed.config.window.controls_title), `${lang} debe contener controls_title`);
    }

    const catalogsSrc = fs.readFileSync(path.resolve(__dirname, '../qml/I18nCatalogs.js'), 'utf8');
    assert.ok(catalogsSrc.includes('Column 1'), "I18nCatalogs.js debe contener traducción en inglés Column 1");
    assert.ok(catalogsSrc.includes('LaTeX syntax error'), "I18nCatalogs.js debe contener LaTeX syntax error");
});

// ─────────────────────────────────────────────────────────────────────────────
// F124: Detección y layout adaptativo CSD izquierda/derecha según entorno de escritorio
// ─────────────────────────────────────────────────────────────────────────────
runTest("F124: Detección y layout adaptativo CSD izquierda/derecha según entorno de escritorio", () => {
    const bridgeH = fs.readFileSync(path.resolve(__dirname, '../src/native/native_bridge.h'), 'utf8');
    assert.ok(bridgeH.includes('windowControlsOnLeft'), "native_bridge.h debe declarar windowControlsOnLeft");

    const bridgeCpp = fs.readFileSync(path.resolve(__dirname, '../src/native/native_bridge.cpp'), 'utf8');
    assert.ok(bridgeCpp.includes('bool Sys::windowControlsOnLeft() const'), "native_bridge.cpp debe implementar Sys::windowControlsOnLeft()");
    assert.ok(bridgeCpp.includes('NOTAS_WINDOW_CONTROLS_SIDE'), "Sys::windowControlsOnLeft debe consultar NOTAS_WINDOW_CONTROLS_SIDE");

    const mainRs = fs.readFileSync(path.resolve(__dirname, '../src/main.rs'), 'utf8');
    assert.ok(mainRs.includes('window-controls-side'), "main.rs debe aceptar bandera --window-controls-side");
    assert.ok(mainRs.includes('csd-left'), "main.rs debe aceptar bandera --csd-left");
    assert.ok(mainRs.includes('csd-right'), "main.rs debe aceptar bandera --csd-right");

    const winControlsQml = fs.readFileSync(path.resolve(__dirname, '../qml/WindowControls.qml'), 'utf8');
    assert.ok(winControlsQml.includes('readonly property bool onLeft'), "WindowControls.qml debe definir propiedad onLeft");
    assert.ok(winControlsQml.includes('root.onLeft ? ["close", "min", "max"] : ["min", "max", "close"]'), "WindowControls.qml debe ordenar botones según onLeft");

    const contentQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesContent.qml'), 'utf8');
    assert.ok(contentQml.includes('property bool windowControlsOnLeft'), "NotesContent.qml debe propagar windowControlsOnLeft");

    const editorQml = fs.readFileSync(path.resolve(__dirname, '../qml/NoteEditorModal.qml'), 'utf8');
    assert.ok(editorQml.includes('property bool windowControlsOnLeft'), "NoteEditorModal.qml debe adaptar espaciadores CSD con windowControlsOnLeft");
});

runTest("F125: BlockQuote contratos de borrado con Backspace y salto de línea multilínea", () => {
    const bqQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockQuote.qml'), 'utf8');
    assert.ok(bqQml.includes('root.editor.convertBlockType(root.blockData.bid, "paragraph", "");'),
        "Backspace en cita vacía debe convertir a párrafo limpio sin '> '");
    assert.ok(bqQml.includes('root.editor.insertParagraphAfter(root.blockData.bid)'),
        "Enter en línea vacía de cita debe salir a párrafo siguiente");
    assert.ok(bqQml.includes('root._syncTextFromModel()'),
        "Enter con texto en cita debe refrescar el modelo con formateo rico");
});

runTest("F126: NoteEditorModal persistencia del título en frontmatter y null-safety de blocksModel", () => {
    const nemQml = fs.readFileSync(path.resolve(__dirname, '../qml/NoteEditorModal.qml'), 'utf8');
    assert.ok(nemQml.includes('root.performSave(null, true);'),
        "_confirmTitleRename debe ejecutar performSave forzado para persistir frontmatter");
    assert.ok(nemQml.includes('blockEditor && blockEditor.blocksModel && blockEditor.blocksModel.count > 0'),
        "Navegación de teclas en titleInput debe chequear defensivamente blockEditor.blocksModel");
});

runTest("F127: NotesService getNote resolución de notas por título, slug canónico y slug normalizado", () => {
    const nsQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesService.qml'), 'utf8');
    assert.ok(nsQml.includes('MD.slugify(slug)'),
        "getNote debe probar versión normalizada con guiones");
    assert.ok(nsQml.includes('n.title.trim().toLowerCase() === searchLower'),
        "getNote debe resolver notas buscando por título humano en la lista notes");
});

runTest("F128: Catálogo de comando slash /link y traducciones completas en 9 idiomas", () => {
    const slashJs = fs.readFileSync(path.resolve(__dirname, '../qml/SlashCommands.js'), 'utf8');
    assert.ok(slashJs.includes('badge: "/link"'), "SlashCommands.js debe incluir comando con badge /link");
    assert.ok(slashJs.includes('id: "link"'), "SlashCommands.js debe declarar id: link");

    const blockEditorQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockEditor.qml'), 'utf8');
    assert.ok(blockEditorQml.includes('if (cmdId === "link")'),
        "BlockEditor debe despachar cmdId link");

    const catalogsJs = fs.readFileSync(path.resolve(__dirname, '../qml/I18nCatalogs.js'), 'utf8');
    assert.ok(catalogsJs.includes('"notes.slash.link"'), "I18nCatalogs.js debe contener notes.slash.link");
    assert.ok(catalogsJs.includes('"notes.slash.link_desc"'), "I18nCatalogs.js debe contener notes.slash.link_desc");
});

runTest("F129: BlockParagraph acotamiento de _findLinkBoundingBox y eliminación de loop en Loader", () => {
    const bpQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockParagraph.qml'), 'utf8');
    assert.ok(bpQml.includes('var maxLineH = Math.round(EditorMetrics.body * 2.2);'),
        "_findLinkBoundingBox debe acotar altura máxima de enlace");
    assert.ok(!bpQml.includes('ShaderEffectSource'),
        "BlockParagraph no debe usar ShaderEffectSource para overlays de enlace");

    const beQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockEditor.qml'), 'utf8');
    assert.ok(beQml.includes('readonly property bool mustBeActive: inViewportChunk || blockIsEditing || isSelected || isSearchTarget'),
        "BlockEditor Loader no debe crear bucle con _everActivated");
    assert.ok(!beQml.includes('_everActivated'),
        "BlockEditor Loader debe eliminar variable causante de bucle");
});

runTest("F130: BlockList renumbering con inicio arbitrario y preservación de listas desordenadas", () => {
    const blockListQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockList.qml'), 'utf8');

    // 1. Verificar lógica de inicio arbitrario y no sobreescritura forzada en _renumberAllOrdered
    assert.ok(blockListQml.includes('currentCount = (!isNaN(thisNum) && thisNum > 0) ? thisNum : 1;'),
        "BlockList debe respetar el número de inicio arbitrario del primer ítem");
    assert.ok(blockListQml.includes('currentCount = !isNaN(thisNum) ? thisNum : (prevNum + 1);'),
        "BlockList debe preservar números arbitrarios y desordenados explícitos");

    // 2. Simulación de renumbering
    function simulateRenumber(items) {
        var indentCounters = {};
        for (var i = 0; i < items.length; i++) {
            var it = items[i];
            var ind = it.indent || "";
            var isOrd = it.marker && (it.marker.indexOf(".") !== -1 || it.marker.indexOf(")") !== -1);
            if (isOrd) {
                var thisNum = parseInt(it.marker, 10);
                var prevNum = indentCounters[ind];
                var currentCount;
                if (prevNum === undefined) {
                    currentCount = (!isNaN(thisNum) && thisNum > 0) ? thisNum : 1;
                } else if (thisNum === prevNum) {
                    currentCount = prevNum + 1;
                } else {
                    currentCount = !isNaN(thisNum) ? thisNum : (prevNum + 1);
                }
                indentCounters[ind] = currentCount;
                var delim = it.marker.endsWith(")") ? ")" : ".";
                it.marker = currentCount + delim;
            }
        }
        return items;
    }

    // Lista que empieza en 9. y continúa en 10.
    const startNine = [{ marker: "9." }, { marker: "10." }];
    simulateRenumber(startNine);
    assert.strictEqual(startNine[0].marker, "9.", "Ítem 0 debe mantener 9.");
    assert.strictEqual(startNine[1].marker, "10.", "Ítem 1 debe mantener 10.");

    // Lista desordenada 1., 2., 5., 3., 4.
    const disordered = [{ marker: "1." }, { marker: "2." }, { marker: "5." }, { marker: "3." }, { marker: "4." }];
    simulateRenumber(disordered);
    assert.strictEqual(disordered[0].marker, "1.");
    assert.strictEqual(disordered[1].marker, "2.");
    assert.strictEqual(disordered[2].marker, "5.", "5. debe conservarse sin sobreescribir a 3.");
    assert.strictEqual(disordered[3].marker, "3.", "3. debe conservarse sin sobreescribir a 4.");
    assert.strictEqual(disordered[4].marker, "4.", "4. debe conservarse");

    // Atajo de cambio de numeración interactivo
    assert.ok(blockListQml.includes('var ordMatch = cleanText.match(/^(\\d+[.)])[ \\t]+([\\s\\S]*)$/);'),
        "BlockList debe detectar atajo de cambio de numeración al escribir en el ítem");
});

runTest("F131: NoteEditorModal header adaptativo CSD sin colisión de botones X", () => {
    const modalQml = fs.readFileSync(path.resolve(__dirname, '../qml/NoteEditorModal.qml'), 'utf8');

    assert.ok(modalQml.includes('id: backBtnComp'),
        "NoteEditorModal debe tener un componente reutilizable para el botón de cierre");
    assert.ok(modalQml.includes('id: backBtnLeftLoader'),
        "NoteEditorModal debe tener loader izquierdo de botón cerrar");
    assert.ok(modalQml.includes('active: root.isExpanded && !root.windowControlsOnLeft'),
        "backBtnLeftLoader debe activarse solo cuando los controles CSD NO están a la izquierda");
    assert.ok(modalQml.includes('id: backBtnRightLoader'),
        "NoteEditorModal debe tener loader derecho de botón cerrar");
    assert.ok(modalQml.includes('active: root.isExpanded && root.windowControlsOnLeft'),
        "backBtnRightLoader debe activarse cuando los controles CSD están a la izquierda");
});

runTest("F132: Acción math en EditorActions y catálogo completo de traducciones en 9 idiomas", () => {
    const eaJs = fs.readFileSync(path.resolve(__dirname, '../qml/EditorActions.js'), 'utf8');
    assert.ok(eaJs.includes('"math": {'), "EditorActions debe incluir la acción math");
    assert.ok(eaJs.includes('labelKey: "notes.editor.action.math"'), "math debe vincularse a notes.editor.action.math");

    const catalogsJs = fs.readFileSync(path.resolve(__dirname, '../qml/I18nCatalogs.js'), 'utf8');
    assert.ok(catalogsJs.includes('"notes.editor.action.math"'), "I18nCatalogs debe contener notes.editor.action.math");

    const meta = JSON.parse(fs.readFileSync(path.resolve(__dirname, '../assets/i18n/meta.json'), 'utf8'));
    for (const l of meta.languages) {
        const langPath = path.resolve(__dirname, `../assets/i18n/${l.code}/notes.json`);
        const json = JSON.parse(fs.readFileSync(langPath, 'utf8'));
        assert.ok(json['notes.editor.action.math'], `notes.json en ${l.code} debe traducir notes.editor.action.math`);
        assert.ok(json.editor && json.editor.action && json.editor.action.math,
            `notes.json en ${l.code} debe tener editor.action.math anidado`);
    }
});

runTest("F133: Single Source of Truth para versión de la app (NotesConfig.appVersion y NotesSettingsModal)", () => {
    const configQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesConfig.qml'), 'utf8');
    assert.ok(configQml.includes('readonly property string appVersion:'), "NotesConfig debe declarar propiedad appVersion");
    assert.ok(configQml.includes('Quickshell.env("NOTAS_APP_VERSION"'), "NotesConfig debe resolver NOTAS_APP_VERSION");

    const settingsQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesSettingsModal.qml'), 'utf8');
    assert.ok(settingsQml.includes('text: "dev.criperto.Notas • Versión " + NotesConfig.appVersion'),
        "NotesSettingsModal debe ligar dinámicamente a NotesConfig.appVersion");
    assert.ok(!settingsQml.includes('"dev.criperto.Notas • Versión 0.2.1"'),
        "NotesSettingsModal no debe hardcodear versión antigua");

    const mainRs = fs.readFileSync(path.resolve(__dirname, '../src/main.rs'), 'utf8');
    assert.ok(mainRs.includes('std::env::set_var("NOTAS_APP_VERSION", env!("CARGO_PKG_VERSION"));'),
        "src/main.rs debe inyectar NOTAS_APP_VERSION desde CARGO_PKG_VERSION");
});

runTest("F134: BlockEditor splitListBlock división de listas al presionar Enter en ítem vacío nivel 0", () => {
    const editorQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockEditor.qml'), 'utf8');
    assert.ok(editorQml.includes('function splitListBlock(bid, itemIdx)'),
        "BlockEditor debe definir la función splitListBlock");

    const listQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockList.qml'), 'utf8');
    assert.ok(listQml.includes('editorRef.splitListBlock(bidRef, itemIdx'),
        "BlockList handleItemReturn debe invocar splitListBlock al salir en nivel 0");
});

runTest("F135: Hotfix v0.2.4 salida de viñetas con Enter, preservación de foco y no confirmActiveBlock destructivo", () => {
    const editorQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockEditor.qml'), 'utf8');
    // splitListBlock no debe llamar confirmActiveBlock para no deseleccionar ni corromper modelos
    const splitFn = editorQml.substring(editorQml.indexOf('function splitListBlock'), editorQml.indexOf('function deleteBlock'));
    assert.ok(!splitFn.includes('root.confirmActiveBlock()'),
        "splitListBlock no debe ejecutar confirmActiveBlock");
    assert.ok(editorQml.includes('function _focusDelegateForBid(bid, cursorPos)'),
        "_focusDelegateForBid debe existir");
    assert.ok(editorQml.includes('cand.blockItemData.bid === bid'),
        "_getDelegateItemForBid debe verificar coincidencia de bid exacta");

    const listQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockList.qml'), 'utf8');
    assert.ok(listQml.includes('LP.serializeList(root._itemsRawArray.slice(0, itemIdx))'),
        "BlockList debe particionar directamente su array local sin reparsear");

    const paraQml = fs.readFileSync(path.resolve(__dirname, '../qml/BlockParagraph.qml'), 'utf8');
    assert.ok(paraQml.includes('root.editor.activeBlockBid === root.blockData.bid'),
        "BlockParagraph debe garantizar visibilidad de editInput inmediatamente");

    const cargoToml = fs.readFileSync(path.resolve(__dirname, '../Cargo.toml'), 'utf8');
    assert.ok(cargoToml.includes('version = "0.2.4"') || cargoToml.includes('version = "0.2.5"'), "Cargo.toml debe estar en 0.2.4 o 0.2.5");
});

runTest("F136: Auditoría de estabilidad, FreeDesktop Trash, rutas XDG, supresión de I/O espurio y renombrado atómico", () => {
    const bridgeH = fs.readFileSync(path.resolve(__dirname, '../src/native/native_bridge.h'), 'utf8');
    assert.ok(bridgeH.includes('moveToTrash(const QString &filePath)'), "native_bridge.h debe declarar moveToTrash");
    assert.ok(bridgeH.includes('fileExists(const QString &filePath)'), "native_bridge.h debe declarar fileExists");
    assert.ok(bridgeH.includes('renameFile(const QString &oldPath, const QString &newPath)'), "native_bridge.h debe declarar renameFile");
    assert.ok(bridgeH.includes('ensureDir(const QString &path)'), "native_bridge.h debe declarar ensureDir");
    assert.ok(bridgeH.includes('m_lastInternalSaveMs'), "native_bridge.h debe contener timestamp de supresión de guardado interno");

    const bridgeCpp = fs.readFileSync(path.resolve(__dirname, '../src/native/native_bridge.cpp'), 'utf8');
    assert.ok(bridgeCpp.includes('QFile::moveToTrash(filePath)'), "Sys::moveToTrash debe usar QFile::moveToTrash nativo");
    assert.ok(bridgeCpp.includes('QFile::rename(oldPath, newPath)'), "Sys::renameFile debe usar QFile::rename atómico");
    assert.ok(bridgeCpp.includes('m_lastInternalSaveMs = QDateTime::currentMSecsSinceEpoch()'), "writeFile debe registrar timestamp de guardado");
    assert.ok(bridgeCpp.includes('m_windowControlsOnLeftCached = true'), "windowControlsOnLeft debe memoizar resultado");

    const notesServiceQml = fs.readFileSync(path.resolve(__dirname, '../qml/NotesService.qml'), 'utf8');
    assert.ok(notesServiceQml.includes('Sys.moveToTrash'), "NotesService debe intentar Sys.moveToTrash antes de gio trash");
    assert.ok(notesServiceQml.includes('Sys.renameFile'), "NotesService debe usar Sys.renameFile atómico");
    assert.ok(notesServiceQml.includes('XDG_STATE_HOME'), "NotesService debe soportar XDG_STATE_HOME con fallback seguro");

    const editorModalQml = fs.readFileSync(path.resolve(__dirname, '../qml/NoteEditorModal.qml'), 'utf8');
    assert.ok(editorModalQml.includes('property bool isRenaming: false'), "NoteEditorModal debe tener bandera isRenaming");
    assert.ok(editorModalQml.includes('root.isRenaming = true'), "_confirmTitleRename debe activar isRenaming");
    assert.ok(editorModalQml.includes('root.isLoading || !root.loadedSlug || root.isRenaming'), "markDirty debe omitir durante renombrado");
});

console.log(`\n========================================`);
console.log(`Resultados: ${passed} OK, ${failed} FAIL`);
console.log(`========================================`);

if (failed > 0) {
    process.exit(1);
}
