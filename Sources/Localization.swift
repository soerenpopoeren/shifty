// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 soerenpopoeren
// Shifty – use a Shimano Di2 to shift in Zwift and MyWhoosh. See LICENSE and CREDITS.md.

import Foundation
import SwiftUI

/// UI languages. "system" follows the macOS language and falls back to English.
enum Language: String, CaseIterable, Identifiable {
    case system, en, de, fr, es
    var id: String { rawValue }

    /// Shown in the language picker, always in the language's own name.
    var nativeName: String {
        switch self {
        case .system: return Localizer.shared.t(.systemLanguage)
        case .en: return "English"
        case .de: return "Deutsch"
        case .fr: return "Français"
        case .es: return "Español"
        }
    }

    /// Column in the string table.
    fileprivate var column: Int {
        switch self {
        case .en, .system: return 0
        case .de: return 1
        case .fr: return 2
        case .es: return 3
        }
    }
}

/// A text that is translated when it is shown, so it follows a language switch.
struct LText: Equatable {
    let key: L
    var args: [String] = []
    init(_ key: L, _ args: String...) { self.key = key; self.args = args }
}

final class Localizer: ObservableObject {
    static let shared = Localizer()

    @Published var language: Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
    }

    private init() {
        Migration.run()
        language = Language(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .system
    }

    /// The language actually used: the chosen one, or for "system" the first supported macOS language.
    var effective: Language {
        guard language == .system else { return language }
        for id in Locale.preferredLanguages {
            if let lang = Language(rawValue: String(id.prefix(2))), lang != .system { return lang }
        }
        return .en
    }

    func t(_ key: L, _ args: String...) -> String { format(key, args) }
    func t(_ text: LText) -> String { format(text.key, text.args) }

    private func format(_ key: L, _ args: [String]) -> String {
        let row = Self.table[key] ?? [key.rawValue]
        let template = row.indices.contains(effective.column) ? row[effective.column] : row[0]
        return args.isEmpty ? template : String(format: template, arguments: args.map { $0 as CVarArg })
    }

    /// Columns: English, German, French, Spanish. Placeholders are always %@.
    private static let table: [L: [String]] = [
        // Menu bar window
        .noDi2: ["No Di2", "Keine Di2", "Aucun Di2", "Ningún Di2"],
        .syncWithToGear: ["Sync with %@ (to gear %@)", "Mit %@ abgleichen (auf Gang %@)",
                          "Synchroniser avec %@ (rapport %@)", "Sincronizar con %@ (marcha %@)"],
        .setMiddle: ["Set to middle", "Auf Mitte setzen", "Mettre au milieu", "Poner en el medio"],
        .setGearOne: ["Set to gear 1", "Auf Gang 1", "Mettre au rapport 1", "Poner en marcha 1"],
        .syncing: ["syncing …", "gleiche ab …", "synchronisation …", "sincronizando …"],
        .connected: ["connected", "verbunden", "connecté", "conectado"],
        .pairing: ["pairing …", "koppelt …", "appairage …", "emparejando …"],
        .waiting: ["waiting", "wartet", "en attente", "esperando"],
        .off: ["off", "aus", "désactivé", "apagado"],
        .active: ["active", "aktiv", "actif", "activo"],
        .permissionMissing: ["needs permission", "Freigabe fehlt", "autorisation requise", "falta permiso"],
        .miniDisplay: ["Mini display", "Mini-Anzeige", "Mini-affichage", "Mini pantalla"],
        .settings: ["Settings", "Einstellungen", "Réglages", "Ajustes"],
        .quit: ["Quit Shifty", "Shifty beenden", "Quitter Shifty", "Salir de Shifty"],
        .harder: ["Harder", "Schwerer", "Plus dur", "Más duro"],
        .easier: ["Easier", "Leichter", "Plus facile", "Más fácil"],
        .dropLogo: ["Drop an image here to change the logo", "Logo-Bild hierher ziehen, um es zu ändern",
                    "Déposez une image ici pour changer le logo", "Arrastra una imagen aquí para cambiar el logo"],
        .gear: ["Gear", "Gang", "Rapport", "Marcha"],
        .zwiftHowTo: ["Connect Zwift", "Zwift verbinden", "Connecter Zwift", "Conectar Zwift"],
        .zwiftStep1: ["In Zwift, choose “Shifty Di2” as power source", "In Zwift bei Leistungsquelle „Shifty Di2“ wählen",
                      "Dans Zwift, choisissez « Shifty Di2 » comme source de puissance",
                      "En Zwift, elige «Shifty Di2» como fuente de potencia"],
        .zwiftStep2: ["Under Controls, choose “Shifty Di2”", "Bei Steuerung „Shifty Di2“ wählen",
                      "Sous Commandes, choisissez « Shifty Di2 »", "En Controles, elige «Shifty Di2»"],
        .zwiftStep3: ["Set the power source back to your trainer", "Leistungsquelle zurück auf deinen Trainer stellen",
                      "Remettez la source de puissance sur votre home trainer",
                      "Vuelve a poner tu rodillo como fuente de potencia"],
        .zwiftWhy: ["Zwift only finds Shifty as a power source first – that's why the detour.",
                    "Zwift findet Shifty zuerst nur als Leistungsquelle – daher der Umweg.",
                    "Zwift ne trouve d'abord Shifty que comme source de puissance – d'où le détour.",
                    "Zwift solo encuentra primero a Shifty como fuente de potencia; de ahí el rodeo."],
        .hintFinish: ["Zwift connected – last step: set the power source back to your trainer.",
                      "Zwift verbunden – letzter Schritt: Leistungsquelle zurück auf deinen Trainer.",
                      "Zwift connecté – dernière étape : remettez la source de puissance sur votre home trainer.",
                      "Zwift conectado. Último paso: vuelve a poner tu rodillo como fuente de potencia."],
        .hintActive: ["Zwift controls active – shifting works.", "Zwift-Steuerung aktiv – Schalten funktioniert.",
                      "Commandes Zwift actives – le changement de vitesse fonctionne.",
                      "Controles de Zwift activos: el cambio funciona."],
        .holdHelp: ["Hold a button to keep shifting until you let go.",
                    "Knopf gedrückt halten schaltet weiter, bis du loslässt.",
                    "Maintenez un bouton pour continuer à changer jusqu'à ce que vous le relâchiez.",
                    "Mantén pulsado un botón para seguir cambiando hasta que lo sueltes."],
        .transparency: ["Transparency", "Transparenz", "Transparence", "Transparencia"],
        .hideMini: ["Hide mini display", "Mini-Anzeige ausblenden", "Masquer le mini-affichage", "Ocultar mini pantalla"],

        // Settings
        .settingsTitle: ["Shifty – Settings", "Shifty – Einstellungen", "Shifty – Réglages", "Shifty – Ajustes"],
        .language: ["Language", "Sprache", "Langue", "Idioma"],
        .systemLanguage: ["System language", "Systemsprache", "Langue du système", "Idioma del sistema"],
        .gearCounter: ["Shifty's counter: gear %@ of %@", "Shiftys Zähler: Gang %@ von %@",
                       "Compteur de Shifty : rapport %@ sur %@", "Contador de Shifty: marcha %@ de %@"],
        .syncWith: ["Sync with %@", "Mit %@ abgleichen", "Synchroniser avec %@", "Sincronizar con %@"],
        .syncHelp: [
            "Neither app reports its gear. Zwift starts every ride in gear 8 – Shifty does the same when Zwift connects. MyWhoosh is synced the first time it connects after Shifty starts: all the way down to 1, then up to Shifty's gear. You can also sync by hand here (takes a few seconds).",
            "Beide Apps verraten ihren Gang nicht. Zwift beginnt jede Fahrt in Gang 8 – Shifty macht das beim Verbinden genauso. MyWhoosh wird beim ersten Verbinden nach dem Start von Shifty abgeglichen: ganz runter auf 1, dann hoch auf Shiftys Gang. Von Hand geht der Abgleich auch hier (dauert ein paar Sekunden).",
            "Aucune des deux apps n'indique son rapport. Zwift commence chaque sortie au rapport 8 – Shifty fait de même à la connexion. MyWhoosh est synchronisé à la première connexion après le démarrage de Shifty : descente jusqu'au rapport 1, puis remontée jusqu'à celui de Shifty. La synchronisation manuelle est aussi possible ici (quelques secondes).",
            "Ninguna de las dos apps indica su marcha. Zwift empieza cada salida en la marcha 8 y Shifty hace lo mismo al conectarse. MyWhoosh se sincroniza la primera vez que se conecta tras iniciar Shifty: baja hasta la marcha 1 y sube hasta la de Shifty. También puedes sincronizar a mano aquí (tarda unos segundos).",
        ],
        .noDi2Connected: ["No Di2 connected", "Keine Di2 verbunden", "Aucun Di2 connecté", "Ningún Di2 conectado"],
        .disconnect: ["Disconnect", "Trennen", "Déconnecter", "Desconectar"],
        .stop: ["Stop", "Stopp", "Arrêter", "Detener"],
        .search: ["Search", "Suchen", "Rechercher", "Buscar"],
        .connect: ["Connect", "Verbinden", "Connecter", "Conectar"],
        .channel: ["D-Fly channel %@", "D-Fly Kanal %@", "Canal D-Fly %@", "Canal D-Fly %@"],
        .holdRepeat: ["Hold = keep shifting", "Halten = weiterschalten", "Maintenir = changer en continu",
                      "Mantener = seguir cambiando"],
        .mapping: ["Button mapping", "Belegung", "Affectation des boutons", "Asignación de botones"],
        .mappingFooter: [
            "Assign the buttons to D-Fly channels in the Shimano E-TUBE app. Then click a channel here and choose “Learn” – Shifty recognises the button when you press it. The part lights up on every press.",
            "Die Knöpfe werden in der Shimano E-TUBE App auf D-Fly-Kanäle gelegt. Danach hier auf einen Kanal klicken und „Anlernen“ wählen – Shifty erkennt den Knopf, wenn du ihn drückst. Bei jedem Druck leuchtet das Teil auf.",
            "Affectez les boutons aux canaux D-Fly dans l'app Shimano E-TUBE. Cliquez ensuite sur un canal ici et choisissez « Apprendre » – Shifty reconnaît le bouton quand vous l'appuyez. La pièce s'allume à chaque pression.",
            "Asigna los botones a los canales D-Fly en la app Shimano E-TUBE. Después haz clic aquí en un canal y elige «Aprender»: Shifty reconoce el botón al pulsarlo. La pieza se ilumina con cada pulsación.",
        ],

        .left: ["Left", "Links", "Gauche", "Izquierda"],
        .right: ["Right", "Rechts", "Droite", "Derecha"],
        .channelShort: ["Ch %@", "Kanal %@", "Canal %@", "Canal %@"],
        .ofMax: ["of %@", "von %@", "sur %@", "de %@"],
        .logTitle: ["Log", "Protokoll", "Journal", "Registro"],
        .copy: ["Copy", "Kopieren", "Copier", "Copiar"],
        .showInFinder: ["Show in Finder", "Im Finder zeigen", "Afficher dans le Finder", "Mostrar en Finder"],
        .version: ["Version %@", "Version %@", "Version %@", "Versión %@"],
        .nothing: ["Nothing", "Nichts", "Rien", "Nada"],
        .buttonTop: ["Top button", "Oberer Knopf", "Bouton supérieur", "Botón superior"],
        .leverMain: ["Shift lever", "Schalthebel", "Levier de vitesses", "Maneta de cambio"],
        .leverSmall: ["Small lever", "Kleiner Hebel", "Petit levier", "Maneta pequeña"],
        .notDfly: ["Not D-Fly", "Kein D-Fly", "Pas D-Fly", "Sin D-Fly"],
        .learn: ["Learn: press the button on the bike", "Anlernen: Knopf am Rad drücken",
                 "Apprendre : appuyez sur le bouton du vélo", "Aprender: pulsa el botón en la bici"],
        .pressNow: ["Press it on the bike …", "Jetzt am Rad drücken …", "Appuyez sur le vélo …", "Púlsalo en la bici …"],
        .cancel: ["Cancel", "Abbrechen", "Annuler", "Cancelar"],

        // Actions
        .actionNone: ["– none –", "– nichts –", "– aucune –", "– ninguna –"],
        .actionShiftUp: ["Harder (gear up)", "Schwerer (Gang hoch)", "Plus dur (monter)", "Más duro (subir marcha)"],
        .actionShiftDown: ["Easier (gear down)", "Leichter (Gang runter)", "Plus facile (descendre)",
                           "Más fácil (bajar marcha)"],
        .actionUturn: ["U-turn", "U-Turn", "Demi-tour", "Cambio de sentido"],

        // Di2 status
        .stNotConnected: ["Not connected", "Nicht verbunden", "Non connecté", "No conectado"],
        .stScanning: ["Searching for Di2 … (press a lever to wake it up)",
                      "Suche Di2 … (Schalthebel kurz drücken, damit sie aufwacht)",
                      "Recherche du Di2 … (appuyez sur une manette pour le réveiller)",
                      "Buscando Di2 … (pulsa una maneta para despertarlo)"],
        .stConnecting: ["Connecting to %@ …", "Verbinde mit %@ …", "Connexion à %@ …", "Conectando con %@ …"],
        .stBluetoothReady: ["Bluetooth ready", "Bluetooth bereit", "Bluetooth prêt", "Bluetooth listo"],
        .stBluetoothUnauthorized: ["No Bluetooth access – allow it in System Settings",
                                   "Kein Bluetooth-Zugriff – in den Systemeinstellungen erlauben",
                                   "Pas d'accès Bluetooth – autorisez-le dans Réglages Système",
                                   "Sin acceso a Bluetooth: permítelo en Ajustes del Sistema"],
        .stBluetoothOff: ["Bluetooth is off", "Bluetooth ist aus", "Bluetooth est désactivé", "Bluetooth está apagado"],
        .stBluetoothUnavailable: ["Bluetooth not available", "Bluetooth nicht verfügbar", "Bluetooth indisponible",
                                  "Bluetooth no disponible"],
        .stReadingServices: ["Connected, reading services …", "Verbunden, lese Dienste …",
                             "Connecté, lecture des services …", "Conectado, leyendo servicios …"],
        .stConnectFailed: ["Connection failed: %@", "Verbindung fehlgeschlagen: %@", "Échec de la connexion : %@",
                           "Error de conexión: %@"],
        .stDisconnected: ["Disconnected", "Getrennt", "Déconnecté", "Desconectado"],
        .stWaitingForDi2: ["Waiting for Di2 … (press a lever to wake it up)", "Warte auf Di2 … (Hebel drücken zum Aufwecken)",
                           "En attente du Di2 … (appuyez sur une manette)", "Esperando al Di2 … (pulsa una maneta)"],
        .stNoDfly: ["D-Fly service not found – is this a Di2?", "D-Fly-Dienst nicht gefunden – ist das eine Di2?",
                    "Service D-Fly introuvable – est-ce bien un Di2 ?", "Servicio D-Fly no encontrado: ¿es un Di2?"],
        .stNoChannels: ["D-Fly channels not found", "D-Fly-Kanäle nicht gefunden", "Canaux D-Fly introuvables",
                        "Canales D-Fly no encontrados"],
        .stSubscribeFailed: ["Subscription failed: %@", "Abo fehlgeschlagen: %@", "Échec de l'abonnement : %@",
                             "Error de suscripción: %@"],
        .stReady: ["Ready – press a D-Fly button", "Bereit – drück einen D-Fly-Knopf", "Prêt – appuyez sur un bouton D-Fly",
                   "Listo: pulsa un botón D-Fly"],
    ]
}

