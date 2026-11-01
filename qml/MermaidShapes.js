.pragma library

// MermaidShapes.js — Generador de rutas SVG (PathSvg) para formas y marcadores de Mermaid

function getShapePath(shape, w, h, r) {
    var radius = (typeof r === "number") ? r : 6;
    switch (shape) {
        case "round":
            return roundedRectPath(w, h, radius);
        case "stadium":
            return stadiumPath(w, h);
        case "subroutine":
            return subroutinePath(w, h);
        case "cylinder":
            return cylinderPath(w, h);
        case "circle":
            if (Math.abs(w - h) > 4) {
                return ellipsePath(w, h);
            }
            return circlePath(Math.min(w, h));
        case "doublecircle":
            var d = Math.min(w, h);
            if (Math.abs(w - h) > 4) {
                var rx1 = w / 2;
                var ry1 = h / 2;
                var rx2 = Math.max(2, rx1 - 4);
                var ry2 = Math.max(2, ry1 - 4);
                return ellipsePath(w, h) + " " +
                       "M 4 " + ry1 + " " +
                       "A " + rx2 + " " + ry2 + " 0 1 0 " + (w - 4) + " " + ry1 + " " +
                       "A " + rx2 + " " + ry2 + " 0 1 0 4 " + ry1 + " Z";
            }
            return doubleCirclePath(d);
        case "diamond":
            return diamondPath(w, h);
        case "hexagon":
            return hexagonPath(w, h);
        case "parallelogram":
            return parallelogramPath(w, h, false);
        case "parallelogram_alt":
            return parallelogramPath(w, h, true);
        case "trapezoid":
            return trapezoidPath(w, h, false);
        case "trapezoid_alt":
            return trapezoidPath(w, h, true);
        case "asym":
            return asymPath(w, h);
        case "start":
            return circlePath(Math.min(w, h));
        case "end":
            return doubleCirclePath(Math.min(w, h));
        case "choice":
            return diamondPath(w, h);
        case "fork":
        case "join":
            return roundedRectPath(w, h, 2);
        case "cloud":
            return cloudPath(w, h);
        case "bang":
            return bangPath(w, h);
        case "rect":
        default:
            return rectPath(w, h);
    }
}

function rectPath(w, h) {
    return "M 0 0 L " + w + " 0 L " + w + " " + h + " L 0 " + h + " Z";
}

function roundedRectPath(w, h, r) {
    var rad = Math.min(r, Math.min(w, h) / 2);
    return "M " + rad + " 0 " +
           "L " + (w - rad) + " 0 " +
           "Q " + w + " 0 " + w + " " + rad + " " +
           "L " + w + " " + (h - rad) + " " +
           "Q " + w + " " + h + " " + (w - rad) + " " + h + " " +
           "L " + rad + " " + h + " " +
           "Q 0 " + h + " 0 " + (h - rad) + " " +
           "L 0 " + rad + " " +
           "Q 0 0 " + rad + " 0 Z";
}

function stadiumPath(w, h) {
    var r = h / 2;
    return "M " + r + " 0 " +
           "L " + (w - r) + " 0 " +
           "A " + r + " " + r + " 0 0 1 " + (w - r) + " " + h + " " +
           "L " + r + " " + h + " " +
           "A " + r + " " + r + " 0 0 1 " + r + " 0 Z";
}

function subroutinePath(w, h) {
    var inset = 10;
    return "M 0 0 L " + w + " 0 L " + w + " " + h + " L 0 " + h + " Z " +
           "M " + inset + " 0 L " + inset + " " + h + " " +
           "M " + (w - inset) + " 0 L " + (w - inset) + " " + h;
}

function cylinderPath(w, h) {
    var pad = 1;
    var x0 = pad;
    var x1 = Math.max(x0 + 4, w - pad);
    var y0 = pad;
    var y1 = Math.max(y0 + 4, h - pad);
    var rx = (x1 - x0) / 2;
    var ry = Math.min(10, Math.max(5, Math.round((y1 - y0) * 0.16)));
    var topFace = "M " + x0 + " " + (y0 + ry) + " " +
                  "A " + rx + " " + ry + " 0 0 1 " + x1 + " " + (y0 + ry) + " " +
                  "A " + rx + " " + ry + " 0 0 1 " + x0 + " " + (y0 + ry) + " Z";
    var body = "M " + x0 + " " + (y0 + ry) + " " +
               "L " + x0 + " " + (y1 - ry) + " " +
               "A " + rx + " " + ry + " 0 0 0 " + x1 + " " + (y1 - ry) + " " +
               "L " + x1 + " " + (y0 + ry) + " " +
               "A " + rx + " " + ry + " 0 0 1 " + x0 + " " + (y0 + ry) + " Z";
    return topFace + " " + body;
}

