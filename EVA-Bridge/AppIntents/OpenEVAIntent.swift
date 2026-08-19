//
//  OpenEVAIntent.swift
//  Eva Copilot
//
//  App Intent para que Siri pueda abrir la app con frases como:
//    "Oye Siri, abrir EVA Copilot"
//    "Oye Siri, abrir Yoe"
//    "Oye Siri, abrir 7X"
//
//  Para configurar:
//    1. Compilar e instalar la app
//    2. Abrir Atajos (Shortcuts) en el iPhone
//    3. Crear nuevo atajo
//    4. Agregar acción: "Abrir app" → buscar "Eva Copilot" o "Yoe"
//    5. Opcional: cambiar el nombre del atajo a "Oye Yoe" y agregar
//       a "Oye Siri" para invocarlo por voz
//
//  iOS 16+ soporta AppIntents directamente. La app se abre en foreground
//  y la escucha continua arranca automáticamente (gracias al .task de
//  ContentView que llama a voice.start() al aparecer).
//

import AppIntents
import Foundation

@available(iOS 16.0, *)
struct OpenEVAIntent: AppIntent {
    static var title: LocalizedStringResource = "Abrir EVA Copilot"
    static var description = IntentDescription("Abre la app EVA Copilot y empieza a escuchar comandos en español, inglés o ruso para traducirlos al chino que entiende el asistente EVA de tu Zeekr 7X.")

    /// Esto hace que la app se abra en foreground cuando se ejecuta el intent.
    static var openAppWhenRun: Bool = true

    /// Frases que Siri reconoce para ejecutar este intent.
    /// El usuario puede agregar más en la app Atajos.
    static var voiceShortcutPhrases: [String] = [
        "Oye Siri, abrir EVA Copilot",
        "Oye Siri, abrir Yoe",
        "Oye Siri, abrir 7X",
        "Oye Siri, activar asistente del carro",
        "Oye Siri, traducir comando",
    ]

    func perform() async throws -> some IntentResult {
        // No necesitamos hacer nada aquí porque openAppWhenRun = true
        // se encarga de abrir la app. La lógica de la app se reanuda sola
        // cuando aparece en foreground.
        return .result()
    }
}
