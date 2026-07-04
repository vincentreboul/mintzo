import AppKit

/// Localise le menu principal macOS dans la langue de l'app (`MzStrings.ui`).
///
/// Pourquoi ce code existe : une app SwiftUI n'a pas de `MainMenu.xib`, et
/// macOS ne fournit AUCUNE localisation basque des menus standard
/// (Quitter / Services / Édition…). Le menu auto-généré reste donc en anglais
/// dès que le système n'est pas dans une langue traduite par Apple — d'où
/// « Quit Mintzo » alors que le reste de l'app est en français ou en basque.
///
/// On renomme les items EN PLACE — jamais l'action ni le raccourci, seulement
/// le titre —, en les identifiant par leur sélecteur (robuste à la structure du
/// menu). Le titre du menu d'app (nom du produit) n'est pas touché.
///
/// Idempotent : ré-appliqué quand une fenêtre devient active, car SwiftUI peut
/// reconstruire le menu après le lancement.
@MainActor
enum MainMenuLocalizer {

    static func localize() {
        guard let mainMenu = NSApp.mainMenu else { return }

        // 1. Titres des items, identifiés par leur sélecteur, sur tout l'arbre.
        retitleItems(in: mainMenu)

        // 2. App menu (premier sous-menu) : Réglages (⌘,) et Services,
        //    non identifiables par un sélecteur stable.
        if let appMenu = mainMenu.items.first?.submenu {
            for item in appMenu.items {
                if item.keyEquivalent == "," && item.keyEquivalentModifierMask == .command {
                    item.title = MzStrings.settings   // « Réglages… » · « Ezarpenak… »
                } else if let sub = item.submenu, sub === NSApp.servicesMenu {
                    item.title = servicesTitle
                    sub.title = servicesTitle
                }
            }
        }

        // 3. Titres des menus de premier niveau (hors app menu).
        retitleTopLevel(mainMenu)
    }

    // MARK: - Items par sélecteur

    /// Titre localisé pour chaque sélecteur d'item standard. Les items dont le
    /// titre est dynamique (plein écran « Activer/Quitter ») sont volontairement
    /// absents : les renommer casserait la bascule.
    private static var titlesBySelector: [String: String] {
        [
            "orderFrontStandardAboutPanel:": mpick("Mintzori buruz", "À propos de Mintzo", "About Mintzo"),
            "hide:": mpick("Ezkutatu Mintzo", "Masquer Mintzo", "Hide Mintzo"),
            "hideOtherApplications:": mpick("Ezkutatu besteak", "Masquer les autres", "Hide Others"),
            "unhideAllApplications:": mpick("Erakutsi guztiak", "Tout afficher", "Show All"),
            "terminate:": mpick("Irten Mintzotik", "Quitter Mintzo", "Quit Mintzo"),
            "undo:": mpick("Desegin", "Annuler", "Undo"),
            "redo:": mpick("Berregin", "Rétablir", "Redo"),
            "cut:": mpick("Ebaki", "Couper", "Cut"),
            "copy:": mpick("Kopiatu", "Copier", "Copy"),
            "paste:": mpick("Itsatsi", "Coller", "Paste"),
            "delete:": mpick("Ezabatu", "Supprimer", "Delete"),
            "selectAll:": mpick("Hautatu dena", "Tout sélectionner", "Select All"),
            "performMiniaturize:": mpick("Minimizatu", "Réduire", "Minimize"),
            "performZoom:": mpick("Zooma", "Zoom", "Zoom"),
            "arrangeInFront:": mpick("Ekarri guztiak aurrera", "Tout ramener au premier plan", "Bring All to Front"),
        ]
    }

    /// Parcourt récursivement le menu et renomme chaque item dont le sélecteur
    /// est connu, sans toucher aux actions ni aux raccourcis.
    private static func retitleItems(in menu: NSMenu) {
        let map = titlesBySelector
        for item in menu.items {
            if let action = item.action, let title = map[NSStringFromSelector(action)] {
                item.title = title
            }
            if let submenu = item.submenu {
                retitleItems(in: submenu)
            }
        }
    }

    // MARK: - Menus de premier niveau

    /// Renomme Édition / Présentation / Fenêtre / Aide. Le menu Fenêtre et le
    /// menu Aide sont identifiés de façon fiable via `NSApp` ; Édition via son
    /// contenu (présence de Coller) ; Présentation par élimination sur le titre.
    private static func retitleTopLevel(_ mainMenu: NSMenu) {
        let appMenu = mainMenu.items.first
        for topItem in mainMenu.items where topItem !== appMenu {
            guard let submenu = topItem.submenu else { continue }
            let newTitle: String?
            if submenu === NSApp.windowsMenu {
                newTitle = mpick("Leihoa", "Fenêtre", "Window")
            } else if submenu === NSApp.helpMenu {
                newTitle = mpick("Laguntza", "Aide", "Help")
            } else if submenu.items.contains(where: { $0.action.map(NSStringFromSelector) == "paste:" }) {
                newTitle = mpick("Editatu", "Édition", "Edit")
            } else {
                switch topItem.title {
                case "View", "Présentation": newTitle = mpick("Ikuspegia", "Présentation", "View")
                case "Edit", "Édition": newTitle = mpick("Editatu", "Édition", "Edit")
                case "Window", "Fenêtre": newTitle = mpick("Leihoa", "Fenêtre", "Window")
                case "Help", "Aide": newTitle = mpick("Laguntza", "Aide", "Help")
                default: newTitle = nil
                }
            }
            if let newTitle {
                topItem.title = newTitle
                submenu.title = newTitle
            }
        }
    }

    // MARK: - Chaînes

    private static var servicesTitle: String {
        mpick("Zerbitzuak", "Services", "Services")
    }

    /// Sélection eu/fr/en alignée sur la langue d'interface (`MzStrings.ui`),
    /// exactement comme le reste de l'app (menu bar, HUD, réglages).
    private static func mpick(_ eu: String, _ fr: String, _ en: String) -> String {
        switch MzStrings.ui {
        case .eu: eu
        case .fr: fr
        case .en: en
        }
    }
}