function ellipsePath(w, h) {
    var rx = w / 2;
    var ry = h / 2;
    return "M 0 " + ry + " " +
           "A " + rx + " " + ry + " 0 1 0 " + w + " " + ry + " " +
           "A " + rx + " " + ry + " 0 1 0 0 " + ry + " Z";
}

function circlePath(d) {
    var r = d / 2;
    return "M 0 " + r + " " +
           "A " + r + " " + r + " 0 1 0 " + d + " " + r + " " +
           "A " + r + " " + r + " 0 1 0 0 " + r + " Z";
}

function doubleCirclePath(d) {
    var r1 = d / 2;
    var r2 = r1 - 4;
    return circlePath(d) + " " +
           "M 4 " + r1 + " " +
           "A " + r2 + " " + r2 + " 0 1 0 " + (d - 4) + " " + r1 + " " +
           "A " + r2 + " " + r2 + " 0 1 0 4 " + r1 + " Z";
}

function diamondPath(w, h) {
    var mx = w / 2;
    var my = h / 2;
    return "M " + mx + " 0 L " + w + " " + my + " L " + mx + " " + h + " L 0 " + my + " Z";
}

function hexagonPath(w, h) {
    var dx = Math.min(16, w / 4);
    var my = h / 2;
    return "M " + dx + " 0 L " + (w - dx) + " 0 L " + w + " " + my + " L " + (w - dx) + " " + h + " L " + dx + " " + h + " L 0 " + my + " Z";
}

function parallelogramPath(w, h, alt) {
    var dx = Math.min(16, w / 4);
    if (!alt) {
        return "M " + dx + " 0 L " + w + " 0 L " + (w - dx) + " " + h + " L 0 " + h + " Z";
    } else {
        return "M 0 0 L " + (w - dx) + " 0 L " + w + " " + h + " L " + dx + " " + h + " Z";
    }
}

function trapezoidPath(w, h, alt) {
    var dx = Math.min(16, w / 4);
    if (!alt) {
        // Base inferior más ancha
        return "M " + dx + " 0 L " + (w - dx) + " 0 L " + w + " " + h + " L 0 " + h + " Z";
    } else {
        // Base superior más ancha
        return "M 0 0 L " + w + " 0 L " + (w - dx) + " " + h + " L " + dx + " " + h + " Z";
    }
}

function asymPath(w, h) {
    var dx = Math.min(14, w / 4);
    var my = h / 2;
    return "M 0 0 L " + (w - dx) + " 0 L " + w + " " + my + " L " + (w - dx) + " " + h + " L 0 " + h + " Z";
}

function cloudPath(w, h) {
    var rw = w / 2;
    var rh = h / 2;
    var r1 = Math.min(rw, rh) * 0.45;
    return "M " + (w * 0.2) + " " + (h * 0.8) + " " +
           "A " + r1 + " " + r1 + " 0 0 1 " + (w * 0.15) + " " + (h * 0.35) + " " +
           "A " + r1 + " " + r1 + " 0 0 1 " + (w * 0.45) + " " + (h * 0.15) + " " +
           "A " + (r1 * 1.2) + " " + (r1 * 1.2) + " 0 0 1 " + (w * 0.8) + " " + (h * 0.25) + " " +
           "A " + r1 + " " + r1 + " 0 0 1 " + (w * 0.9) + " " + (h * 0.75) + " " +
           "A " + r1 + " " + r1 + " 0 0 1 " + (w * 0.6) + " " + (h * 0.9) + " " +
           "A " + r1 + " " + r1 + " 0 0 1 " + (w * 0.2) + " " + (h * 0.8) + " Z";
}

