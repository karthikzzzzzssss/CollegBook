import SwiftUI

private let secondary = Color(hex: 0x6B7280)
private let stroke = Color(hex: 0xE3E5E8)
private let muted = Color(hex: 0xF4F5F7)
private let danger = Color(hex: 0xD32F2F)
private let emptyMessage =
  "You don't have any choice lists currently.\nCreate one here to start adding your college choices."

/// The Choice List screens' chrome: the green header over the page.
private struct ChoiceScaffold<Content: View>: View {
  let title: String
  var subtitle: String? = nil
  let background: Color
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: 0) {
      GreenHeader(title: title, subtitle: subtitle, large: true)
      content.frame(maxWidth: .infinity, maxHeight: .infinity).background(background)
    }
    .background(GreenHeader.gradient.ignoresSafeArea(edges: .top))
    .hiddenNavigationBar()
    .coversTabBar()
  }
}

/// bg_choice_pill_button.
private struct PillButton: View {
  let label: String
  var enabled = true
  var color: Color = stateGreen
  var disabledColor = Color(hex: 0xA3B4AE)
  var height: CGFloat = 52
  var expand = true
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(label).font(.inter(15, .semibold)).foregroundStyle(.white)
        .padding(.horizontal, expand ? 0 : 24)
        .frame(maxWidth: expand ? .infinity : nil).frame(height: height)
        .background(enabled ? color : disabledColor, in: Capsule())
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
  }
}

/// bg_choice_lock_circle: a state-colour circle with a 6pt #E6EEEA ring.
private struct LockCircle: View {
  let size: CGFloat
  let padding: CGFloat
  let icon: String

  var body: some View {
    Image(icon).renderingMode(.template).resizable().foregroundStyle(.white).padding(padding - 6)
      .frame(width: size - 12, height: size - 12)
      .background(stateGreen, in: Circle())
      .padding(6)
      .background(Color(hex: 0xE6EEEA), in: Circle())
  }
}

private struct Handle: View {
  var width: CGFloat = 40
  var height: CGFloat = 4
  var body: some View { Capsule().fill(Color(hex: 0xD9D9D9)).frame(width: width, height: height) }
}

/// The ⋮ menu: an optional action, then the destructive one in red.
private struct MoreMenu: View {
  var actionLabel: String? = nil
  var onAction: (() -> Void)? = nil
  let deleteLabel: String
  let onDelete: () -> Void

  var body: some View {
    Menu {
      if let actionLabel, let onAction { Button(actionLabel, action: onAction) }
      Button(deleteLabel, role: .destructive, action: onDelete)
    } label: {
      Image("ic_more_vert").renderingMode(.template).resizable().foregroundStyle(secondary).padding(10)
        .frame(width: 40, height: 40)
    }
    .accessibilityLabel("More options")
  }
}

private enum ChoiceRoute: Hashable {
  case detail(id: String, name: String?)
  case add(id: String, name: String?, openListAfter: Bool)
}

// MARK: - My Choice Lists (ChoiceListsActivity)

struct ChoiceListsView: View {
  let isSubscribed: Bool
  let onGetPackage: () -> Void

  @EnvironmentObject private var app: AppState
  @State private var lists: [ChoiceList]?
  @State private var empty: String?
  @State private var loading = false
  @State private var creating = false
  @State private var deleting: ChoiceList?
  @State private var downloading: ChoiceList?
  @State private var exported: URL?
  @State private var sharing: URL?
  @State private var route: ChoiceRoute?
  private var repo: ChoiceListRepository { .shared }

