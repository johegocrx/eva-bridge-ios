//
//  VoiceService.swift
//  Eva Copilot
//
//  Servicio de escucha continua (foreground). Sin wake word en español.
//  Flujo:
//    1. App se abre → permisos → empieza a escuchar en silencio
//    2. Usuario dice algo en español → recognizer transcribe (partials)
//    3. Cuando hay 1.5s de silencio (debounce) o llega final result → busca match
//    4. Dice "嗨伊娃" + comando en chino
//    5. Vuelve a escuchar (auto-ciclo)
//
//  iOS puede suspender la app en background. Funciona bien en foreground
//  (ej. el iPhone apoyado en el soporte del auto, app abierta).
//

import Foundation
import AVFoundation
import Combine

@MainActor
final class VoiceService: ObservableObject {

    enum State: String {
        case idle = "Toca el micrófono"
        case listening = "Escuchando..."
        case translating = "Traduciendo..."
        case speaking = "Hablando a EVA"
        case stopped = "Detenido"
        case awaitingConfirmation = "Esperando tu confirmación"
    }

    @Published var state: State = .idle
    @Published var lastTranscript: String = ""
    @Published var lastMatch: EvaCommand?
    @Published var permissionGranted: Bool = false
    @Published var infoMessage: String = ""
    /// Todos los matches del último comando (para mostrar en la lista)
    @Published var lastMatches: [CatalogMatch] = []
    /// El match pendiente de confirmación cuando el modo seguro lo requiere
    @Published var pendingMatch: CatalogMatch?
    /// Cuando es true, se pide confirmación al usuario antes de ejecutar cualquier
    /// match con confidence < safeModeThreshold. Persistido en UserDefaults.
    @Published var safeMode: Bool = true {
        didSet { UserDefaults.standard.set(safeMode, forKey: "safeMode") }
    }
    /// Umbral de confidence (0-1) por encima del cual se ejecuta sin pedir
    /// confirmación, incluso con modo seguro activado.
    @Published var safeModeThreshold: Double = 0.7 {
        didSet { UserDefaults.standard.set(safeModeThreshold, forKey: "safeModeThreshold") }
    }
    /// Locale del ASR (es-MX, en-US, ru-RU). Cambio de idioma reinicia
    /// el recognizer. El corpus del matcher se mantiene (ya incluye en/ru).
    @Published var speechLocale: String = "es-MX" {
        didSet {
            UserDefaults.standard.set(speechLocale, forKey: "speechLocale")
            speech.setLocale(speechLocale)
            // Reiniciar escucha para que tome el nuevo recognizer
            if state == .listening || state == .idle {
                speech.stopListening()
                beginListeningCycle()
            }
        }
    }
    /// Nombre display del locale actual
    var speechLocaleDisplay: String { speech.currentLocaleDisplay }

    private let speech: SpeechManager
    private let tts: TTSManager
    private let matcher: CatalogMatcher
    private let history: CommandHistory

    /// El último input transcrito, para guardar en el historial al ejecutar
    private var lastInputForHistory: String = ""

    // Debounce: si el último partial no cambia por este tiempo, procesar
    private var debounceTimer: Timer?
    private let debounceInterval: TimeInterval = 1.5
    private var lastPartialText: String = ""
    private var processing: Bool = false

