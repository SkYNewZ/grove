import GroveKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section("Dossiers analysés") {
                ForEach(settings.scanRoots, id: \.self) { root in
                    HStack {
                        Text(root).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button {
                            settings.scanRoots.removeAll { $0 == root }
                            Task { await model.reload() }
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Retirer \(root)")
                    }
                }
                Button("Ajouter un dossier…") {
                    if let path = FolderPicker.choose(), !settings.scanRoots.contains(path) {
                        settings.scanRoots.append(path)
                        Task { await model.reload() }
                    }
                }
                Text("Grove ne cherche que dans ces dossiers (4 niveaux de profondeur).")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Barre de menus") {
                Stepper(
                    "Dépôts affichés : \(settings.menuBarLimit)", value: $settings.menuBarLimit,
                    in: AppSettings.menuBarLimits)
                Text("Les dépôts épinglés d'abord, puis les plus récemment actifs.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Claude Code") {
                Picker("Au clic sur ✦", selection: $settings.claudeMode) {
                    Text("Reprendre la dernière session si elle existe").tag(ClaudeLaunchMode.resumeLatest)
                    Text("Toujours démarrer une nouvelle session").tag(ClaudeLaunchMode.newSession)
                }
                .pickerStyle(.radioGroup)
            }

            Section("Expliquer (IA)") {
                Picker("Modèle", selection: $settings.explainModel) {
                    Text("Haiku — économique (recommandé)").tag(ExplainModel.haiku)
                    Text("Sonnet — plus fin, plus cher").tag(ExplainModel.sonnet)
                }
                Text(
                    "Utilise ton abonnement via la commande claude, sans outils, plafonné à 0,25 $ par appel."
                )
                .font(.caption).foregroundStyle(.secondary)
            }

            Section("Général") {
                Toggle("Ouvrir Grove à l'ouverture de session", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }

            Section("Outils détectés") {
                toolRow("git", model.tools.git)
                toolRow("gh (GitHub)", model.tools.gh)
                toolRow("glab (GitLab)", model.tools.glab)
                toolRow("claude", model.tools.claude)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 760)
    }

    private func toolRow(_ name: String, _ path: String?) -> some View {
        LabeledContent(name) {
            Text(path ?? "introuvable").foregroundStyle(path == nil ? .orange : .secondary)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Impossible de modifier l'ouverture à la connexion : \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
