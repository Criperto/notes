// notes/MathTemplates.js
// Plantillas predefinidas para la inserción rápida de fórmulas LaTeX

var TEMPLATES = {
    fraction: "$$\n\\frac{a}{b}\n$$",
    quadratic: "$$\nx = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}\n$$",
    integral: "$$\n\\int_{a}^{b} f(x) \\, dx\n$$",
    sum: "$$\n\\sum_{i=1}^{n} a_i\n$$",
    limit: "$$\n\\lim_{x \\to 0} \\frac{\\sin(x)}{x} = 1\n$$",
    root: "$$\n\\sqrt[n]{x}\n$$",
    matrix: "$$\n\\begin{pmatrix}\na & b \\\\\nc & d\n\\end{pmatrix}\n$$",
    cases: "$$\nf(x) = \\begin{cases}\nx^2 & \\text{si } x \\ge 0 \\\\\n-x & \\text{si } x < 0\n\\end{cases}\n$$"
};

function getTemplate(key) {
    if (TEMPLATES[key]) {
        return TEMPLATES[key];
    }
    return TEMPLATES.fraction;
}

function getTemplateList() {
    return [
        { id: "fraction", labelKey: "notes.math.template.fraction", defaultLabel: "Fracción", icon: "math" },
        { id: "quadratic", labelKey: "notes.math.template.quadratic", defaultLabel: "Ecuación cuadrática", icon: "math" },
        { id: "integral", labelKey: "notes.math.template.integral", defaultLabel: "Integral definida", icon: "math" },
        { id: "sum", labelKey: "notes.math.template.sum", defaultLabel: "Sumatoria", icon: "math" },
        { id: "limit", labelKey: "notes.math.template.limit", defaultLabel: "Límite", icon: "math" },
        { id: "root", labelKey: "notes.math.template.root", defaultLabel: "Raíz cuadrada / n-ésima", icon: "math" },
        { id: "matrix", labelKey: "notes.math.template.matrix", defaultLabel: "Matriz (2x2)", icon: "table" },
        { id: "cases", labelKey: "notes.math.template.cases", defaultLabel: "Función a trozos (Casos)", icon: "code-blocks" }
    ];
}
