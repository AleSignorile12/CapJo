import SwiftUI
import UIKit
import UserNotifications

enum JournalTheme {
    static let lavender = Color(red: 214.0 / 255.0, green: 202.0 / 255.0, blue: 242.0 / 255.0)
    static let deepPurple = Color(red: 58.0 / 255.0, green: 2.0 / 255.0, blue: 91.0 / 255.0)
    static let purple = Color(red: 130.0 / 255.0, green: 65.0 / 255.0, blue: 148.0 / 255.0)
    static let backgroundAnimationDuration: TimeInterval = 14

    static var background: some View {
        AnimatedJournalBackground()
    }
}

private struct AnimatedJournalBackground: View {
    @State private var isShifted = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RadialGradient(
                    colors: [Color.white.opacity(0.96), JournalTheme.lavender.opacity(0.92), Color(red: 0.77, green: 0.69, blue: 0.89)],
                    center: UnitPoint(x: isShifted ? 0.56 : 0.44, y: isShifted ? 0.32 : 0.40),
                    startRadius: 24,
                    endRadius: max(geometry.size.width, geometry.size.height) * 0.82
                )
                Circle()
                    .fill(Color.white.opacity(0.42))
                    .frame(width: min(geometry.size.width, geometry.size.height) * 0.72)
                    .blur(radius: 78)
                    .position(
                        x: geometry.size.width * (isShifted ? 0.54 : 0.46),
                        y: geometry.size.height * (isShifted ? 0.38 : 0.46)
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: JournalTheme.backgroundAnimationDuration).repeatForever(autoreverses: true)) {
                isShifted = true
            }
        }
    }
}

private enum JournalFilter: String, CaseIterable, Identifiable {
    case all = "All photos"
    case captions = "With captions"

    var id: String { rawValue }
}

private enum JournalCollection: String, CaseIterable, Identifiable {
    case all = "All"
    case favorites = "Favorites"

    var id: String { rawValue }
}

private enum JournalSortOrder: String, CaseIterable, Identifiable {
    case date = "Date"
    case category = "Category"

    var id: String { rawValue }
}

private struct JournalSection: Identifiable {
    let id: String
    let title: String
    let entries: [JournalEntry]
}

struct ContentView: View {
    @EnvironmentObject private var journal: JournalStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("selectedCategories") private var savedCategories = "Nature,Art & Architecture"
    @AppStorage("todayPrompt") private var savedTodayPrompt = ""
    @AppStorage("todayPromptDate") private var savedTodayPromptDate = ""
    @AppStorage("activeChallengePrompt") private var activeChallengePrompt = ""
    @AppStorage("activeChallengeID") private var activeChallengeID = ""
    @AppStorage("dailyPromptsEnabled") private var dailyPromptsEnabled = false
    @AppStorage("notificationsPerDay") private var notificationsPerDay = 1
    @AppStorage("notificationPermissionPrompted") private var notificationPermissionPrompted = false
    @AppStorage("promptChangeDay") private var promptChangeDay = ""
    @AppStorage("promptChangesUsed") private var promptChangesUsed = 0

    @State private var showCamera = false
    @State private var capturedPhoto: CapturedPhoto?
    @State private var capturePrompt = ""
    @State private var captureCategory = "Other"
    @State private var captureChallengeID: String?
    @State private var showCameraUnavailable = false
    @State private var showSettings = false
    @State private var showJournal = false
    @State private var notificationMessage = ""
    @State private var isUpdatingNotifications = false
    @State private var journalFilter: JournalFilter = .all
    @State private var journalSortOrder: JournalSortOrder = .date
    @State private var journalCollection: JournalCollection = .all
    @State private var journalCategory = "All categories"
    @State private var journalSearchText = ""
    @State private var selectedJournalDate: Date?
    @State private var dateBeingPicked = Date()
    @State private var showDatePicker = false

    private var selectedCategories: [PromptCategory] {
        savedCategories.split(separator: ",")
            .compactMap { PromptCategory.fromSavedName(String($0)) }
    }