  var body: some View {
    ChoiceScaffold(title: "Choice List", background: .white) {
      VStack(spacing: 0) {
        Handle(width: 36, height: 3).padding(.top, 20)
        Text("My Choice Lists").font(.inter(16, .semibold)).foregroundStyle(appInk).padding(.top, 12)
        ZStack(alignment: .top) {
          ScrollView {
            LazyVStack(spacing: 12) {
              ForEach(lists ?? []) { list in listCard(list) }
            }
            .padding(EdgeInsets(top: 20, leading: 16, bottom: 16, trailing: 16))
          }
          if let empty, (lists ?? []).isEmpty {
            Text(empty).font(.inter(14)).foregroundStyle(secondary).multilineTextAlignment(.center).lineSpacing(5)
              .padding(EdgeInsets(top: 28, leading: 32, bottom: 0, trailing: 32))
          }
          if loading { ProgressView().tint(stateGreen).controlSize(.large).padding(.top, 40) }
        }
        PillButton(label: "+  Create choice list") { creating = true }
          .padding(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20))
      }
    }
    .task { await load() }
    .sheet(isPresented: $creating) {
      CreateListSheet { list in
        Task { await load() }
        // Straight to adding the first choice; the list is on this page behind it.
        route = .add(id: list.id, name: list.name, openListAfter: true)
      }
    }
    .sheet(item: $deleting) { list in
      let count = list.choiceCount
      ConfirmDeleteSheet(
        title: "Delete this list?", subject: list.name,
        message: (count == 0
          ? "This list will be permanently deleted."
          : "This list and its \(count) \(count == 1 ? "choice" : "choices") will be permanently deleted.")
          + " This can't be undone.",
        deleteLabel: "Delete list",
        action: { try await repo.deleteList(list.id) }
      ) {
        app.show("List deleted")
        Task { await load() }
      }
    }
    .sheet(item: $downloading, onDismiss: {
      // The share sheet opens once the download sheet has gone.
      sharing = exported
      exported = nil
    }) { DownloadSheet(list: $0) { exported = $0 } }
    .sheet(item: $sharing) { ShareSheet(url: $0).ignoresSafeArea() }
    .compatDestination(item: $route) { route in
      switch route {
      case .detail(let id, let name):
        ChoiceListDetailView(listId: id, listName: name, isSubscribed: isSubscribed, onGetPackage: onGetPackage)
      case .add(let id, let name, let openAfter):
        AddChoiceView(listId: id, listName: name, openListAfter: openAfter) {
          // Replace the add screen with the list's choices (pushReplacement).
          self.route = .detail(id: id, name: name)
        }
      }
    }
    .onChangeCompat(of: route) { _, new in if new == nil { Task { await load() } } }
  }

  /// Also runs on return from the add/detail screens (onResume).
  private func load() async {
    if (lists ?? []).isEmpty { loading = true }
    defer { loading = false }
    do {
      let result = try await repo.getLists()
      lists = result
      empty = result.isEmpty ? emptyMessage : nil
    } catch {
      // Pushed over or left mid-request: nothing failed.
      guard !Task.isCancelled else { return }
      if (lists ?? []).isEmpty { empty = error.localizedDescription } else { app.show(error.localizedDescription) }
    }
  }

  private func listCard(_ list: ChoiceList) -> some View {
    HStack(spacing: 14) {
      LockCircle(size: 40, padding: 11, icon: "ic_heart_filled")
      VStack(alignment: .leading, spacing: 2) {
        Text(list.name ?? "").font(.inter(15, .semibold)).foregroundStyle(appInk).lineLimit(1)
        Text(list.choiceCount == 0 ? "No choices yet" : "\(list.choiceCount) \(list.choiceCount == 1 ? "choice" : "choices")")
          .font(.inter(13)).foregroundStyle(secondary)
      }
      Spacer(minLength: 0)
      MoreMenu(actionLabel: "Download", onAction: { downloading = list }, deleteLabel: "Delete list") { deleting = list }
    }
    .padding(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 4))
    .background(.white, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(stroke))
    .contentShape(Rectangle())
    .onTapGesture { route = .detail(id: list.id, name: list.name) }
  }
}

