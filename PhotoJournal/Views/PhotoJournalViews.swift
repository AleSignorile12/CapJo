import SwiftUI
import UIKit

struct PolaroidCard: View {
    let entry: JournalEntry
    let image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let image {
                        GeometryReader { geometry in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .clipped()
                        }
                        .aspectRatio(1, contentMode: .fit)
                    } else {
                        Rectangle()
                            .fill(.quaternary)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay { Image(systemName: "photo").foregroundStyle(.secondary) }
                    }
                }

                if let emoji = entry.mood, !emoji.isEmpty {
                    EmojiBubble(emoji: emoji)
                        .offset(x: -10, y: 16)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, (entry.mood ?? "").isEmpty ? 0 : 20)

            VStack(alignment: .leading, spacing: 6) {
                Text("“\(entry.prompt)”")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Label(entry.displayCategory, systemImage: "square.grid.2x2")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !entry.caption.isEmpty {
                    Text(entry.caption)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 14)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this journal photo")
    }
}

struct JournalEntryDetailView: View {
    @EnvironmentObject private var journal: JournalStore
    @Environment(\.dismiss) private var dismiss
    let entry: JournalEntry
    @State private var caption: String
    @State private var mood: String
    @State private var showSaved = false
    @State private var showDeleteConfirmation = false
    @State private var showPhotoSaveMessage = false
    @State private var photoSaveMessage = ""
    @State private var isSavingToPhotos = false

    init(entry: JournalEntry) {
        self.entry = entry
        _caption = State(initialValue: entry.caption)
        _mood = State(initialValue: entry.mood ?? "")
    }

    private var isFavorite: Bool {
        journal.entries.first(where: { $0.id == entry.id })?.isFavorite ?? entry.isFavorite ?? false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let image = journal.image(for: entry) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 6)
                        .padding(.horizontal, 12)
                }

                VStack(spacing: 6) {
                    EmojiPickerButton(emoji: $mood)
                    Text(mood.isEmpty ? "Tap + to add an emoji to this photo." : "Tap the emoji to change it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text("“\(entry.prompt)”")
                        .font(.title2.weight(.semibold))
                    Label(entry.displayCategory, systemImage: "square.grid.2x2")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(entry.date.formatted(date: .complete, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                TextField("Add a caption", text: $caption, axis: .vertical)
                    .lineLimit(3...8)
                    .padding(14)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Photo caption")

            }
            .padding()
        }
        .background(JournalTheme.background.ignoresSafeArea())
        .navigationTitle("Your moment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    journal.updateDetails(for: entry, caption: caption, song: entry.song ?? "", mood: mood)
                    showSaved = true
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    journal.toggleFavorite(entry)
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? .red : .primary)
                        .symbolEffect(.bounce, value: isFavorite)
                }
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        savePhotoToLibrary()
                    } label: {
                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isSavingToPhotos)
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Photo", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More photo actions")
            }
        }
        .alert("Details saved", isPresented: $showSaved) {
            Button("OK", role: .cancel) { }
        }
        .alert("PhotoJournal", isPresented: $showPhotoSaveMessage) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(photoSaveMessage)
        }
        .confirmationDialog("Delete this photo?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Photo", role: .destructive) {
                journal.delete(entry)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the photo from your journal. A copy saved to Photos will stay there.")
        }
    }

    private func savePhotoToLibrary() {
        guard let image = journal.image(for: entry) else {
            photoSaveMessage = "This photo could not be opened."
            showPhotoSaveMessage = true
            return
        }
        isSavingToPhotos = true
        Task {
            do {
                try await PhotoLibrarySaver.save(image)
                photoSaveMessage = "Saved to Photos."
            } catch {
                photoSaveMessage = error.localizedDescription
            }
            isSavingToPhotos = false
            showPhotoSaveMessage = true
        }
    }

}

private struct EmojiBubble: View {
    let emoji: String

    var body: some View {
        Text(emoji)
            .font(.system(size: 22))
            .frame(width: 40, height: 40)
            .background(.regularMaterial, in: Circle())
            .overlay { Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1) }
            .shadow(color: .black.opacity(0.16), radius: 5, x: 0, y: 2)
            .accessibilityLabel("Photo emoji: \(emoji)")
    }
}

