# Changelog

## v2.4 (2026-08-30) — Refresh build

### ✨ Nuevas features
- **Selector de idioma al primer launch**: pantalla de bienvenida que aparece la primera vez que abrís la app para elegir entre Español, English o Русский. Persistido con `@AppStorage("hasSelectedLanguage")`. Se puede cambiar después desde el menú 🌐.
- **Icono Zeekr rediseñado**: rayo Zeekr en cyan/azul con bordes redondeados, fondo azul oscuro con ondas. Reemplaza al ícono anterior (Z plateada).

### 🔧 Cambios internos
- `ContentView.swift`: nuevo overlay `firstLaunchLanguagePicker` con gradiente Zeekr y bandera de país por idioma.
- `project.yml`: `MARKETING_VERSION: "2.4"`, `CURRENT_PROJECT_VERSION: "24"`.
- `Assets.xcassets/AppIcon.appiconset/`: regenerados los `icon-29..1024.png` con el nuevo diseño.

### ✅ Features ya presentes (verificadas en v2.23)
- Modo seguro con threshold configurable (toggle en header)
- Smart matching por categoría: si decís "cajuela" o "ventana" sin match exacto, muestra todas las opciones de esa categoría
- Confirmación con número: decir "uno", "dos", "la 3", "número 4" selecciona la opción
- Cancelar con voz: "cancelar", "no", "nada"
- Multi-idioma ASR: es-MX, en-US, ru-RU (selector en settings)
- Wake word: "oye Yoe" / "empezar" / "reanudar"
- Historial últimos 20 comandos
- Botón PARAR (kill switch de emergencia)
- Wake word "嗨伊娃" + comando en chino mandarín (TTS on-device)

## v2.23 (anterior)
Build con modo seguro, smart matching por categoría, multi-idioma, y la mayoría de las features de v2.4 pero sin selector de primer launch y con el ícono viejo.