/// bottomsheet_create_choice_list.
private struct CreateListSheet: View {
  let onCreated: (ChoiceList) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var name = ""
  @State private var error: String?
  @State private var creating = false
  @FocusState private var focused: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Handle().frame(maxWidth: .infinity)
      Text("Create choice list").font(.inter(18, .semibold)).foregroundStyle(appInk).padding(.top, 16)
      Text("Give your list a name, then start adding choices.").font(.inter(13)).foregroundStyle(secondary).padding(.top, 4)
      TextField("", text: $name, prompt: Text("e.g. Round 1 deemed colleges").foregroundColor(secondary))
        .font(.inter(15, .medium)).foregroundStyle(appInk)
        .textInputAutocapitalization(.sentences)
        .submitLabel(.done).onSubmit(create)
        .focused($focused)
        .padding(.horizontal, 16).frame(height: 50)
        .background(muted, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(focused ? stateGreen : stroke, lineWidth: focused ? 1.5 : 1))
        .padding(.top, 18)
        .onChangeCompat(of: name) { _, new in
          if new.count > 60 { name = String(new.prefix(60)) }
          error = nil
        }
      if let error { Text(error).font(.inter(12)).foregroundStyle(danger).padding(.top, 6) }
      PillButton(label: creating ? "Creating…" : "Create", enabled: !creating, action: create).padding(.top, 20)
    }
    .padding(EdgeInsets(top: 10, leading: 20, bottom: 20, trailing: 20))
    .sheetDetents([.height(300)])
    .sheetCornerRadius(20)
    .onAppear { focused = true }
  }

  private func create() {
    guard !creating else { return }
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return error = "Please enter a name for your list" }
    if ChoiceListRepository.shared.nameExists(trimmed) { return error = "You already have a list with this name" }
    creating = true
    Task {
      do {
        let list = try await ChoiceListRepository.shared.createList(trimmed)
        dismiss()
        onCreated(list)
      } catch {
        creating = false
        self.error = error.localizedDescription
      }
    }
  }
}

/// bottomsheet_confirm_delete: stays open while the request runs and shows
/// the server's error in place.
private struct ConfirmDeleteSheet: View {
  let title: String
  let subject: String?
  let message: String
  let deleteLabel: String
  let action: () async throws -> Void
  let onDone: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var busy = false
  @State private var error: String?