/// Short access to the current translation, for views.
func t(_ key: L, _ args: String...) -> String {
    var text = LText(key)
    text.args = args
    return Localizer.shared.t(text)
}

/// Keys of all translated texts.
enum L: String {
    case noDi2, syncWithToGear, setMiddle, setGearOne, syncing, connected, pairing, waiting, off, active
    case permissionMissing, miniDisplay, settings, quit, harder, easier, dropLogo, gear, hideMini, transparency
    case holdHelp
    case zwiftHowTo, zwiftStep1, zwiftStep2, zwiftStep3, zwiftWhy, hintFinish, hintActive
    case settingsTitle, language, systemLanguage, gearCounter, syncWith, syncHelp, noDi2Connected
    case disconnect, stop, search, connect, channel, holdRepeat, mapping, mappingFooter
    case left, right, channelShort, ofMax, logTitle, copy, showInFinder, version, nothing
    case buttonTop, leverMain, leverSmall, notDfly, learn, pressNow, cancel
    case actionNone, actionShiftUp, actionShiftDown, actionUturn
    case stNotConnected, stScanning, stConnecting, stBluetoothReady, stBluetoothUnauthorized, stBluetoothOff
    case stBluetoothUnavailable, stReadingServices, stConnectFailed, stDisconnected, stWaitingForDi2
    case stNoDfly, stNoChannels, stSubscribeFailed, stReady
}