    private var todayPrompt: String {
        let availablePrompts = selectedCategories.flatMap(\.prompts)
        if savedTodayPromptDate == todayKey && availablePrompts.contains(savedTodayPrompt) {
            return savedTodayPrompt
        }
        return availablePrompts.first ?? "Take a picture of something around you"
    }

    private var activeTodayChallengeID: String? {
        guard !activeChallengePrompt.isEmpty,
              activeChallengeID.hasPrefix("photo-prompt-\(todayKey)") else { return nil }
        return activeChallengeID
    }

    private var displayedTodayPrompt: String {
        activeTodayChallengeID == nil ? todayPrompt : activeChallengePrompt
    }

    private var todayCategory: PromptCategory? {
        selectedCategories.first { $0.prompts.contains(displayedTodayPrompt) }
    }

    private var todayPromptCompleted: Bool {
        guard let activeTodayChallengeID else { return false }
        return journal.entries.contains { $0.challengeID == activeTodayChallengeID }
    }

    private var filteredJournalEntries: [JournalEntry] {
        journal.entries.filter { entry in
            let matchesCollection = journalCollection == .all || entry.isFavorite == true
            let matchesDate = selectedJournalDate.map {
                Calendar.current.isDate(entry.date, inSameDayAs: $0)
            } ?? true
            let matchesCategory = journalCategory == "All categories" || entry.displayCategory == journalCategory
            let matchesSearch = journalSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || entry.caption.localizedCaseInsensitiveContains(journalSearchText.trimmingCharacters(in: .whitespacesAndNewlines))

            let matchesFilter: Bool
            switch journalFilter {
            case .all:
                matchesFilter = true
            case .captions:
                matchesFilter = !entry.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return matchesCollection && matchesDate && matchesCategory && matchesSearch && matchesFilter
        }
    }

    private var hasActiveJournalFilters: Bool {
            //journalCollection != .all
            journalFilter != .all
            || journalCategory != "All categories"
            || !journalSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedJournalDate != nil
    }

    private func clearJournalFilters() {
        journalCollection = .all
        journalFilter = .all
        journalCategory = "All categories"
        journalSearchText = ""
        selectedJournalDate = nil
    }

    private var journalSections: [JournalSection] {
        switch journalSortOrder {
        case .date:
            let grouped = Dictionary(grouping: filteredJournalEntries) {
                Calendar.current.startOfDay(for: $0.date)
            }
            return grouped.keys.sorted(by: >).map { date in
                let entries = (grouped[date] ?? []).sorted { $0.date > $1.date }
                return JournalSection(
                    id: String(Int(date.timeIntervalSince1970)),
                    title: date.formatted(date: .complete, time: .omitted),
                    entries: entries
                )
            }
        case .category:
            let grouped = Dictionary(grouping: filteredJournalEntries, by: \.displayCategory)
            return grouped.keys.sorted {
                $0.localizedStandardCompare($1) == .orderedAscending
            }.map { category in
                let entries = (grouped[category] ?? []).sorted { $0.date > $1.date }
                return JournalSection(id: category, title: category, entries: entries)
            }
        }
    }

    private var todayKey: String {
        let date = Calendar.current.dateComponents([.year, .month, .day], from: Date.now)
        return String(format: "%04d-%02d-%02d", date.year ?? 0, date.month ?? 0, date.day ?? 0)
    }

    private var changesUsedToday: Int {
        promptChangeDay == todayKey ? promptChangesUsed : 0
    }

    private var promptChangesRemaining: Int {
        max(0, 3 - changesUsedToday)
    }

    private var currentDayStreak: Int {
        let calendar = Calendar.current
        let savedDays = Set(journal.entries.map { calendar.startOfDay(for: $0.date) })
        guard !savedDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: Date())
        var day = savedDays.contains(today)
            ? today
            : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        var streak = 0

        while savedDays.contains(day) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previousDay
        }
        return streak
    }

    private var todaysSavedChallengeCount: Int {
        let todayPrefix = "photo-prompt-\(todayKey)"
        let completedChallenges = journal.entries.compactMap { entry -> String? in
            guard Calendar.current.isDateInToday(entry.date),
                  let challengeID = entry.challengeID,
                  challengeID.hasPrefix(todayPrefix) else { return nil }
            return challengeID
        }
        return Set(completedChallenges).count
    }

    private var todaysChallengeGoal: Int {
        max(1, notificationsPerDay)
    }

    private var streakSummaryCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                Text("🔥")
                    .font(.system(size: 32))
                Text("\(currentDayStreak)")
                    .font(.system(size: 36, weight: .medium, design: .rounded))
                    .foregroundStyle(JournalTheme.deepPurple)
            }
            Text("Day streak")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(JournalTheme.purple)
            Text(currentDayStreak == 0 ? "Start today!" : "Keep it going!")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(JournalTheme.purple)
        }.padding(.top, -10)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(currentDayStreak) day streak")
    }

    private var todayChallengesSummaryCard: some View {
        let progress = min(todaysSavedChallengeCount, todaysChallengeGoal)
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(progress)/\(todaysChallengeGoal)")
                .font(.system(size: 36, weight: .medium, design: .rounded))
                .foregroundStyle(JournalTheme.deepPurple)
                .monospacedDigit()
            Text("Today's challenges")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(JournalTheme.purple)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(0..<todaysChallengeGoal, id: \.self) { index in
                    Capsule()
                        .fill(index < progress ? JournalTheme.purple : JournalTheme.lavender)
                        .frame(height: 7)
                }
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's challenges: \(progress) of \(todaysChallengeGoal) complete")
    }

    private var canChangePrompt: Bool {
        promptChangesRemaining > 0 && selectedCategories.flatMap(\.prompts)
            .contains(where: { $0 != displayedTodayPrompt })
    }

    var body: some View {
        todayScreen
        .task {
            await handleNotificationPermissionOnLaunch()
            await PromptNotifications.activateLatestDeliveredChallengeForToday()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await PromptNotifications.activateLatestDeliveredChallengeForToday() }
        }
        .onChange(of: notificationsPerDay) { _, _ in
            refreshNotificationScheduleIfEnabled()
        }
        .onChange(of: savedCategories) { _, _ in
            refreshNotificationScheduleIfEnabled()
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                capturedPhoto = CapturedPhoto(image: image)
            }
        }
        .sheet(item: $capturedPhoto) { photo in
            PhotoReviewView(
                photo: photo,
                prompt: capturePrompt,
                category: captureCategory,
                challengeID: captureChallengeID
            )
                .environmentObject(journal)
        }
        .sheet(isPresented: $showSettings) {
            promptSettingsScreen
                .environmentObject(journal)
        }
        .sheet(isPresented: $showJournal) {
            journalScreen
                .environmentObject(journal)
        }
        .alert("Camera unavailable", isPresented: $showCameraUnavailable) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Try running the app on an iPhone with a camera.")
        }
    }

    private var todayScreen: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Your challenge is…")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(JournalTheme.deepPurple)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, -40)

                        VStack(alignment: .leading, spacing: 0) {
                            
                            HStack(alignment: .firstTextBaseline) {
                                Text("Take a picture of:")
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.black).italic()
                                Spacer(minLength: 8)
                                Text(Date.now.formatted(.dateTime.day().month(.wide).year()))
                                    .font(.system(size: 15, weight: .regular, design: .rounded).italic())
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }.padding(.bottom, 55)
                            
                            VStack{
                                Text("“\(displayedTodayPrompt)”").multilineTextAlignment(.center)
                                    .font(.system(size: 25, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)


                                Button(action: openCamera) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 29, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 154, height: 54)
                                        .background(JournalTheme.deepPurple, in: Capsule())
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                                .padding(30)
                            }
                            

                            Button(action: changeTodayPrompt) {
                                HStack(spacing: 6) {
                                    Text("Refresh  \(promptChangesRemaining)/3")
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .underline()
                                .foregroundStyle(JournalTheme.deepPurple)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .disabled(!canChangePrompt)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 352)
                        .background(.white, in: RoundedRectangle(cornerRadius: 40, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                        .padding(.top, 38)
                        
                        Button {
                            showJournal = true
                        } label: {
                            Label("Take a look at your journal!", systemImage: "book")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(JournalTheme.deepPurple, in: Capsule())
                                .shadow(color: .black.opacity(0.16), radius: 6, x: 0, y: 3)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        .padding(20)
                        
                        

                        HStack(alignment: .top, spacing: 14) {
                            streakSummaryCard
                            todayChallengesSummaryCard
                        }
                        
                        Spacer(minLength: 36)

                        
                    }.padding(.horizontal, 24)
                        .padding(.top, 22)
                        .padding(.bottom, 24)
                        .frame(minHeight: geometry.size.height, alignment: .top)
                    
                        .navigationTitle("")
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                Text("CapJo")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(JournalTheme.deepPurple)
                                    .padding(5)
                            }
                        }
                }
            }
            .background(JournalTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(JournalTheme.deepPurple)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.72), in: Circle())
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
    }

    private var journalScreen: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Journal")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(JournalTheme.deepPurple)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 10)

                Picker("Journal section", selection: $journalCollection) {
                    ForEach(JournalCollection.allCases) { collection in
                        Text(collection.rawValue).tag(collection)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                Group {
                    if journal.entries.isEmpty {
                        ContentUnavailableView(
                            "Your journal is empty",
                            systemImage: "photo.on.rectangle.angled",
                            description: Text("Your saved moments will appear here.")
                        )
                    } else if filteredJournalEntries.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: journalCollection == .favorites
                                  ? "heart"
                                  : "line.3.horizontal.decrease.circle")
                                .font(.largeTitle)
                                .foregroundStyle(JournalTheme.deepPurple)
                            Text(emptyJournalTitle)
                                .font(.title3.weight(.semibold))
                            Text(emptyJournalDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 26) {
                                ForEach(journalSections) { section in
                                    VStack(alignment: .leading, spacing: 14) {
                                        Text(section.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Divider()

                                        let leftEntries = section.entries.enumerated()
                                            .filter { $0.offset.isMultiple(of: 2) }
                                            .map { $0.element }
                                        let rightEntries = section.entries.enumerated()
                                            .filter { !$0.offset.isMultiple(of: 2) }
                                            .map { $0.element }

                                        HStack(alignment: .top, spacing: 14) {
                                            LazyVStack(spacing: 16) {
                                                ForEach(leftEntries) { entry in journalCard(entry) }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .top)

                                            LazyVStack(spacing: 16) {
                                                ForEach(rightEntries) { entry in journalCard(entry) }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .top)
                                        }
                                    }
                                }
                            }
                            .padding()
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(JournalTheme.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $journalSearchText, prompt: "Search captions")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Picker("Filter photos", selection: $journalFilter) {
                            ForEach(JournalFilter.allCases) { filter in
                                Text(filter.rawValue).tag(filter)
                            }
                        }
                        Picker("Order by", selection: $journalSortOrder) {
                            ForEach(JournalSortOrder.allCases) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        Picker("Category", selection: $journalCategory) {
                            Text("All categories").tag("All categories")
                            ForEach(PromptCategory.allCases) { category in
                                Text(category.rawValue).tag(category.rawValue)
                            }
                            if journal.entries.contains(where: { $0.displayCategory == "Other" }) {
                                Text("Other").tag("Other")
                            }
                        }
                    } label: {
                        Image(systemName: journalFilter == .all
                              && journalCategory == "All categories"
                              && journalSearchText.isEmpty
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill").foregroundStyle(JournalTheme.deepPurple)
                    }
                    .accessibilityLabel("Filter journal photos")

                    Button {
                        dateBeingPicked = selectedJournalDate ?? Date()
                        showDatePicker = true
                    } label: {
                        Image(systemName: selectedJournalDate == nil ? "calendar" : "calendar.badge.checkmark").foregroundStyle(JournalTheme.deepPurple)
                    }
                    .accessibilityLabel("Jump to a date")

                    if hasActiveJournalFilters {
                        Button("Clear filters") {
                            clearJournalFilters()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(JournalTheme.deepPurple)
                        .accessibilityLabel("Clear journal filters")
                    }
                }
            }
            .sheet(isPresented: $showDatePicker) {
                datePickerSheet
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showJournal = false
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .foregroundStyle(JournalTheme.deepPurple)
                }
            }
        }
    }

    private var hasFavorites: Bool {
        journal.entries.contains { $0.isFavorite == true }
    }

    private var emptyJournalTitle: String {
        if journalCollection == .favorites && !hasFavorites { return "No favorites yet" }
        return "No photos match"
    }

    private var emptyJournalDescription: String {
        if journalCollection == .favorites && !hasFavorites {
            return "Tap the heart on a photo to keep it in your favorites."
        }
        if let selectedJournalDate {
            return "There are no photos for \(selectedJournalDate.formatted(date: .complete, time: .omitted)) with the current filter."
        }
        return "Try a different filter or clear your filters."
    }

    private var datePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 14) {
                DatePicker(
                    "Choose a date",
                    selection: $dateBeingPicked,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()

                Button("Show all dates") {
                    selectedJournalDate = nil
                    showDatePicker = false
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(JournalTheme.background.ignoresSafeArea())
            .navigationTitle("Jump to a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showDatePicker = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show photos") {
                        selectedJournalDate = dateBeingPicked
                        showDatePicker = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func journalCard(_ entry: JournalEntry) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink {
                JournalEntryDetailView(entry: entry)
            } label: {
                PolaroidCard(entry: entry, image: journal.image(for: entry))
            }
            .buttonStyle(.plain)

            Button {
                journal.toggleFavorite(entry)
            } label: {
                Image(systemName: entry.isFavorite == true ? "heart.fill" : "heart")
                    .font(.headline)
                    .foregroundStyle(entry.isFavorite == true ? Color.red : JournalTheme.deepPurple.opacity(0.72))
                    .frame(width: 40, height: 40)
                    .background(.white, in: Circle())
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5) }
                    .shadow(color: .black.opacity(0.2), radius: 7, x: 0, y: 3)
                    .symbolEffect(.bounce, value: entry.isFavorite == true)
            }
            .buttonStyle(.plain)
            .padding(6)
            .offset(x: 6, y: -7)
            .accessibilityLabel(entry.isFavorite == true ? "Remove from favorites" : "Add to favorites")
            .accessibilityHint("Toggles this photo's favorite status")
        }
    }

    private var promptSettingsScreen: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Interests")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(JournalTheme.deepPurple)
                        Text("Pick your interests. Prompts are based on the ones you select.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(PromptCategory.allCases) { category in
                            interestTile(category)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Push Notification")
                            .font(.system(size: 25, weight: .bold, design: .rounded))
                            .foregroundStyle(JournalTheme.deepPurple)
                        Text("Choose 1–5 challenges for each day. A reminder may follow two hours later for your next challenge.")
                            .font(.subheadline.italic())
                            .foregroundStyle(.primary)
                        HStack(spacing: 12) {
                            Button {
                                notificationsPerDay = max(1, notificationsPerDay - 1)
                            } label: {
                                Image(systemName: "minus")
                                    .font(.headline)
                                    .frame(width: 48, height: 44)
                            }
                            .disabled(notificationsPerDay <= 1 || isUpdatingNotifications)
                            Spacer()
                            Text("\(notificationsPerDay)")
                                .font(.title3.weight(.medium))
                                .monospacedDigit()
                            Spacer()
                            Button {
                                notificationsPerDay = min(5, notificationsPerDay + 1)
                            } label: {
                                Image(systemName: "plus")
                                    .font(.headline)
                                    .frame(width: 48, height: 44)
                            }
                            .disabled(notificationsPerDay >= 5 || isUpdatingNotifications)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(JournalTheme.deepPurple)
                        .padding(.horizontal, 6)
                        .background(JournalTheme.lavender.opacity(0.58), in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 5, x: 0, y: 3)

                        Text("To disable notifications, go to your phone Settings → PhotoJournal → Notifications → Turn off Allow Notifications.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if !notificationMessage.isEmpty {
                            Text(notificationMessage)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(JournalTheme.purple)
                        }
                    }

                    Text("Prompts are scheduled on this iPhone. No account or internet connection is used.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(JournalTheme.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showSettings = false
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .foregroundStyle(JournalTheme.deepPurple)
                }
            }
        }
    }

    private func interestTile(_ category: PromptCategory) -> some View {
        let isSelected = selectedCategories.contains(category)
        return Button {
            categoryBinding(for: category).wrappedValue.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 12) {
                    Image(systemName: category.symbolName)
                        .font(.system(size: 42, weight: .medium))
                        .frame(height: 52)
                        .symbolEffect(.bounce, value: isSelected)
                    Text(category.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 144)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(JournalTheme.deepPurple, in: Circle())
                        .padding(9)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .foregroundStyle(JournalTheme.deepPurple)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? JournalTheme.lavender : Color.white.opacity(0.62))
                    .shadow(color: JournalTheme.deepPurple.opacity(isSelected ? 0.17 : 0.07), radius: isSelected ? 9 : 5, x: 0, y: 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? JournalTheme.deepPurple : JournalTheme.deepPurple.opacity(0.12), lineWidth: isSelected ? 2.5 : 1)
            }
            .scaleEffect(isSelected ? 1.015 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.rawValue), \(isSelected ? "selected" : "not selected")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func refreshNotificationScheduleIfEnabled() {
        guard dailyPromptsEnabled, !isUpdatingNotifications else { return }
        guard !selectedCategories.isEmpty else {
            PromptNotifications.cancelScheduledPrompts()
            notificationMessage = "Choose an interest to receive daily prompts."
            return
        }
        isUpdatingNotifications = true
        Task {
            let result = await PromptNotifications.scheduleWeek(
                categories: selectedCategories,
                notificationsPerDay: notificationsPerDay
            )
            isUpdatingNotifications = false
            if let result { notificationMessage = result }
        }
    }

    private func handleNotificationPermissionOnLaunch() async {
        if !notificationPermissionPrompted {
            notificationPermissionPrompted = true
            do {
                let allowed = try await UNUserNotificationCenter.current()
                    .requestAuthorization(options: [.alert, .sound, .badge])
                dailyPromptsEnabled = allowed
                if allowed {
                    notificationMessage = "Notifications are on."
                    await scheduleCurrentPrompts()
                } else {
                    notificationMessage = "Notifications are off. You can change this in your iPhone Settings."
                }
            } catch {
                notificationMessage = "Could not request notification permission: \(error.localizedDescription)"
            }
            return
        }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        dailyPromptsEnabled = allowed
        if allowed {
            await scheduleCurrentPrompts()
        }
    }

    private func scheduleCurrentPrompts() async {
        guard !selectedCategories.isEmpty else {
            notificationMessage = "Choose at least one interest to receive prompts."
            return
        }
        let result = await PromptNotifications.scheduleWeek(
            categories: selectedCategories,
            notificationsPerDay: notificationsPerDay
        )
        if let result { notificationMessage = result }
    }

    private func categoryBinding(for category: PromptCategory) -> Binding<Bool> {
        Binding(
            get: { selectedCategories.contains(category) },
            set: { isOn in
                var names = Set(selectedCategories.map(\.rawValue))
                if isOn { names.insert(category.rawValue) }
                else { names.remove(category.rawValue) }
                savedCategories = PromptCategory.allCases
                    .map(\.rawValue).filter { names.contains($0) }.joined(separator: ",")
            }
        )
    }

    private func changeTodayPrompt() {
        let availablePrompts = selectedCategories.flatMap(\.prompts)
            .filter { $0 != displayedTodayPrompt }
        guard canChangePrompt, let newPrompt = availablePrompts.randomElement() else { return }

        if promptChangeDay != todayKey {
            promptChangeDay = todayKey
            promptChangesUsed = 0
        }
        promptChangesUsed += 1
        savedTodayPrompt = newPrompt
        savedTodayPromptDate = todayKey
        PromptNotifications.clearActiveChallenge()

        Task {
            await PromptNotifications.updatePendingPromptForToday(newPrompt)
        }
    }

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            showCameraUnavailable = true
            return
        }
        capturePrompt = displayedTodayPrompt
        captureChallengeID = activeTodayChallengeID
        captureCategory = selectedCategories.first { $0.prompts.contains(capturePrompt) }?.rawValue ?? "Other"
        showCamera = true
    }
}
