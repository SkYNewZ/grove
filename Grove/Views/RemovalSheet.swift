import GroveKit
import SwiftUI

struct RemovalSheet: View {
    let review: RemovalReview
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var understood = false

    private var plan: RemovalPlan { review.plan }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Supprimer « \(plan.worktree.title) » ?").font(.title3.weight(.semibold))
            Text("\(review.repoName) · \(plan.worktree.path)")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)

            Label(
                "Le dossier part dans la Corbeille et les commits restent sauvegardés dans git (refs/grove-backup/*).",
                systemImage: "checkmark.shield"
            )
            .font(.callout)

            if let warning = plan.fetchWarning {
                Label(
                    "Le fetch a échoué, l'état « mergé » peut être en retard : \(warning)",
                    systemImage: "wifi.exclamationmark"
                )
                .font(.callout).foregroundStyle(.orange)
            }
            FileList(
                title: "Modifications non commitées", systemImage: "exclamationmark.triangle.fill",
                tint: .orange, items: plan.dirtyFiles)
            FileList(
                title: "Modifications masquées (assume-unchanged)", systemImage: "eye.slash", tint: .orange,
                items: plan.hiddenModifiedFiles)
            FileList(
                title: "Processus actifs dans ce dossier", systemImage: "bolt.fill", tint: .red,
                items: plan.runningProcesses)
            FileList(
                title: "Fichiers ignorés par git (conservés dans la Corbeille)",
                systemImage: "doc.badge.gearshape", tint: .secondary, items: plan.ignoredFiles)
            if !plan.collateralPruned.isEmpty {
                Text(
                    "Nettoyage git aussi : \(plan.collateralPruned.count) autre(s) worktree(s) dont le dossier n'existe plus (sauvegardés)."
                )
                .font(.caption).foregroundStyle(.secondary)
            }

            if plan.requiresStrongConfirmation {
                Toggle(
                    "Je comprends que ce travail non commité ne sera plus dans le dépôt (il reste dans la Corbeille).",
                    isOn: $understood
                )
                .toggleStyle(.checkbox)
            }

            HStack {
                Spacer()
                Button("Annuler", role: .cancel) {
                    model.removal = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("Mettre à la Corbeille", role: .destructive) {
                    model.confirmRemoval(strong: understood)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    (plan.requiresStrongConfirmation && !understood)
                        || model.busyWorktrees.contains(plan.worktree.path))
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}

private struct FileList: View {
    let title: String
    let systemImage: String
    let tint: Color
    let items: [String]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(title) (\(items.count))", systemImage: systemImage).font(.callout.weight(.medium))
                    .foregroundStyle(tint)
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(items.prefix(100), id: \.self) { Text($0).font(.caption.monospaced()) }
                        if items.count > 100 {
                            Text("… et \(items.count - 100) autres").font(.caption).foregroundStyle(
                                .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 90)
            }
        }
    }
}