  var body: some View {
    VStack(spacing: 0) {
      Handle()
      Image("ic_cb_delete").renderingMode(.template).resizable().foregroundStyle(.white).padding(10)
        .frame(width: 48, height: 48).background(danger, in: Circle())
        .padding(8).background(Color(hex: 0xFDECEC), in: Circle())
        .padding(.top, 22)
      Text(title).font(.inter(18, .semibold)).foregroundStyle(appInk).multilineTextAlignment(.center).padding(.top, 16)
      if let subject, !subject.isEmpty {
        Text(subject).font(.inter(14, .medium)).foregroundStyle(appInk).lineLimit(2).multilineTextAlignment(.center)
          .padding(.top, 6)
      }
      Text(message).font(.inter(13)).foregroundStyle(secondary).multilineTextAlignment(.center).lineSpacing(3)
        .padding(.top, 6)
      if let error { Text(error).font(.inter(12)).foregroundStyle(danger).multilineTextAlignment(.center).padding(.top, 10) }
      HStack(spacing: 12) {
        Button {
          dismiss()
        } label: {
          Text("Cancel").font(.inter(15, .semibold)).foregroundStyle(appInk).frame(maxWidth: .infinity).frame(height: 52)
            .background(.white, in: Capsule()).overlay(Capsule().stroke(Color(hex: 0xD1D5DB)))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .opacity(busy ? 0.5 : 1)
        PillButton(label: busy ? "Deleting…" : deleteLabel, enabled: !busy, color: danger, disabledColor: Color(hex: 0xE9A3A3)) {
          busy = true
          error = nil
          Task {
            do {
              try await action()
              dismiss()
              onDone()
            } catch {
              busy = false
              self.error = error.localizedDescription
            }
          }
        }
      }
      .padding(.top, 24)
    }
    .padding(EdgeInsets(top: 10, leading: 20, bottom: 20, trailing: 20))
    .sheetDetents([.height(380)])
    .sheetCornerRadius(20)
    .interactiveDismissDisabled(busy)
  }
}

/// DownloadChoiceListSheet: PDF or CSV, then the share sheet (Save to
/// Files, AirDrop, mail…).
private struct DownloadSheet: View {
  let list: ChoiceList
  let onExported: (URL) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var saving: ChoiceExportFormat?
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Handle().frame(maxWidth: .infinity)
      Text("Download choice list").font(.inter(18, .semibold)).foregroundStyle(appInk).padding(.top, 16)
      Text("\(list.name ?? "")  ·  Save or share the file").font(.inter(13)).foregroundStyle(secondary).lineLimit(1).padding(.top, 4)
      option(.pdf, "ic_cb_file_pdf", "Download as PDF", "Printable table of your choices")
      option(.csv, "ic_cb_file_csv", "Download as CSV", "Open in Excel or Google Sheets")
      if let error { Text(error).font(.inter(12)).foregroundStyle(danger).padding(.top, 10) }
    }
    .padding(EdgeInsets(top: 10, leading: 20, bottom: 24, trailing: 20))
    .sheetDetents([.height(290)])
    .sheetCornerRadius(20)
    .interactiveDismissDisabled(saving != nil)
  }

  private func option(_ format: ChoiceExportFormat, _ icon: String, _ label: String, _ hint: String) -> some View {
    Button {
      download(format)
    } label: {
      HStack(spacing: 14) {
        Image(icon).renderingMode(.template).resizable().foregroundStyle(stateGreen).padding(11)
          .frame(width: 44, height: 44).background(Color(hex: 0xE6EEEA), in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text(label).font(.inter(15, .semibold)).foregroundStyle(appInk)
          Text(hint).font(.inter(12)).foregroundStyle(secondary)
        }
        Spacer()
        if saving == format {
          ProgressView().tint(stateGreen).frame(width: 32, height: 32)
        } else {
          Image("ic_cb_chevron_right").renderingMode(.template).resizable().foregroundStyle(secondary).padding(4)
            .frame(width: 32, height: 32)
        }
      }
      .padding(.leading, 14).padding(.trailing, 10)
      .frame(minHeight: 72)
      .background(.white, in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0xE5E7EB)))
    }
    .buttonStyle(.plain)
    .disabled(saving != nil)
    .opacity(saving != nil && saving != format ? 0.5 : 1)
    .padding(.top, 12)
  }

  private func download(_ format: ChoiceExportFormat) {
    guard saving == nil else { return }
    saving = format
    error = nil
    Task {
      do {
        var loaded = try await ChoiceListRepository.shared.getChoices(list.id)
        if loaded.name == nil { loaded = ChoiceList(id: loaded.id, name: list.name, choiceCount: loaded.choices.count, choices: loaded.choices) }
        onExported(try ChoiceExport.export(loaded, as: format))
        dismiss()
      } catch let error as ChoiceError {
        saving = nil
        self.error = error.message
      } catch {
        saving = nil
        self.error = "Couldn't save the file. Please try again."
      }
    }
  }
}

// MARK: - One list (ChoiceListDetailActivity)

private struct ChoiceListDetailView: View {
  let listId: String
  let listName: String?
  let isSubscribed: Bool
  let onGetPackage: () -> Void

  @EnvironmentObject private var app: AppState
  @State private var name: String?
  @State private var choices: [ChoiceItem] = []
  @State private var adding = false
  @State private var removing: ChoiceItem?
  /// The choices have been fetched once: until then "no choices" isn't known.
  @State private var loaded = false
  @State private var loadError: String?

