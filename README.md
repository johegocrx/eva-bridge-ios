# 🚗 EVA Bridge — Standalone iOS App

App nativa de iOS para traducir tus comandos en español, inglés o ruso al chino mandarín, para que el asistente **EVA** de tu **Zeekr 7X** te entienda.

**100% offline después de instalar.** No necesita PC encendida, ni internet, ni ngrok, ni servidores.

---

## ✨ Qué hace (v2.9)

- Te escucha en **español** (on-device, sin internet, SFSpeechRecognizer es-MX)
- También entiende **inglés** y **ruso** en el top 50 de comandos (vía catálogo expandido)
- Busca en el catálogo de **254 comandos** EVA pre-cargado
- **Modo seguro**: si la confidence del reconocimiento es baja, NO ejecuta — pregunta con sugerencias
- **Sugerencias por categoría**: si decís "cajuela" sin match exacto, muestra todos los comandos de cajuela
- **Botón PARAR**: kill switch de emergencia que cancela todo instantáneamente
- **Historial**: últimos 20 comandos ejecutados, tappeá uno para repetirlo
- **"Oye Yoe"**: reanuda la escucha con la voz, sin tocar la pantalla
- Pronuncia la **wake word** "嗨伊娃" (Hey EVA) + el comando en **chino mandarín** (on-device)

## 🆚 Comparado con la versión PWA

| | PWA (web) | **iOS nativo (este)** |
|---|---|---|
| Requiere internet | Sí (Web Speech API) | **NO** — todo on-device |
| Requiere PC encendida | Sí (ngrok) | **NO** — standalone |
| Reconoce voz | Via Siri servers | **On-device (SFSpeechRecognizer)** |
| TTS chino | On-device (limitado) | **On-device (AVSpeechSynthesizer, premium)** |
| Velocidad de respuesta | ~1-2s red | **<100ms local** |
| Privacidad | Audio sale a Apple | **Audio nunca sale del iPhone** |
| Multi-idioma | Solo ES | **ES + EN + RU (top 50)** |
| Modo seguro | No | **Sí** |
| Historial | No | **Sí (20)** |
| Multi-idioma | Solo ES | **ES + EN + RU (top 50)** |
| Modo seguro | No | **Sí — confirma antes de ejecutar** |
| Historial | No | **Sí — últimos 20 comandos** |

---

## 🎤 Comandos de voz útiles

| Decir | Acción |
|---|---|
| (cualquier comando de los 254 del catálogo) | Lo traduce a chino y se lo dice a EVA |
| **"adiós"** / **"cancelar"** / **"para"** | Detiene la escucha |
| **"oye Yoe"** / **"empezar"** / **"reanudar"** | Reanuda la escucha (cuando está pausada) |
| **"PARAR"** (botón rojo) | Kill switch de emergencia |

## ⚙️ Modo seguro (toggle en la app)

- **ON (default)**: si la confidence del match es < 70%, NO ejecuta. En su lugar, pregunta: "¿Quisiste decir X?" con la lista de candidatos. Vos elegís.
- **OFF**: ejecuta el mejor match siempre, sin preguntar.

Útil cuando:
- Hay ruido ambiente y el ASR transcribe mal
- El head unit está con la ventana abierta
- El user quiere tener control total antes de cada acción

---

## 🚀 Instalación (3 caminos — elegí el que te sirva)

### Camino A: GitHub Actions — **RECOMENDADO**, sin Mac, 100% automático

**Requisitos:** cuenta GitHub gratis (no pagás nada)

1. Andá a https://github.com/new
2. Nombre: `eva-bridge-ios` (o lo que quieras)
3. Visibility: **Public** (para que las GitHub Actions sean gratis)
4. **NO inicialices** con README, .gitignore, ni licencia
5. Click **Create repository**

6. Descargá el ZIP de este proyecto y descomprimilo
7. Abrí una terminal y andá a la carpeta descomprimida:
   ```bash
   cd ruta/a/EVA-Bridge-iOS
   git init
   git add .
   git commit -m "init"
   git branch -M main
   git remote add origin https://github.com/TU_USUARIO/eva-bridge-ios.git
   git push -u origin main
   ```
8. Andá a la pestaña **Actions** de tu repo → click **Build EVA Bridge IPA** → **Run workflow**
9. Esperá 5-10 minutos
10. Cuando termine, click en el run → bajá el artifact **EVA-Bridge-unsigned**
11. Descomprimilo → tenés `EVA-Bridge.ipa`

**Instalar el .ipa en tu iPhone (elegí una):**

**Opción 1: Sideloadly (más fácil)**
12. Descargá **Sideloadly** desde https://sideloadly.io (Windows)
13. Conectá tu iPhone por USB
14. Abrí Sideloadly → arrastrá el .ipa → ingresá tu Apple ID
15. Click **Start** → espera 30-60s
16. En el iPhone: Ajustes → General → VPN y gestión de dispositivos → tu Apple ID → Confiar
17. ¡Listo! El ícono **EVA Bridge** aparece en tu pantalla de inicio

**Opción 2: AltStore (más permanente)**
12. Descargá **AltStore** desde https://altstore.io en tu PC
13. Instalá AltStore en tu iPhone (requiere iTunes/Apple Devices y un Apple ID)
14. Abrí AltStore en el iPhone → My Apps → **+** → elegí `EVA-Bridge.ipa`
15. AltStore lo firma con tu Apple ID y lo instala
16. **Confiá en el developer**: Ajustes → General → VPN y gestión de dispositivos → tu Apple ID → Confiar
17. ¡Listo! El ícono **EVA Bridge** aparece en tu pantalla de inicio

