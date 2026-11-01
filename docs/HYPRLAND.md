# Reglas e Integración de Hyprland para `Notas`

Guía de configuración para integrar `Notas` (`dev.criperto.Notas`) con Hyprland.

> [!NOTE]
> Recuerda que las reglas no se modifican automáticamente; cópialas en tu configuración de Hyprland según tu preferencia.

---

## 1. Configuración Estándar (`hyprland.conf`)

### Reglas de Ventana (Flotante centrada con dimensiones recomendadas)
```ini
# Regla para la ventana principal de Notas
windowrulev2 = float, class:^(dev.criperto.Notas)$
windowrulev2 = center, class:^(dev.criperto.Notas)$
windowrulev2 = size 1040 740, class:^(dev.criperto.Notas)$
windowrulev2 = minsize 680 500, class:^(dev.criperto.Notas)$
windowrulev2 = dimaround, class:^(dev.criperto.Notas)$
```

### Atajo de Teclado (Toggle inteligente)
```ini
# Super + N para alternar o enfocar Notas
bind = $mainMod, N, exec, notas toggle
```

---

## 2. Configuración en Sintaxis Lua (Entornos con Hyprland Lua)

Si tu entorno utiliza configuración modular en Lua (ej. `windows.lua` y `keybinduser.lua`):

### En `windows.lua`:
```lua
hl.windowrule({
    class = "dev.criperto.Notas",
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
    args = "notas toggle",
})
```
