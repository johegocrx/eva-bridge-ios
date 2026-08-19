//
//  EVACopilotShortcuts.swift
//  Eva Copilot
//
//  Provider de Shortcuts para la app. Registra los AppIntents disponibles
//  en la galería de Atajos del iPhone.
//

import AppIntents
import Foundation

@available(iOS 16.0, *)
struct EVACopilotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenEVAIntent(),
            phrases: [
                "Abrir \(.applicationName)",
                "Activar \(.applicationName)",
                "Empezar a traducir con \(.applicationName)",
            ],
            shortTitle: "Abrir EVA Copilot",
            systemImageName: "car.fill"
        )
    }
}