  var body: some View {
    let count = choices.count
    ChoiceScaffold(title: name ?? listName ?? "", subtitle: loaded ? "\(count) \(count == 1 ? "choice" : "choices")" : nil, background: Color(hex: 0xF7F8FA)) {
      ZStack(alignment: .bottomTrailing) {
        ScrollView {
          LazyVStack(spacing: 12) {
            if count == 0 {
              if let loadError {
                Text(loadError).font(.inter(14)).foregroundStyle(secondary)
                  .multilineTextAlignment(.center).padding(.top, 40)
              } else if !loaded {
                ProgressView().tint(stateGreen).controlSize(.large).padding(.top, 40)
              } else {
                Text("No choices in this list yet.\nTap “Add new choice” to add one.").font(.inter(14)).foregroundStyle(secondary)
                  .multilineTextAlignment(.center).padding(.top, 40)
              }
            } else {
              Text("Your choices in order of preference. Tap ⋮ on a choice to remove it.").font(.inter(13))
                .foregroundStyle(secondary).multilineTextAlignment(.center)
            }
            ForEach(Array(choices.enumerated()), id: \.offset) { index, item in choiceCard(index + 1, item) }
            if !isSubscribed && count > 0 { lockedCard.padding(.top, 8) }
          }
          .padding(EdgeInsets(top: 12, leading: 16, bottom: 96, trailing: 16))
        }
        PillButton(label: "+  Add new choice", expand: false) { adding = true }
          .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
          .padding(EdgeInsets(top: 0, leading: 0, bottom: 24, trailing: 20))
      }
    }
    .task { await load() }
    .compatDestination(isPresented: $adding) {
      AddChoiceView(listId: listId, listName: name ?? listName, openListAfter: false) {}
    }
    .onChangeCompat(of: adding) { _, open in if !open { Task { await load() } } }
    .sheet(item: Binding(get: { removing.map { RemoveBox(item: $0) } }, set: { removing = $0?.item })) { box in
      let item = box.item
      ConfirmDeleteSheet(
        title: "Remove this choice?", subject: item.institute,
        message: "\(item.course ?? "") · \(item.quota ?? "") | \(item.category ?? "")\nIt will be removed from \"\(name ?? listName ?? "")\".",
        deleteLabel: "Remove",
        action: { try await ChoiceListRepository.shared.deleteChoice(listId, item.id ?? "") }
      ) {
        app.show("Choice removed")
        Task { await load() }
      }
    }
  }

  private struct RemoveBox: Identifiable {
    let item: ChoiceItem
    var id: String { item.id ?? UUID().uuidString }
  }

  private func load() async {
    do {
      let list = try await ChoiceListRepository.shared.getChoices(listId)
      if let listName = list.name { name = listName }
      choices = list.choices
      loaded = true
      loadError = nil
    } catch {
      // Pushed over or left mid-request: nothing failed.
      guard !Task.isCancelled else { return }
      if loaded { app.show(error.localizedDescription) } else { loadError = error.localizedDescription }
    }
  }

  private static func join(_ separator: String, _ parts: [String?]) -> String {
    parts.compactMap { $0 }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: separator)
  }

  private func choiceCard(_ rank: Int, _ item: ChoiceItem) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top) {
        Text("#\(rank)").font(.inter(13, .semibold)).foregroundStyle(stateGreen)
          .padding(.horizontal, 12).padding(.vertical, 3).background(muted, in: Capsule())
          .padding(.leading, 16).padding(.top, 12)
        Spacer()
        MoreMenu(deleteLabel: "Remove choice") { removing = item }.padding(.top, 4).padding(.trailing, 4)
      }
      VStack(alignment: .leading, spacing: 0) {
        Text(Self.join(" • ", [item.institute, item.state])).font(.inter(15, .semibold)).foregroundStyle(appInk)
        Text(Self.join(" • ", [item.course, item.beds > 0 ? "\(item.beds) BEDS" : nil])).font(.inter(13, .medium))
          .foregroundStyle(secondary).padding(.top, 6)
        Text(Self.join("  |  ", [item.quota, item.category])).font(.inter(12, .medium)).foregroundStyle(stateGreen)
          .padding(.horizontal, 12).padding(.vertical, 4)
          .background(.white, in: Capsule()).overlay(Capsule().stroke(stroke))
          .padding(.top, 10)
      }
      .padding(.horizontal, 16)
    }
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.white, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(stroke))
  }

  /// layout_choice_locked_card.
  private var lockedCard: some View {
    VStack(spacing: 0) {
      LockCircle(size: 64, padding: 18, icon: "ic_baseline_lock_24")
      Text("Content Locked").font(.inter(16, .semibold)).foregroundStyle(appInk).padding(.top, 14)
      Text("Please purchase a NEET PG package to see closing ranks and your chances for these choices.").font(.inter(13))
        .foregroundStyle(secondary).multilineTextAlignment(.center).padding(.top, 6)
      PillButton(label: "Get a Package  →", height: 48, action: onGetPackage).padding(.top, 18)
    }
    .padding(.horizontal, 20).padding(.vertical, 24)
    .background(.white, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(stroke))
  }
}