**Refrescar cada 7 días:** 
- **Sideloadly**: reabrir Sideloadly y "Start" de nuevo
- **AltStore**: automático si tu PC está encendida con AltServer, o manual desde la app

---

### Camino B: Amigo con Mac — 5 minutos, una sola vez

**Requisitos:** acceso a una Mac con Xcode 15+ (amigo, Apple Store, biblioteca, coworking)

1. Pedile a tu amigo que instale **XcodeGen**:
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   brew install xcodegen
   ```

2. Pasale la carpeta `eva-bridge-ios/` (por USB, AirDrop, lo que sea)

3. En la Mac:
   ```bash
   cd eva-bridge-ios
   xcodegen generate
   open EVA-Bridge.xcodeproj
   ```

4. En Xcode:
   - Click en el proyecto **EVA-Bridge** en el panel izquierdo
   - Tab **Signing & Capabilities**
   - Desmarcá "Automatically manage signing"
   - En **Team** elegí "Add an Account..." → ingresá tu Apple ID (gratis)
   - Volvé a marcar "Automatically manage signing"
   - Cambiá el **Bundle Identifier** a algo único: `com.evabridge.YOURNAME.zeekr`
   - Conectá tu iPhone por USB
   - Arriba a la izquierda, elegí tu iPhone como destino
   - Click **▶** (Run) o `Cmd+R`

5. En el iPhone:
   - Ajustes → General → VPN y gestión de dispositivos → tu Apple ID → Confiar
   - Abrí **EVA Bridge** desde el home

6. ¡Listo! Tu amigo puede cerrar todo. La app queda en tu iPhone.

---

### Camino C: App Store (futuro) — si querés distribución pública

Si querés publicar la app en el App Store para que otros Zeekr owners la bajen:
- Necesitás Apple Developer Program ($99 USD/año)
- Subís el IPA firmado con tu cert a App Store Connect
- Esperás review (1-3 días)
- Aprobada → cualquiera la baja con su Apple ID

Si te interesa, decime y armamos el flujo.

---

## 🔧 Requisitos técnicos

- **iOS 16 o superior** (para on-device speech recognition en español)
- **iPhone 8 o superior** (chips A11+ para on-device ML)
- **Espacio:** ~30 MB
- **Voz china instalada** (Ajustes → General → Teclado → Teclados → Agregar → Chino simplificado)

## 🐛 Solución de problemas

**"Reconocimiento on-device no soportado"** en la app
- Tu iPhone no soporta on-device ASR para español. Opciones:
  - Actualizá a iOS 16+ si es posible
  - O usá un iPhone más moderno (XS+)
  - La app sigue funcionando pero usará servidor (necesita internet)

**"Sin voz china"** en la app
- Ajustes → General → Teclado → Teclados → Agregar teclado nuevo → Chino (simplificado)
- O: Ajustes → Accesibilidad → Contenido hablado → Voces → Voz → Chino → descargar voz mejorada
- Reiniciá la app

**El head unit no entiende el chino del iPhone**
- Subí volumen del iPhone al **100%**
- Activá **Speaker / Manos libres** (altavoz trasero es muy débil)
- Acerca el iPhone a **5-10 cm** del micrófono del coche
- A veces ayuda hablar el comando DOS veces

**La app caduca a los 7 días (AltStore)**
- Abrí AltStore en el iPhone → My Apps → Refresh All
- O dejá tu PC encendida con AltServer para auto-refresh

---

## 📂 Estructura del proyecto

```
eva-bridge-ios/
├── EVA-Bridge/
│   ├── EVABridgeApp.swift        # Entry point SwiftUI (DI de managers)
│   ├── ContentView.swift          # UI principal (header, mic, lista, historial)
│   ├── SpeechManager.swift        # SFSpeechRecognizer on-device (es-MX) + pause/resume
│   ├── TTSManager.swift           # AVSpeechSynthesizer zh-CN (premium voice)
│   ├── VoiceService.swift         # Orquesta escucha continua, modo seguro, pánico
│   ├── CatalogMatcher.swift       # Búsqueda fuzzy 254 comandos (es+en+ru) + categorías
│   ├── CommandHistory.swift       # Historial últimos 20 comandos (UserDefaults)
│   ├── WakeWordDetector.swift     # Stop / start / cancel commands
│   ├── AppIntents/
│   │   ├── OpenEVAIntent.swift    # AppIntent para "Oye Siri, abrir EVA Copilot"
│   │   └── EVACopilotShortcuts.swift # Provider de Shortcuts
│   ├── Info.plist                 # Permisos mic + speech + App Intents
│   ├── catalog.json               # 254 comandos (50 con en+ru)
│   └── Assets.xcassets/           # Logo Zeekr Z con ondas + AccentColor
├── project.yml                    # XcodeGen spec
├── .github/workflows/build.yml    # GitHub Actions (build IPA unsigned)
├── Tools/
│   └── translate_catalog.py       # Script para traducir catalog.json (MyMemory API)
└── README.md                      # Este archivo
```

---

## 📜 Licencia

MIT — hacé lo que quieras con el código.