private struct EmojiPickerButton: View {
    @Binding var emoji: String
    @State private var isShowingPicker = false

    var body: some View {
        Button {
            isShowingPicker = true
        } label: {
            Group {
                if emoji.isEmpty {
                    Image(systemName: "plus")
                        .font(.headline)
                        .foregroundStyle(.primary)
                } else {
                    Text(emoji)
                        .font(.system(size: 22))
                }
            }
            .frame(width: 40, height: 40)
            .background(.regularMaterial, in: Circle())
            .overlay { Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1) }
            .shadow(color: .black.opacity(0.16), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(emoji.isEmpty ? "Add one emoji to this photo" : "Change photo emoji")
        .accessibilityHint("Opens a picker with emoji only. Choose one emoji to show in a bubble on the photo.")
        .sheet(isPresented: $isShowingPicker) {
            EmojiPickerSheet(selectedEmoji: $emoji)
        }
    }
}

private struct EmojiPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedEmoji: String
    @State private var selectedGroup: EmojiCatalogGroup = .smileys
    @State private var searchText = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)

    private var visibleEmojis: [EmojiItem] {
        if searchText.isEmpty {
            return selectedGroup.emojis
        }
        return EmojiCatalog.search(searchText)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if searchText.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(EmojiCatalogGroup.allCases) { group in
                                Button(group.title) { selectedGroup = group }
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(selectedGroup == group ? Color.accentColor.opacity(0.16) : Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
                            }
                        }
                    }
                }

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(visibleEmojis) { item in
                            Button {
                                selectedEmoji = item.emoji
                                dismiss()
                            } label: {
                                Text(item.emoji)
                                    .font(.title2)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .background(selectedEmoji == item.emoji ? Color.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(item.name)
                        }
                    }
                }
            }
            .padding()
            .searchable(text: $searchText, prompt: "Search emoji")
            .navigationTitle("Choose one emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !selectedEmoji.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Remove", role: .destructive) {
                            selectedEmoji = ""
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct PhotoReviewView: View {
    @EnvironmentObject private var journal: JournalStore
    @Environment(\.dismiss) private var dismiss

    let photo: CapturedPhoto
    let prompt: String
    let category: String
    let challengeID: String?
    @State private var caption = ""
    @State private var mood = ""
    @State private var saveToPhotos = false
    @State private var isSaving = false
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack(alignment: .bottomTrailing) {
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 330)
                            .frame(maxWidth: .infinity)
                        EmojiPickerButton(emoji: $mood)
                            .offset(x: -10, y: 16)
                    }
                    .padding(.bottom, 16)
                    .listRowBackground(Color.clear)
                    Text(mood.isEmpty ? "Tap + to add one emoji to your photo." : "Tap the emoji to change it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                Section("Today's prompt") {
                    Text("“\(prompt)”")
                    LabeledContent("Category", value: category)
                }
                Section("Caption") {
                    TextField("Add a note about this moment", text: $caption, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Toggle(isOn: $saveToPhotos) {
                        Label("Also save to Photos", systemImage: "square.and.arrow.down")
                    }
                    Text("Your journal keeps its own copy. Photos access is only requested if you turn this on.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(JournalTheme.background.ignoresSafeArea())
            .navigationTitle("Save your moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        saveEntry()
                    }
                    .disabled(isSaving)
                }
            }
            .alert("Photo journal", isPresented: $showAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text(alertMessage)
            }
        }
    }

    private func saveEntry() {
        isSaving = true
        Task {
            guard journal.add(
                image: photo.image,
                prompt: prompt,
                category: category,
                caption: caption,
                song: "",
                mood: mood,
                challengeID: challengeID
            ) else {
                alertMessage = "The photo could not be saved. Please try again."
                showAlert = true
                isSaving = false
                return
            }

            if saveToPhotos {
                do {
                    try await PhotoLibrarySaver.save(photo.image)
                    alertMessage = "Saved to your journal and Photos."
                } catch {
                    alertMessage = "Saved to your journal. \(error.localizedDescription)"
                }
            } else {
                alertMessage = "Saved to your journal."
            }
            isSaving = false
            showAlert = true
        }
    }
}