// MARK: - Add new choice (AddChoiceActivity)

/// Counselling → Institute → Course → Quota → Category, each single-select;
/// changing a field clears the ones below it.
private struct AddChoiceView: View {
  let listId: String
  let listName: String?
  /// Right after creating a list: show its choices once one is added.
  let openListAfter: Bool
  let onAdded: () -> Void

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var values: [String?] = Array(repeating: nil, count: 5)
  @State private var quotas: [QuotaOption] = []
  @State private var loadingField: Int?
  @State private var adding = false
  @State private var picker: PickerState?

  struct PickerState: Identifiable {
    let field: Int
    let options: [String]
    var id: Int { field }
  }

  private static let labels = ["Counselling", "Institute", "Course", "Quota", "Category"]
  private static let titles = ["Select counselling", "Select institute", "Select course", "Select quota", "Select category"]
  private static let searches = ["Search counselling", "Search institutes", "Search courses", "Search quotas", "Search categories"]
  private static let locked = ["", "Select counselling first", "Select institute first", "Select course first", "Select quota first"]

  private var complete: Bool { values.allSatisfy { $0 != nil } }

  var body: some View {
    ChoiceScaffold(title: "Add new choice", subtitle: (listName ?? "").isEmpty ? nil : listName, background: .white) {
      VStack(spacing: 0) {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(0..<5, id: \.self) { field(i: $0) }
          }
          .padding(EdgeInsets(top: 4, leading: 20, bottom: 20, trailing: 20))
        }
        PillButton(label: adding ? "Adding…" : "+  Add choice", enabled: complete && !adding, action: add)
          .padding(EdgeInsets(top: 0, leading: 20, bottom: 20, trailing: 20))
      }
    }
    .sheet(item: $picker) { state in
      OptionPickerSheet(
        title: Self.titles[state.field], searchHint: Self.searches[state.field], options: state.options,
        selected: values[state.field]
      ) { pick(state.field, $0) }
    }
  }

  /// layout_choice_field.
  private func field(i: Int) -> some View {
    let enabled = i == 0 || values[i - 1] != nil
    return VStack(alignment: .leading, spacing: 8) {
      Text(Self.labels[i]).font(.inter(13, .medium)).foregroundStyle(secondary)
      Button {
        open(i)
      } label: {
        HStack {
          Text(values[i] ?? Self.titles[i]).font(.inter(15, .medium)).foregroundStyle(values[i] == nil ? secondary : appInk)
            .multilineTextAlignment(.leading)
          Spacer()
          if loadingField == i {
            ProgressView().tint(stateGreen).frame(width: 20, height: 20)
          } else {
            Image("ic_baseline_arrow_drop_down_24").renderingMode(.template).resizable().frame(width: 24, height: 24)
              .foregroundStyle(secondary)
          }
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 10))
        .frame(minHeight: 52)
        .background(muted, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(stroke))
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .opacity(enabled ? 1 : 0.5)
    }
    .padding(.top, 18)
  }

  private func open(_ field: Int) {
    if field > 0, values[field - 1] == nil { return app.show(Self.locked[field]) }
    guard loadingField == nil else { return }
    loadingField = field
    Task {
      let repo = ChoiceListRepository.shared
      do {
        let options: [String]
        switch field {
        case 0: options = try await repo.counsellingOptions()
        case 1: options = try await repo.instituteOptions(values[0]!)
        case 2: options = try await repo.courseOptions(values[0]!, values[1]!)
        case 3:
          quotas = try await repo.quotaOptions(values[0]!, values[1]!, values[2]!)
          options = quotas.map(\.name)
        default: options = quotas.filter { $0.name == values[3] }.flatMap(\.categories)
        }
        loadingField = nil
        guard !options.isEmpty else { return app.show("No \(Self.labels[field].lowercased()) options available") }
        picker = PickerState(field: field, options: options)
      } catch {
        loadingField = nil
        app.show(error.localizedDescription)
      }
    }
  }

  private func pick(_ field: Int, _ value: String) {
    guard value != values[field] else { return }
    values[field] = value
    for below in (field + 1)..<5 { values[below] = nil }
  }

  private func add() {
    adding = true
    Task {
      do {
        try await ChoiceListRepository.shared.addChoice(
          listId: listId, counselling: values[0]!, institute: values[1]!, course: values[2]!, quota: values[3]!,
          category: values[4]!)
        app.show("Choice added")
        if openListAfter { onAdded() } else { dismiss() }
      } catch {
        adding = false
        app.show(error.localizedDescription)
      }
    }
  }
}