function bangPath(w, h) {
    var cx = w / 2;
    var cy = h / 2;
    var rx = w / 2;
    var ry = h / 2;
    var pts = [];
    var n = 12;
    for (var i = 0; i < n; i++) {
        var angle = (i * 2 * Math.PI) / n - Math.PI / 2;
        var rMod = (i % 2 === 0) ? 1.0 : 0.65;
        var px = cx + rx * rMod * Math.cos(angle);
        var py = cy + ry * rMod * Math.sin(angle);
        pts.push(px.toFixed(1) + " " + py.toFixed(1));
    }
    return "M " + pts.join(" L ") + " Z";
}

// ── Intersección con el borde para conectar aristas limpiamente ──────────────

function getBoundaryPoint(shape, cx, cy, w, h, angleRad) {
    var cos = Math.cos(angleRad);
    var sin = Math.sin(angleRad);
    var halfW = w / 2;
    var halfH = h / 2;

    if (shape === "circle" || shape === "doublecircle" || shape === "start" || shape === "end") {
        var r = Math.min(halfW, halfH);
        return { x: cx + r * cos, y: cy + r * sin };
    }

    if (shape === "diamond" || shape === "choice") {
        // Rombo: |x/halfW| + |y/halfH| = 1
        var denom = Math.abs(cos) / halfW + Math.abs(sin) / halfH;
        var dist = 1.0 / denom;
        return { x: cx + dist * cos, y: cy + dist * sin };
    }

    // Caja rectangular estándar (o round/stadium)
    var tx = (cos > 0) ? (halfW / cos) : (-halfW / cos);
    var ty = (sin > 0) ? (halfH / sin) : (-halfH / sin);
    var t = Math.min(Math.abs(tx), Math.abs(ty));

    return { x: cx + t * cos, y: cy + t * sin };
}

// ── Marcadores de flechas en extremos ────────────────────────────────────────