    init(speech: SpeechManager, tts: TTSManager, matcher: CatalogMatcher, history: CommandHistory) {
        self.speech = speech
        self.tts = tts
        self.matcher = matcher
        self.history = history

        // Cargar settings persistidos en UserDefaults.
        // Para el primer launch (key no existe), UserDefaults devuelve 0/false
        // para tipos primitivos. Usamos `object(forKey:)` para detectar
        // si el key existe y settear el default solo en ese caso.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "safeMode") == nil {
            defaults.set(true, forKey: "safeMode")
        }
        self.safeMode = defaults.bool(forKey: "safeMode")
        if defaults.object(forKey: "safeModeThreshold") == nil {
            defaults.set(0.7, forKey: "safeModeThreshold")
        }
        self.safeModeThreshold = defaults.double(forKey: "safeModeThreshold")
        // Callbacks del speech manager
        self.speech.onPartialResult = { [weak self] text in
            self?.handlePartial(text)
        }
        self.speech.onFinalResult = { [weak self] text in
            self?.handleFinal(text)
        }
        // Si el recognizer termina solo (timeout / no speech), reiniciar
        self.speech.onAutoRestartNeeded = { [weak self] in
            guard let self = self else { return }
            if self.state == .listening && !self.processing {
                self.beginListeningCycle()
            }
        }
    }

    func start() async {
        let granted = await speech.requestPermissions()
        self.permissionGranted = granted
        if granted {
            beginListeningCycle()
        }
    }

    func stop() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        // Mejora #6: pause en vez de stop. El recognizer sigue activo para
        // detectar "oye yoe" / "empezar" / etc. y reanudar automáticamente.
        speech.pauseListening()
        tts.stop()
        pendingMatch = nil
        lastMatches = []
        state = .stopped
        infoMessage = "⏸️ Detenido. Decí \"oye Yoe\" o \"empezar\" para reiniciar."
    }

    /// Botón de pánico: cancela TODO inmediatamente. Más agresivo que stop().
    /// Usado cuando el user quiere un kill switch de emergencia.
    func panic() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        processing = false
        speech.stopListening()
        tts.stop()
        pendingMatch = nil
        lastMatches = []
        lastMatch = nil
        state = .idle
        infoMessage = "🛑 PÁNICO: todo detenido. Toca el micrófono o decí \"oye Yoe\" para reiniciar."
    }

    private func beginListeningCycle() {
        debounceTimer?.invalidate()
        debounceTimer = nil
        processing = false
        state = .listening
        infoMessage = "Decí tu comando en español"
        lastTranscript = ""
        lastPartialText = ""
        lastMatch = nil
        // lastMatches se mantiene para que el usuario vea el último resultado
        speech.startListening()
    }

    private func handlePartial(_ text: String) {
        // Si está pausado, chequear si es un start command. Si lo es,
        // volver a listening.
        if state == .stopped {
            if WakeWordDetector.isStartCommand(text) {
                // El user quiere reanudar. Arrancamos el ciclo.
                lastTranscript = ""
                lastPartialText = ""
                infoMessage = "👂 Reanudando..."
                speech.resumeListening()  // manuallyStopped = false
                beginListeningCycle()      // resetea state y processing
            }
            // Si no es start command, descartar
            return
        }

        // Si está esperando confirmación, el user está diciendo algo
        // para elegir opción. Procesar inmediatamente.
        if state == .awaitingConfirmation {
            lastTranscript = text
            lastPartialText = text
            handleConfirmationInput(text)
            return
        }

        guard state == .listening, !processing else { return }
        lastTranscript = text
        lastPartialText = text
        lastInputForHistory = text  // para el historial

        // Reiniciar timer de debounce. Cuando el usuario deje de hablar
        // (1.5s sin cambios), procesamos el último texto.
        debounceTimer?.invalidate()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    guard self.state == .listening, !self.processing else { return }
                    let t = self.lastPartialText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty {
                        self.processCommand(t)
                    }
                }
            }
        }
    }

    private func handleFinal(_ text: String) {
        // Si está pausado, chequear si es un start command.
        if state == .stopped {
            if WakeWordDetector.isStartCommand(text) {
                speech.resumeListening()
                beginListeningCycle()
            }
            return
        }

        // Si está esperando confirmación, procesar el input directamente
        // (sin debounce porque es una respuesta corta: "uno", "dos", etc.)
        if state == .awaitingConfirmation {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            lastTranscript = trimmed
            lastInputForHistory = trimmed
            handleConfirmationInput(trimmed)
            return
        }

        // El recognizer dio un final result. Procesar inmediatamente.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        lastTranscript = trimmed
        lastInputForHistory = trimmed
        debounceTimer?.invalidate()
        debounceTimer = nil
        guard !trimmed.isEmpty else {
            if !processing && state == .listening {
                beginListeningCycle()
            }
            return
        }
        if !processing {
            processCommand(trimmed)
        }
    }

    /// Maneja el input del user cuando state == .awaitingConfirmation.
    /// Detecta:
    /// 1) Comandos de cancel ("cancelar", "no", "nada")
    /// 2) Números 1-8 (palabras o dígitos) para seleccionar opción
    /// 3) Cualquier otra cosa → pide que diga un número
    func handleConfirmationInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if processing { return }
        processing = true

        if WakeWordDetector.isCancelCommand(trimmed) {
            cancelConfirmation()
            return
        }
        if let num = WakeWordDetector.extractOptionNumber(trimmed),
           num >= 1, num <= lastMatches.count {
            confirmMatch(lastMatches[num - 1])
            return
        }
        // Si dice otra cosa, le pedimos que diga un número
        if !lastMatches.isEmpty {
            infoMessage = pickNumberInfoText()
            speakEnumerationReminder(options: lastMatches)
            // processing = false y volver a listening
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.processing = false
                self?.beginListeningCycle()
            }
        }
    }

    private func processCommand(_ text: String) {
        guard !processing else { return }
        processing = true
        debounceTimer?.invalidate()
        debounceTimer = nil
        state = .translating
        speech.stopListening()

        // Comandos de stop
        if WakeWordDetector.isStopCommand(text) {
            tts.speakInSpanish("Cancelado. Decí \"oye Yoe\" para volver.")
            state = .stopped
            infoMessage = "⏸️ Detenido. Decí \"oye Yoe\" o \"empezar\" para reiniciar."
            lastMatches = []
            pendingMatch = nil
            processing = false
            return
        }

        // Si está esperando confirmación, el user puede:
        // 1) Decir "cancelar" / "no" → cancelar
        // 2) Decir un número (1-8) → seleccionar esa opción
        // 3) Tocar una opción en la lista (vía confirmMatch)
        if state == .awaitingConfirmation {
            if WakeWordDetector.isCancelCommand(text) {
                cancelConfirmation()
                return
            }
            if let num = WakeWordDetector.extractOptionNumber(text), num >= 1, num <= lastMatches.count {
                confirmMatch(lastMatches[num - 1])
                return
            }
            // Si dice otra cosa que no es número ni cancel, le pedimos
            // que elija un número
            if !lastMatches.isEmpty {
                infoMessage = "Decí el número de la opción que querés (1 a \(lastMatches.count)), o \"cancelar\"."
                speakEnumerationReminder(options: lastMatches)
                processing = false
                beginListeningCycle()
                return
            }
        }

        // Buscar en catálogo
        let results = matcher.search(text)
        if results.isEmpty {
            handleNoMatch(text: text)
            return
        }

        let best = results.first!

        // MODO SEGURO: si está activado y la confidence del mejor match es baja,
        // NO ejecutar. En su lugar, mostrar candidatos y pedir confirmación.
        if safeMode && best.confidence < safeModeThreshold {
            pendingMatch = best
            lastMatches = Array(results.prefix(5))
            state = .awaitingConfirmation
            // CRÍTICO: resetear processing para que handleConfirmationInput
            // pueda procesar el siguiente input del usuario. Si no, el
            // guard `if processing { return }` en handleConfirmationInput
            // bloquea todo.
            processing = false
            infoMessage = "¿Quisiste decir: \"\(best.command.es)\"? Decí el número de la opción (1 a \(lastMatches.count))."
            speakConfirmationPrompt(options: Array(results.prefix(5)))
            return
        }

        // Confidence alta o modo seguro desactivado → ejecutar
        executeMatch(best, allResults: results)
    }

    /// Ejecuta un match confirmado. Habla el wake word + el comando a EVA y
    /// vuelve a escuchar.
    private func executeMatch(_ match: CatalogMatch, allResults: [CatalogMatch]? = nil) {
        lastMatch = match.command
        if let all = allResults {
            lastMatches = Array(all.prefix(5))
        }
        pendingMatch = nil
        state = .speaking
        infoMessage = "→ \(match.command.zh)"

        // Guardar en historial
        let wasConfirmed = (allResults != nil)  // vino de un confirmMatch()
        let inputSnapshot = lastInputForHistory
        let conf = match.confidence
        history.add(
            inputEs: inputSnapshot,
            command: match.command,
            confidence: conf,
            wasConfirmed: wasConfirmed
        )

        let cmdToRun = match.command
        tts.speak("嗨伊娃", completion: { [weak self] in
            guard let self = self else { return }
            self.tts.speakCommand(cmdToRun, completion: { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.beginListeningCycle()
                }
            })
        })
    }

    /// El usuario tocó un candidato en la lista de confirmación. Ejecuta ese
    /// match (no necesariamente el best original).
    func confirmMatch(_ match: CatalogMatch) {
        guard state == .awaitingConfirmation else { return }
        processing = true  // evita que el ciclo de escucha dispare otro processCommand
        executeMatch(match, allResults: lastMatches)
    }

    /// Cancela la confirmación pendiente. Sirve tanto para un toque en la UI
    /// como para el comando de voz "cancelar".
    func cancelConfirmation() {
        pendingMatch = nil
        lastMatches = []
        state = .listening
        infoMessage = "Cancelado. Decí tu comando."
        tts.speakInSpanish("Cancelado.", completion: { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.beginListeningCycle()
            }
        })
    }

    /// Maneja el caso de no match. Por ahora: pide que reintente.
    /// (La mejora #2 va a ampliar esto para sugerir alternativas por categoría.)
    private func handleNoMatch(text: String) {
        // Intentar encontrar alternativas por categoría antes de rendirse.
        let alternatives = matcher.searchByCategory(text)
        if !alternatives.isEmpty {
            // Mostrar las alternativas como matches (sin confidence, score=0, maxScore=0 → conf=0)
            let altMatches = alternatives.enumerated().map { idx, cmd in
                CatalogMatch(command: cmd, score: 1, maxScore: 10)
            }
            lastMatches = altMatches
            infoMessage = "No encontré ese comando exacto. ¿Quisiste alguna de estas opciones? Decí el número (1 a \(altMatches.count))."
            // Pasamos a estado awaitingConfirmation para que el user pueda elegir
            // por voz con un número, igual que en modo seguro.
            state = .awaitingConfirmation
            pendingMatch = altMatches.first
            // CRÍTICO: resetear processing para que handleConfirmationInput
            // pueda procesar el siguiente input del usuario.
            processing = false
            let intro = noMatchIntroText()
            speakEnumerationPrompt(options: altMatches, intro: intro)
            return
        } else {
            infoMessage = noMatchInfoText()
            lastMatches = []
            pendingMatch = nil
            tts.speakInLocale(noMatchInfoText(), locale: speechLocale, completion: { [weak self] in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    self?.beginListeningCycle()
                }
            })
        }
    }

    /// Texto del intro cuando no hay match (en el idioma del ASR)
    private func noMatchIntroText() -> String {
        switch speechLocale {
        case "en-US": return "I didn't understand, but I found these options:"
        case "ru-RU": return "Я не понял, но нашёл эти варианты:"
        default: return "No entendí, pero encontré estas opciones:"
        }
    }

    // MARK: - Textos de feedback en el idioma del ASR

    private func stopConfirmText() -> String {
        switch speechLocale {
        case "en-US": return "Stopped. Say \"oye Yoe\" to resume."
        case "ru-RU": return "Остановлено. Скажите \"ойе Ё\" для возобновления."
        default: return "Cancelado. Decí \"oye Yoe\" para volver."
        }
    }

    private func stoppedInfoText() -> String {
        switch speechLocale {
        case "en-US": return "⏸️ Stopped. Say \"oye Yoe\" or \"start\" to resume."
        case "ru-RU": return "⏸️ Остановлено. Скажите \"ойе Ё\" или \"начать\" для возобновления."
        default: return "⏸️ Detenido. Decí \"oye Yoe\" o \"empezar\" para reiniciar."
        }
    }

    private func pickNumberInfoText() -> String {
        switch speechLocale {
        case "en-US": return "Say the number of the option (1 to \(lastMatches.count)), or \"cancel\"."
        case "ru-RU": return "Скажите номер варианта (от 1 до \(lastMatches.count)), или \"отмена\"."
        default: return "Decí el número de la opción (1 a \(lastMatches.count)), o \"cancelar\"."
        }
    }

    private func cancelText() -> String {
        switch speechLocale {
        case "en-US": return "Cancelled."
        case "ru-RU": return "Отменено."
        default: return "Cancelado."
        }
    }

    /// Texto del infoMessage cuando no hay match (en el idioma del ASR)
    private func noMatchInfoText() -> String {
        switch speechLocale {
        case "en-US": return "I didn't understand. Try other words."
        case "ru-RU": return "Я не понял. Попробуйте другие слова."
        default: return "No te entendí. Probá con otras palabras."
        }
    }

    /// Helper: devuelve la primera palabra significativa del texto.
    private func firstToken(_ text: String) -> String {
        let parts = text.split(separator: " ").map(String.init)
        return parts.first(where: { $0.count > 2 }) ?? text
    }

    /// Pregunta en español si el usuario quiso decir alguno de los candidatos.
    /// Enumera todas las opciones con número para que el user pueda decir
    /// "la uno", "la dos", etc.
    private func speakConfirmationPrompt(options: [CatalogMatch]) {
        speakEnumerationPrompt(options: options, intro: "Elige una opción:")
    }

    /// Lee en voz alta una lista enumerada de opciones. Formato:
    /// "Elige una opción. Opción uno: <es>. Opción dos: <es>. ..."
    /// USA LA VOZ DEL LOCALE DEL ASR (es/en/ru) para que el user entienda
    /// en el idioma que está hablando.
    private func speakEnumerationPrompt(options: [CatalogMatch], intro: String) {
        guard !options.isEmpty else { return }
        let text = enumerationText(options: options, intro: intro)
        tts.speakInLocale(text, locale: speechLocale, completion: nil)
    }

    /// Construye el texto enumerado según el locale del ASR.
    /// En español: "Opción uno: <es>"
    /// En inglés: "Option one: <es>" (o usa el campo 'en' si existe)
    /// En ruso: usa el campo 'ru' si existe
    private func enumerationText(options: [CatalogMatch], intro: String) -> String {
        let lang = speechLocale
        var parts: [String] = [intro]
        for (idx, m) in options.prefix(5).enumerated() {
            let num = idx + 1
            let optionLabel: String
            let optionText: String
            switch lang {
            case "en-US":
                optionLabel = "Option \(numberWordEnglish(num))"
                optionText = m.command.en ?? m.command.es
            case "ru-RU":
                optionLabel = "Вариант \(numberWordRussian(num))"
                optionText = m.command.ru ?? m.command.es
            default: // es-MX
                optionLabel = "Opción \(numberWordSpanish(num))"
                optionText = m.command.es
            }
            parts.append("\(optionLabel): \(optionText)")
        }
        // Prompt final también en el idioma
        let finalPrompt: String
        switch lang {
        case "en-US": finalPrompt = "Say the number, or cancel."
        case "ru-RU": finalPrompt = "Скажите номер, или отмена."
        default: finalPrompt = "Decí el número de la que querés, o cancelar."
        }
        parts.append(finalPrompt)
        return parts.joined(separator: ". ")
    }

    /// Recordatorio: si el user dice algo que no es un número durante
    /// awaitingConfirmation, le recordamos las opciones.
    private func speakEnumerationReminder(options: [CatalogMatch]) {
        speakEnumerationPrompt(options: options, intro: "Por favor, decí un número.")
    }

    /// Convierte un número 1-8 a su palabra en español.
    private func numberWordSpanish(_ n: Int) -> String {
        switch n {
        case 1: return "uno"
        case 2: return "dos"
        case 3: return "tres"
        case 4: return "cuatro"
        case 5: return "cinco"
        case 6: return "seis"
        case 7: return "siete"
        case 8: return "ocho"
        default: return "\(n)"
        }
    }

    /// Convierte un número 1-8 a su palabra en inglés.
    private func numberWordEnglish(_ n: Int) -> String {
        switch n {
        case 1: return "one"
        case 2: return "two"
        case 3: return "three"
        case 4: return "four"
        case 5: return "five"
        case 6: return "six"
        case 7: return "seven"
        case 8: return "eight"
        default: return "\(n)"
        }
    }

    /// Convierte un número 1-8 a su palabra en ruso.
    private func numberWordRussian(_ n: Int) -> String {
        switch n {
        case 1: return "один"
        case 2: return "два"
        case 3: return "три"
        case 4: return "четыре"
        case 5: return "пять"
        case 6: return "шесть"
        case 7: return "семь"
        case 8: return "восемь"
        default: return "\(n)"
        }
    }
}