/// ChoiceOptionPickerSheet: lists over 8 options get a search box and 85% of
/// the screen; short ones just wrap.
private struct OptionPickerSheet: View {
  let title: String
  let searchHint: String
  let options: [String]
  let selected: String?
  let onPick: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var search = ""

  var body: some View {
    let long = options.count > 8
    let query = search.trimmingCharacters(in: .whitespaces).lowercased()
    let shown = options.filter { query.isEmpty || $0.lowercased().contains(query) }
    VStack(spacing: 0) {
      Text(title).font(.inter(16, .semibold)).foregroundStyle(appInk).padding(.top, 24)
      if long {
        HStack(spacing: 10) {
          Image("ic_baseline_search_24").renderingMode(.template).resizable().frame(width: 24, height: 24).foregroundStyle(secondary)
          TextField("", text: $search, prompt: Text(searchHint).foregroundColor(secondary)).font(.inter(15)).foregroundStyle(appInk)
        }
        .padding(.horizontal, 14).frame(height: 48)
        .background(muted, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(stroke))
        .padding(.horizontal, 16).padding(.top, 14)
      }
      Rectangle().fill(Color(hex: 0xECEDF0)).frame(height: 1).padding(.top, 12)
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(shown, id: \.self) { option in
            Button {
              onPick(option)
              dismiss()
            } label: {
              HStack(spacing: 8) {
                Text(option).font(.inter(15, .medium)).foregroundStyle(appInk).multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: option == selected ? "largecircle.fill.circle" : "circle").font(.system(size: 20))
                  .foregroundStyle(stateGreen)
              }
              .padding(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
              .frame(minHeight: 52)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
          if shown.isEmpty {
            Text("No matches found").font(.inter(14)).foregroundStyle(secondary).padding(.top, 32)
          }
        }
        .padding(.bottom, 16)
      }
    }
    .sheetDetents(long ? [.fraction(0.85)] : [.medium, .large])
    .sheetDragIndicatorVisible()
    .sheetCornerRadius(20)
  }
}

/// The system share sheet for an exported file (Save to Files, AirDrop, mail…).
private struct ShareSheet: UIViewControllerRepresentable {
  let url: URL
  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: [url], applicationActivities: nil)
  }
  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