function getArrowPath(kind, targetX, targetY, angleRad, size) {
    var s = size || 8;
    var cos = Math.cos(angleRad);
    var sin = Math.sin(angleRad);

    // Vector unitario hacia atrás
    var ux = -cos;
    var uy = -sin;
    // Vector unitario perpendicular
    var px = -sin;
    var py = cos;

    if (kind === "arrow" || kind === "triangle" || kind === "triangle_hollow") {
        // Cabeza triangular cerrada (UML herencia / realización / flowchart)
        var b1x = targetX + ux * s + px * (s * 0.48);
        var b1y = targetY + uy * s + py * (s * 0.48);
        var b2x = targetX + ux * s - px * (s * 0.48);
        var b2y = targetY + uy * s - py * (s * 0.48);
        return "M " + targetX + " " + targetY + " L " + b1x + " " + b1y + " L " + b2x + " " + b2y + " Z";
    }

    if (kind === "open_arrow") {
        // Flecha abierta (asociación UML)
        var ob1x = targetX + ux * s + px * (s * 0.45);
        var ob1y = targetY + uy * s + py * (s * 0.45);
        var ob2x = targetX + ux * s - px * (s * 0.45);
        var ob2y = targetY + uy * s - py * (s * 0.45);
        return "M " + ob1x + " " + ob1y + " L " + targetX + " " + targetY + " L " + ob2x + " " + ob2y;
    }

    if (kind === "diamond" || kind === "diamond_filled" || kind === "diamond_hollow") {
        // Diamante UML (agregación o composición)
        var d1x = targetX;
        var d1y = targetY;
        var d2x = targetX + ux * (s * 0.7) + px * (s * 0.4);
        var d2y = targetY + uy * (s * 0.7) + py * (s * 0.4);
        var d3x = targetX + ux * (s * 1.4);
        var d3y = targetY + uy * (s * 1.4);
        var d4x = targetX + ux * (s * 0.7) - px * (s * 0.4);
        var d4y = targetY + uy * (s * 0.7) - py * (s * 0.4);
        return "M " + d1x + " " + d1y + " L " + d2x + " " + d2y + " L " + d3x + " " + d3y + " L " + d4x + " " + d4y + " Z";
    }

    if (kind === "crows_foot_one") {
        // ER: Exactamente uno (|| dos barras perpendiculares)
        var p1x1 = targetX + ux * (s * 0.25) + px * (s * 0.45);
        var p1y1 = targetY + uy * (s * 0.25) + py * (s * 0.45);
        var p1x2 = targetX + ux * (s * 0.25) - px * (s * 0.45);
        var p1y2 = targetY + uy * (s * 0.25) - py * (s * 0.45);
        var p2x1 = targetX + ux * (s * 0.65) + px * (s * 0.45);
        var p2y1 = targetY + uy * (s * 0.65) + py * (s * 0.45);
        var p2x2 = targetX + ux * (s * 0.65) - px * (s * 0.45);
        var p2y2 = targetY + uy * (s * 0.65) - py * (s * 0.45);
        return "M " + p1x1 + " " + p1y1 + " L " + p1x2 + " " + p1y2 + " " +
               "M " + p2x1 + " " + p2y1 + " L " + p2x2 + " " + p2y2;
    }

    if (kind === "crows_foot_zero_or_one") {
        // ER: Cero o uno (o| círculo + barra perpendicular)
        var barX1 = targetX + ux * (s * 0.25) + px * (s * 0.45);
        var barY1 = targetY + uy * (s * 0.25) + py * (s * 0.45);
        var barX2 = targetX + ux * (s * 0.25) - px * (s * 0.45);
        var barY2 = targetY + uy * (s * 0.25) - py * (s * 0.45);
        var cr = s * 0.32;
        var ccx = targetX + ux * (s * 0.85);
        var ccy = targetY + uy * (s * 0.85);
        return "M " + barX1 + " " + barY1 + " L " + barX2 + " " + barY2 + " " +
               "M " + (ccx - cr) + " " + ccy + " A " + cr + " " + cr + " 0 1 0 " + (ccx + cr) + " " + ccy + " A " + cr + " " + cr + " 0 1 0 " + (ccx - cr) + " " + ccy + " Z";
    }

    if (kind === "crows_foot_many") {
        // ER: Muchos ({ pata de gallo de 3 puntas)
        var fx1 = targetX + px * (s * 0.5);
        var fy1 = targetY + py * (s * 0.5);
        var fx2 = targetX - px * (s * 0.5);
        var fy2 = targetY - py * (s * 0.5);
        var baseCenter = { x: targetX + ux * (s * 0.9), y: targetY + uy * (s * 0.9) };
        return "M " + fx1 + " " + fy1 + " L " + baseCenter.x + " " + baseCenter.y + " " +
               "L " + fx2 + " " + fy2 + " " +
               "M " + targetX + " " + targetY + " L " + baseCenter.x + " " + baseCenter.y;
    }

    if (kind === "crows_foot_zero_or_many") {
        // ER: Cero o muchos (o{ círculo + pata de gallo)
        var zfx1 = targetX + px * (s * 0.5);
        var zfy1 = targetY + py * (s * 0.5);
        var zfx2 = targetX - px * (s * 0.5);
        var zfy2 = targetY - py * (s * 0.5);
        var zbaseCenter = { x: targetX + ux * (s * 0.8), y: targetY + uy * (s * 0.8) };
        var zcr = s * 0.32;
        var zccx = targetX + ux * (s * 1.35);
        var zccy = targetY + uy * (s * 1.35);
        return "M " + zfx1 + " " + zfy1 + " L " + zbaseCenter.x + " " + zbaseCenter.y + " " +
               "L " + zfx2 + " " + zfy2 + " " +
               "M " + targetX + " " + targetY + " L " + zbaseCenter.x + " " + zbaseCenter.y + " " +
               "M " + (zccx - zcr) + " " + zccy + " A " + zcr + " " + zcr + " 0 1 0 " + (zccx + zcr) + " " + zccy + " A " + zcr + " " + zcr + " 0 1 0 " + (zccx - zcr) + " " + zccy + " Z";
    }

    if (kind === "circle") {
        var r = s * 0.4;
        var cx = targetX + ux * r;
        var cy = targetY + uy * r;
        return "M " + (cx - r) + " " + cy + " A " + r + " " + r + " 0 1 0 " + (cx + r) + " " + cy + " A " + r + " " + r + " 0 1 0 " + (cx - r) + " " + cy + " Z";
    }

    if (kind === "cross") {
        var cs = s * 0.45;
        var p1x = targetX + ux * (cs * 0.5);
        var p1y = targetY + uy * (cs * 0.5);
        return "M " + (p1x - cs) + " " + (p1y - cs) + " L " + (p1x + cs) + " " + (p1y + cs) + " " +
               "M " + (p1x - cs) + " " + (p1y + cs) + " L " + (p1x + cs) + " " + (p1y - cs);
    }

    return "";
}
