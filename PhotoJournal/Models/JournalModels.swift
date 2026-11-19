import SwiftUI
import Combine

struct JournalEntry: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var prompt: String
    var caption: String
    var song: String?
    var isFavorite: Bool? = false
    var category: String? = nil
    var mood: String? = nil
    var imageName: String
    var challengeID: String? = nil

    var displayCategory: String {
        if category == "Family" {
            return PromptCategory.family.rawValue
        }
        if category == "Everyday life" {
            return "Other"
        }
        return category
            ?? PromptCategory.allCases.first(where: { $0.prompts.contains(prompt) })?.rawValue
            ?? "Other"
    }
}

@MainActor
final class JournalStore: ObservableObject {
    @Published private(set) var entries: [JournalEntry] = []

    private let folderName = "JournalPhotos"
    private let entriesFileName = "journal.json"

    init() {
        loadEntries()
    }

    func add(
        image: UIImage,
        prompt: String,
        category: String,
        caption: String,
        song: String,
        mood: String,
        challengeID: String? = nil
    ) -> Bool {
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: rendererFormat)
        let uprightImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        guard let data = uprightImage.jpegData(compressionQuality: 0.85) else { return false }

        let imageName = "\(UUID().uuidString).jpg"
        do {
            try data.write(to: photoFolder().appendingPathComponent(imageName))
            let songNote = song.trimmingCharacters(in: .whitespacesAndNewlines)
            let entry = JournalEntry(
                prompt: prompt,
                caption: caption,
                song: songNote.isEmpty ? nil : songNote,
                category: category,
                mood: mood.isEmpty ? nil : mood,
                imageName: imageName,
                challengeID: challengeID
            )
            entries.insert(entry, at: 0)
            saveEntries()
            PromptNotifications.cancelFollowUp(for: Date())
            return true
        } catch {
            print("Could not save journal photo: \(error)")
            return false
        }
    }

    func updateDetails(for entry: JournalEntry, caption: String, song: String, mood: String) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].caption = caption
        let songNote = song.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[index].song = songNote.isEmpty ? nil : songNote
        entries[index].mood = mood.isEmpty ? nil : mood
        saveEntries()
    }

    func toggleFavorite(_ entry: JournalEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isFavorite = !(entries[index].isFavorite ?? false)
        saveEntries()
    }

    func delete(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
        try? FileManager.default.removeItem(at: photoFolder().appendingPathComponent(entry.imageName))
        saveEntries()
    }

    func image(for entry: JournalEntry) -> UIImage? {
        UIImage(contentsOfFile: photoFolder().appendingPathComponent(entry.imageName).path)
    }

    private func photoFolder() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func entriesURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(entriesFileName)
    }

    private func loadEntries() {
        guard let data = try? Data(contentsOf: entriesURL()),
              let savedEntries = try? JSONDecoder().decode([JournalEntry].self, from: data) else { return }
        entries = savedEntries.map { savedEntry in
            var entry = savedEntry
            entry.mood = emojiForOldMoodLabel(entry.mood)
            return entry
        }.sorted { $0.date > $1.date }
    }

    private func emojiForOldMoodLabel(_ mood: String?) -> String? {
        guard let mood else { return nil }
        switch mood {
        case "Joyful": return "😄"
        case "Calm": return "😌"
        case "Curious": return "🤔"
        case "Grateful": return "🥰"
        case "Nostalgic": return "🥹"
        default: return mood
        }
    }

    private func saveEntries() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: entriesURL(), options: .atomic)
    }
}

enum PromptCategory: String, CaseIterable, Identifiable {
    case nature = "Nature"
    case art = "Art & Architecture"
    case music = "Music"
    case cinema = "Cinema"
    case pets = "Pets"
    case family = "Friends & Family"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .nature: "mountain.2"
        case .art: "photo.on.rectangle"
        case .music: "music.note"
        case .cinema: "film"
        case .pets: "pawprint"
        case .family: "person.3"
        }
    }

    var prompts: [String] {
        switch self {
        case .nature: return ["The sky", "A flower", "A tree near you"]
        case .art: return ["An interesting shape", "Something handmade", "A color you love"]
        case .music: return ["What you are listening to", "Something that feels like a song"]
        case .cinema: return ["A scene that feels cinematic", "A place with dramatic light"]
        case .pets: return ["A pet", "Your favorite toy or paw"]
        case .family: return ["A small family moment", "Something that reminds you of home"]
        }
    }

    static func fromSavedName(_ name: String) -> PromptCategory? {
        if name == "Family" { return .family }
        if name == "Art" { return .art }
        return PromptCategory(rawValue: name)
    }
}

extension String {
    var quotedForDisplay: String {
        "“\(self)”"
    }
}

struct CapturedPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}
