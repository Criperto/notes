# Reglas e Integración de Hyprland para `Notas`

Guía de configuración para integrar `Notas` (`io.github.criperto.notes`) con Hyprland.

> [!NOTE]
> Recuerda que las reglas no se modifican automáticamente; cópialas en tu configuración de Hyprland según tu preferencia.

---

## 1. Configuración Estándar (`hyprland.conf`)

### Reglas de Ventana (Flotante centrada con dimensiones recomendadas)
```ini
# Regla para la ventana principal de Notas
windowrulev2 = float, class:^(io.github.criperto.notes)$
windowrulev2 = center, class:^(io.github.criperto.notes)$
windowrulev2 = size 1040 740, class:^(io.github.criperto.notes)$
windowrulev2 = minsize 680 500, class:^(io.github.criperto.notes)$
windowrulev2 = dimaround, class:^(io.github.criperto.notes)$
```

### Atajo de Teclado (Toggle inteligente)
```ini
# Super + N para alternar o enfocar Notas
bind = $mainMod, N, exec, criperto-notes toggle
```

---

## 2. Configuración en Sintaxis Lua (Entornos con Hyprland Lua)

Si tu entorno utiliza configuración modular en Lua (ej. `windows.lua` y `keybinduser.lua`):

### En `windows.lua`:
```lua
hl.windowrule({
    class = "io.github.criperto.notes",
    float = true,
    center = true,
    size = { 1040, 740 },
    minsize = { 680, 500 },
})
```

### En `keybinduser.lua`:
```lua
hl.bind({
    mods = { "SUPER" },
    key = "n",
    dispatcher = "exec",
    args = "criperto-notes toggle",
})
```
