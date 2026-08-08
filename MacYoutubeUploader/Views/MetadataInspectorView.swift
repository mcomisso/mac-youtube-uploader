import SwiftUI

struct MetadataInspectorView: View {
    @ObservedObject var preferences: PreferencesStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                InspectorField(title: "Title template", help: "{filename} and {date} are supported.") {
                    TextField("Title template", text: titleTemplateBinding)
                        .textFieldStyle(.plain)
                        .appInput()
                }

                InspectorField(title: "Description") {
                    TextEditor(text: descriptionTemplateBinding)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 92)
                        .appInput()
                }

                publishingPanel

                InspectorField(title: "Tags", help: "Separate tags with commas.") {
                    VStack(alignment: .leading, spacing: 9) {
                        if !preferences.metadata.tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 7) {
                                    ForEach(preferences.metadata.tags, id: \.self) { tag in
                                        Text(tag)
                                            .font(.caption.weight(.medium))
                                            .foregroundStyle(AppTheme.blue)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 5)
                                            .background(AppTheme.blueSoft, in: Capsule())
                                    }
                                }
                            }
                        }

                        TextField("travel, vlog, 4k", text: tagsBinding)
                            .textFieldStyle(.plain)
                            .appInput()
                    }
                }
            }
            .padding(18)
        }
        .background(AppTheme.surface)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "checklist.checked")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.blue)
                .frame(width: 28, height: 28)
                .background(AppTheme.blueSoft, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Metadata")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.text)

                Text("Defaults applied when videos enter the queue.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .appCard(padding: 12, background: AppTheme.field, border: AppTheme.line)
    }

    private var publishingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Publishing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.muted)

            Divider()
                .background(AppTheme.line)

            PublishingMenuRow(title: "Privacy", value: preferences.metadata.privacy.label) {
                ForEach(PrivacyStatus.allCases) { status in
                    Button {
                        setPrivacy(status)
                    } label: {
                        Label(
                            status.label,
                            systemImage: status == preferences.metadata.privacy ? "checkmark" : "circle"
                        )
                    }
                }
            }

            PublishingMenuRow(title: "Category", value: selectedCategoryName) {
                ForEach(YouTubeCategory.defaults) { category in
                    Button {
                        setCategory(category.id)
                    } label: {
                        Label(
                            category.name,
                            systemImage: category.id == selectedCategoryID ? "checkmark" : "circle"
                        )
                    }
                }
            }

            PublishingMenuRow(title: "Audience", value: preferences.metadata.kidsSafety.label) {
                ForEach(KidsSafetySelection.allCases) { selection in
                    Button {
                        setKidsSafety(selection)
                    } label: {
                        Label(
                            selection.label,
                            systemImage: selection == preferences.metadata.kidsSafety ? "checkmark" : "circle"
                        )
                    }
                }
            }

            Toggle("Allow embedding", isOn: allowEmbeddingBinding)
                .toggleStyle(.checkbox)
        }
        .font(.callout)
        .foregroundStyle(AppTheme.text)
        .appCard(padding: 14, background: AppTheme.surface, border: AppTheme.line)
    }

    private var titleTemplateBinding: Binding<String> {
        Binding {
            preferences.metadata.titleTemplate
        } set: { value in
            guard preferences.metadata.titleTemplate != value else { return }
            preferences.metadata.titleTemplate = value
        }
    }

    private var descriptionTemplateBinding: Binding<String> {
        Binding {
            preferences.metadata.descriptionTemplate
        } set: { value in
            guard preferences.metadata.descriptionTemplate != value else { return }
            preferences.metadata.descriptionTemplate = value
        }
    }

    private var selectedCategoryID: String {
        let categoryID = preferences.metadata.categoryID
        return YouTubeCategory.defaults.contains { $0.id == categoryID }
            ? categoryID
            : YouTubeCategory.defaults[0].id
    }

    private var selectedCategoryName: String {
        YouTubeCategory.name(for: selectedCategoryID)
    }

    private func setPrivacy(_ value: PrivacyStatus) {
        guard preferences.metadata.privacy != value else { return }
        preferences.metadata.privacy = value
    }

    private func setCategory(_ value: String) {
        guard YouTubeCategory.defaults.contains(where: { $0.id == value }),
              preferences.metadata.categoryID != value else {
            return
        }
        preferences.metadata.categoryID = value
    }

    private func setKidsSafety(_ value: KidsSafetySelection) {
        guard preferences.metadata.kidsSafety != value else { return }
        preferences.metadata.kidsSafety = value
    }

    private var allowEmbeddingBinding: Binding<Bool> {
        Binding {
            preferences.metadata.allowEmbedding
        } set: { value in
            guard preferences.metadata.allowEmbedding != value else { return }
            preferences.metadata.allowEmbedding = value
        }
    }

    private var tagsBinding: Binding<String> {
        Binding {
            preferences.metadata.tags.joined(separator: ", ")
        } set: { value in
            let tags = value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard preferences.metadata.tags != tags else { return }
            preferences.metadata.tags = tags
        }
    }
}

private struct InspectorField<Content: View>: View {
    var title: String
    var help: String?
    @ViewBuilder var content: Content

    init(title: String, help: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.help = help
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)

                Spacer()
            }

            content

            if let help {
                Text(help)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.muted)
            }
        }
        .appCard(padding: 14, background: AppTheme.surface, border: AppTheme.line)
    }
}

private struct PublishingMenuRow<MenuContent: View>: View {
    var title: String
    var value: String
    @ViewBuilder var menuContent: () -> MenuContent

    var body: some View {
        Menu {
            menuContent()
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.muted)

                    Text(value)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(AppTheme.text)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(AppTheme.field, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(AppTheme.line, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
