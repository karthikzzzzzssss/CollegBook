import SwiftUI

private let primarySoft = Color(hex: 0xE0FFC2)
private let pageBg = Color(hex: 0xF4F7F6)
private let cardBorder = Color(hex: 0xE6ECEA)
private let ink = Color(hex: 0x1C1E21)
private let labelColor = Color(hex: 0x374151)
private let muted = Color(hex: 0x6B7280)
private let hint = Color(hex: 0x9CA3AF)
private let fieldBorder = Color(hex: 0xDCE3E0)
private let fieldFill = Color(hex: 0xFAFBFB)
private let lockedFill = Color(hex: 0xF2F4F5)
private let errorColor = Color(hex: 0xD93025)

/// The "degree" values the API accepts (CounselorRegistrationActivity.DEGREES).
private let degrees = ["DNB", "Diploma", "M.Ch", "MBBS", "MD", "MS", "Nbems DMRD"]
/// The least a mentor may charge per minute.
private let minPerMinute = 10

struct Expert: Hashable, Identifiable {
  let id: Int
  let name: String
}

/// Languages a mentor can talk to students in (CounsellorPickActivity.LANGUAGES).
/// Shown capitalised; sent as `know_language` in lowercase, comma-separated ("hindi,telugu").
enum MentorLanguages {
  static let all = [
    "Assamese", "Bengali", "English", "Gujarati", "Hindi", "Kannada", "Malayalam", "Marathi", "Odia", "Punjabi", "Tamil",
    "Telugu", "Urdu",
  ]

  /// "hindi, telugu" → ["hindi", "telugu"].
  static func values(_ raw: String?) -> [String] {
    var seen = Set<String>()
    return (raw ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
      .filter { !$0.isEmpty && seen.insert($0).inserted }
  }

  /// The API value for a selection: "hindi,telugu".
  static func raw(_ values: [String]) -> String { values.joined(separator: ",") }

  static func capitalize(_ word: String) -> String { word.prefix(1).uppercased() + word.dropFirst().lowercased() }

  /// "hindi,telugu" → "Hindi, Telugu"; "" when none.
  static func display(_ raw: String?) -> String { display(values(raw)) }
  static func display(_ values: [String]) -> String { values.map(capitalize).joined(separator: ", ") }
}

private enum Field: CaseIterable {
  case photo, name, speciality, designation, degree, state, institute, experts, languages, fee
}

private func items(_ json: JSONObject) -> [Expert] {
  (json.object("data") ?? [:]).objects("results").compactMap { r in
    r.string("name").map { Expert(id: r.int("id") ?? 0, name: $0) }
  }
}

/// "25.50" → "25.5", "100.00" → "100"; anything unparseable as-is.
private func plainAmount(_ amount: String) -> String {
  let number = NSDecimalNumber(string: amount)
  return number == .notANumber ? amount : number.stringValue
}

private func sameAmount(_ a: String?, _ b: String?) -> Bool {
  guard let a, let b else { return false }
  let x = NSDecimalNumber(string: a), y = NSDecimalNumber(string: b)
  return x != .notANumber && y != .notANumber && x.compare(y) == .orderedSame
}

/// "[1,5]", as the API takes (and compares) expertise.
private func expertIDs(_ experts: [Expert]) -> String { "[\(experts.map { String($0.id) }.joined(separator: ","))]" }

/// Mentor registration: photo, name, speciality, designation, degree, exam
/// type, state, institute, expertise, languages and per-minute fee, posted as
/// multipart to college/counsellor/ (CounselorRegistrationActivity's request).
///
/// With `editing` (an approved mentor's college/counsellor/ data) it is the
/// Edit Profile screen instead (the activity's edit mode): name, exam type and
/// institute are locked (the institute changes through an admin request), and
/// Save sends only what changed to PUT college/counsellor/profile/.
struct MentorRegistrationView: View {
  var editing: JSONObject? = nil

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var photo: Data?
  /// Edit mode: the current photo on the server.
  @State private var photoURL: String?
  @State private var name = ""
  @State private var fee = ""
  @State private var speciality: String?
  @State private var designation: String?
  @State private var degree: String?
  @State private var stateName: String?
  @State private var institute: String?
  @State private var experts: [Expert] = []
  /// Lowercase API values, e.g. ["hindi", "telugu"]. Optional.
  @State private var languages: [String] = []
  @State private var pickingLanguages = false
  /// Inline messages, shown once Submit has been tried.
  @State private var errors: [Field: String] = [:]
  @State private var triedSubmit = false
  @State private var submitting = false
  @State private var choosingPhotoSource = false
  @State private var photoSource: UIImagePickerController.SourceType?
  @State private var picker: PickerRoute?
  @State private var pickingExperts = false
  @State private var showingHelp = false
  @State private var showingTerms = false
  @FocusState private var focus: Field?

  // Edit mode
  /// What the server has, to send only what changed. Nil = not known (yet).
  @State private var saved = Saved()
  @State private var loadedEdit = false
  @State private var loadingRest = false
  /// The institute asked for in a request still waiting for the admin.
  @State private var pendingInstitute: String?
  @State private var requestingInstitute = false

  private struct Saved {
    var speciality, designation, degree, state, fee, expertIDs: String?
    var languages: [String] = []
  }

  private var editMode: Bool { editing != nil }

  private struct PickerRoute: Identifiable, Hashable {
    let title: String
    var endpoint = ""
    var query: [String: String] = [:]
    /// A fixed list instead of an endpoint (degree).
    var options: [String]? = nil
    let field: Field
    var id: String { title }
  }

  private var hasInput: Bool {
    photo != nil || !name.trimmingCharacters(in: .whitespaces).isEmpty || !fee.trimmingCharacters(in: .whitespaces).isEmpty
      || speciality != nil || designation != nil || degree != nil || stateName != nil || institute != nil
      || !experts.isEmpty || !languages.isEmpty
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 12) {
            if !editMode { introCard.padding(.bottom, 4) }
            photoCard.id(Field.photo)
            section("Professional details", "How students will see you") {
              if editMode {
                lockedInput("Full name", name)
              } else {
                textInput(.name, "Full name", "e.g. Dr. Ananya Rao", $name)
              }
              selectInput(.speciality, "Speciality", "Select speciality", speciality) {
                picker = PickerRoute(
                  title: "Select speciality", endpoint: "college/counsellor/drop-down/speciality/", field: .speciality)
              }
              selectInput(.designation, "Designation", "Select designation", designation) {
                picker = PickerRoute(
                  title: "Select designation", endpoint: "college/counsellor/drop-down/designation/", field: .designation)
              }
              selectInput(.degree, "Degree", "Select degree", degree) {
                picker = PickerRoute(title: "Select degree", options: degrees, field: .degree)
              }
              lockedInput("Exam type", "NEET PG")
            }
            section("Your institute", "Where you study or work now") {
              selectInput(.state, "State", "Select state", stateName) {
                picker = PickerRoute(title: "Select state", endpoint: "college/counsellor/drop-down/state/", field: .state)
              }
              if editMode {
                lockedInput("Institute", institute ?? "")
                if let pendingInstitute { pendingNotice(pendingInstitute) }
                requestInstituteButton
              } else {
                selectInput(
                  .institute, "Institute", stateName == nil ? "Select a state first" : "Select institute", institute,
                  disabled: stateName == nil
                ) {
                  guard let stateName else { return app.show("Please select state first") }
                  picker = PickerRoute(
                    title: "Select institute", endpoint: "college/counsellor/drop-down/institute_name/",
                    query: ["state": stateName], field: .institute)
                }
              }
            }
            section("Areas of expertise", "Topics you can guide students on") {
              selectInput(
                .experts, "Expertise", "Select expertise",
                experts.isEmpty ? nil : experts.map(\.name).joined(separator: ", ")
              ) { pickingExperts = true }
            }
            section("Languages", "Languages you can talk to students in") {
              selectInput(
                .languages, "Known languages", "Select languages",
                languages.isEmpty ? nil : MentorLanguages.display(languages)
              ) { pickingLanguages = true }
            }
            section("Consultation fee", "Students are charged per minute of call") {
              textInput(
                .fee, "Fee per minute", "\(minPerMinute)", $fee, prefix: "₹", suffix: "/ min", numeric: true,
                helper: "Minimum ₹\(minPerMinute) per minute. You can change it later.")
            }
          }
          .padding(EdgeInsets(top: 16, leading: 16, bottom: 24, trailing: 16))
        }
        .dismissesKeyboardInteractively()
        .background(pageBg)
        .onChangeCompat(of: errors.count) { _, _ in }
        .onReceive(NotificationCenter.default.publisher(for: .mentorFormScroll)) { note in
          if let field = note.object as? Field { withAnimation { proxy.scrollTo(field, anchor: .top) } }
        }
      }
      submitBar
    }
    .overlay { if loadingRest { loadingOverlay } }
    // Covers, not pushes: anything pushed inside the side menu's mentor
    // screens sends SwiftUI into a layout loop (100% CPU, frozen) on iOS 17.
    .fullScreenCover(isPresented: $pickingLanguages) {
      LanguagesPickerView(selected: languages) { languages = $0 }.environmentObject(app)
    }
    .sheet(isPresented: $requestingInstitute) {
      InstituteRequestSheet(current: institute ?? "") { requested in pendingInstitute = requested } onAlreadyPending: {
        Task { await loadPendingInstituteRequest() }
      }
      .environmentObject(app)
      .sheetDetents([.height(530), .large])
      .sheetDragIndicatorVisible()
    }
    .background(AppColors.primary.ignoresSafeArea(edges: .top))
    .hiddenNavigationBar()
    .coversTabBar()
    .task { await setUpEditMode() }
    .onChangeCompat(of: name) { _, _ in revalidate() }
    .onChangeCompat(of: fee) { _, new in
      // The saved fee can have decimals ("25.50"), unlike at registration.
      let cleaned: String
      if editMode {
        var seenDot = false
        cleaned = String(
          new.filter { c in
            if c == "." { defer { seenDot = true }; return !seenDot }
            return c.isNumber
          }.prefix(8))
      } else {
        cleaned = String(new.filter(\.isNumber).prefix(5))
      }
      if cleaned != new { fee = cleaned }
      revalidate()
    }
    .fullScreenCover(item: Binding(get: { photoSource.map { SourceBox(source: $0) } }, set: { photoSource = $0?.source })) {
      box in
      // A square crop, so the round avatar shows exactly what was chosen.
      SquarePhotoPicker(source: box.source) { image in
        guard let jpeg = Self.shrink(image) else { return app.show("Couldn't read that image") }
        photo = jpeg
        revalidate()
      }
      .ignoresSafeArea()
    }
    .fullScreenCover(item: $picker) { route in
      OptionPickerView(
        title: route.title, endpoint: route.endpoint, query: route.query, options: route.options,
        selected: value(route.field)
      ) {
        set(route.field, $0)
      }
      .environmentObject(app)
    }
    .fullScreenCover(isPresented: $pickingExperts) {
      ExpertsPickerView(selected: experts) {
        experts = $0
        revalidate()
      }
      .environmentObject(app)
    }
    .fullScreenCover(isPresented: $showingHelp) {
      CompatNavigationStack { ContactUsView() }.environmentObject(app)
    }
    .fullScreenCover(isPresented: $showingTerms) {
      CompatNavigationStack { LegalDocumentView(doc: .terms) }.environmentObject(app)
    }
  }

  private struct SourceBox: Identifiable {
    let source: UIImagePickerController.SourceType
    var id: Int { source.rawValue }
  }

  private func value(_ field: Field) -> String? {
    switch field {
    case .speciality: speciality
    case .designation: designation
    case .degree: degree
    case .state: stateName
    case .institute: institute
    default: nil
    }
  }

  private func set(_ field: Field, _ value: String) {
    switch field {
    case .speciality: speciality = value
    case .designation: designation = value
    case .degree: degree = value
    case .state:
      // The institute list depends on the state; in edit mode the institute
      // is locked, so the state doesn't touch it.
      if !editMode, value != stateName { institute = nil }
      stateName = value
    case .institute: institute = value
    default: break
    }
    revalidate()
  }

  /// A JPEG no larger than 1000px a side at quality 85.
  private static func shrink(_ image: UIImage) -> Data? {
    let upright = image.normalized()
    let side = max(upright.size.width, upright.size.height)
    let scale = side > 1000 ? 1000 / side : 1
    let size = CGSize(width: upright.size.width * scale, height: upright.size.height * scale)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: size, format: format).image { _ in upright.draw(in: CGRect(origin: .zero, size: size)) }
      .jpegData(compressionQuality: 0.85)
  }

  // MARK: Edit mode

  private static func trimmed(_ value: Any?) -> String? {
    guard let s = (value as? String)?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
    return s
  }

  /// Fills the form from the profile, then loads what college/counsellor/ leaves out.
  private func setUpEditMode() async {
    guard var editing, !loadedEdit else { return }
    loadedEdit = true
    // The latest profile, not the one As a Mentor loaded earlier: it may have
    // changed since (e.g. on another device), and loadRestOfProfile re-sends
    // the languages, so stale ones would be written back.
    loadingRest = true
    if let json = try? await app.api.get("college/counsellor/"), json.string("message") == "COUNSELLOR_PROFILE",
      let fresh = json.object("data")
    {
      editing = fresh
    }
    name = editing.string("name") ?? ""
    photoURL = editing["image"] as? String
    institute = Self.trimmed(editing["institute_name"])
    stateName = Self.trimmed(editing["state"])
    speciality = Self.trimmed(editing["speciality"])
    designation = Self.trimmed(editing["designation"])
    languages = MentorLanguages.values(editing["know_language"] as? String)
    saved.state = stateName
    saved.speciality = speciality
    saved.designation = designation
    saved.languages = languages
    async let rest: Void = loadRestOfProfile()
    async let pending: Void = loadPendingInstituteRequest()
    _ = await (rest, pending)
  }

  /// college/counsellor/ doesn't return degree, expertise or fee, but the
  /// profile PUT answers with the full card: re-sending the current languages
  /// changes nothing and gets those three. If this fails they stay blank, and
  /// Save leaves whatever the mentor didn't fill in untouched.
  private func loadRestOfProfile() async {
    loadingRest = true
    defer { loadingRest = false }
    guard
      let card = try? await app.api.request(
        "PUT", "college/counsellor/profile/", body: ["know_language": MentorLanguages.raw(saved.languages)]
      ).object("data")
    else { return }
    saved.degree = Self.trimmed(card["degree"])
    if degree == nil { degree = saved.degree }
    let cardExperts = card.objects("expert").compactMap { e in e.string("name").map { Expert(id: e.int("id") ?? 0, name: $0) } }
    saved.expertIDs = expertIDs(cardExperts)
    if experts.isEmpty { experts = cardExperts }
    if let amount = card.object("appointment")?.string("consultation_fee"), !amount.isEmpty {
      saved.fee = amount
      if fee.isEmpty { fee = plainAmount(amount) }
    }
  }

  /// A request still waiting for the admin stays visible when the form is reopened.
  private func loadPendingInstituteRequest() async {
    guard let json = try? await app.api.get("college/counsellor/institute-change-request/") else { return }
    let pending = (json["data"] as? [JSONObject] ?? []).first { $0.string("status") == "PENDING" }
    pendingInstitute = pending.flatMap { Self.trimmed($0["requested_institute_name"]) }
  }

  private func saveChanges() {
    focus = nil
    var fields: [String: String] = [:]
    func addIfChanged(_ key: String, _ value: String?, _ old: String?) {
      if let value, value != old { fields[key] = value }
    }
    addIfChanged("state", stateName, saved.state)
    addIfChanged("speciality", speciality, saved.speciality)
    addIfChanged("designation", designation, saved.designation)
    addIfChanged("degree", degree, saved.degree)
    addIfChanged("expert", experts.isEmpty ? nil : expertIDs(experts), saved.expertIDs)
    // "" clears them.
    if languages != saved.languages { fields["know_language"] = MentorLanguages.raw(languages) }

    let amount = fee.trimmingCharacters(in: .whitespaces)
    if amount.isEmpty {
      // Blank is only fine when the current fee couldn't be loaded: nothing to change then.
      if saved.fee != nil { return app.show("Please enter per minute amount") }
    } else if !sameAmount(amount, saved.fee) {
      guard let value = Double(amount) else { return app.show("Enter a valid per minute amount") }
      if value < Double(minPerMinute) { return app.show("Per minute amount should be at least ₹\(minPerMinute)") }
      fields["per_min"] = amount
    }

    let file = photo.map { APIClient.UploadFile(field: "image", data: $0, fileName: "mentor_profile.jpg", mimeType: "image/jpeg") }
    if fields.isEmpty && file == nil { return app.show("No changes to save") }

    submitting = true
    Task {
      defer { submitting = false }
      do {
        let result = try await app.api.postMultipart("college/counsellor/profile/", method: "PUT", fields: fields, file: file)
        if (200..<300).contains(result.status) {
          app.show("Profile updated")
          dismiss()  // As a Mentor reloads the profile when this closes.
        } else if result.status == 409 {
          app.show("You can't change your fee during a call. Try again after it ends.")
        } else {
          app.show(Self.errorMessage(result.json))
        }
      } catch {
        app.show("Network error. Please try again.")
      }
    }
  }

  /// The server's message, or a generic one; `message` can be an object of field errors.
  static func errorMessage(_ json: JSONObject?) -> String {
    if let message = json?["message"] as? String, !message.isEmpty { return message }
    if let description = json?["description"] as? String, !description.isEmpty { return description }
    return "Something went wrong"
  }

  // MARK: Validation

  private func revalidate() { if triedSubmit && !editMode { validate() } }

  /// Fills `errors` for every missing or invalid field.
  private func validate() {
    var e: [Field: String] = [:]
    if photo == nil { e[.photo] = "Please add a profile photo" }
    if name.trimmingCharacters(in: .whitespaces).isEmpty { e[.name] = "Please enter your name" }
    if speciality == nil { e[.speciality] = "Please select your speciality" }
    if designation == nil { e[.designation] = "Please select your designation" }
    if degree == nil { e[.degree] = "Please select your degree" }
    if stateName == nil { e[.state] = "Please select a state" }
    if institute == nil { e[.institute] = "Please select your institute" }
    if experts.isEmpty { e[.experts] = "Please select your expertise" }
    let value = fee.trimmingCharacters(in: .whitespaces)
    if value.isEmpty {
      e[.fee] = "Please enter your fee per minute"
    } else if let amount = Double(value) {
      if amount < Double(minPerMinute) { e[.fee] = "Fee should be at least ₹\(minPerMinute) per minute" }
    } else {
      e[.fee] = "Enter a valid amount"
    }
    errors = e
  }

  private func submit() {
    if editMode { return saveChanges() }
    focus = nil
    triedSubmit = true
    validate()
    if let first = Field.allCases.first(where: { errors[$0] != nil }) {
      app.show(errors[first]!)
      NotificationCenter.default.post(name: .mentorFormScroll, object: first)
      if first == .name || first == .fee { focus = first }
      return
    }
    submitting = true
    Task {
      defer { submitting = false }
      var message: String
      var ok = false
      do {
        var fields = [
          "name": name.trimmingCharacters(in: .whitespaces), "state": stateName!, "institute_name": institute!,
          "speciality": speciality!, "designation": designation!, "degree": degree!,
          "expert": expertIDs(experts), "per_min": fee.trimmingCharacters(in: .whitespaces),
          "exam_type": "NEET_PG",
        ]
        // Optional: left out entirely when none are picked, as on Android.
        if !languages.isEmpty { fields["know_language"] = MentorLanguages.raw(languages) }
        let result = try await app.api.postMultipart(
          "college/counsellor/",
          fields: fields,
          file: APIClient.UploadFile(field: "image", data: photo!, fileName: "mentor_profile.jpg", mimeType: "image/jpeg"))
        ok = (200..<300).contains(result.status)
        message = result.json?.string(["description", "message"]) ?? (ok ? "Registration submitted" : "Something went wrong")
      } catch {
        message = "Network error. Please try again."
      }
      app.show(message)
      if ok { dismiss() }
    }
  }

  /// Back with a half-filled form asks before throwing it away.
  private func back() {
    guard !submitting else { return }
    guard !editMode, hasInput else { return dismiss() }
    Task {
      if await NativeAlert.show(
        title: "Discard application?", message: "The details you have entered will be lost.", negative: "Keep editing",
        positive: "Discard", destructive: true)
      {
        dismiss()
      }
    }
  }

  // MARK: Pieces

  private var header: some View {
    HStack(spacing: 8) {
      Button(action: back) {
        Image(systemName: "arrow.left").font(.system(size: 20, weight: .medium)).foregroundStyle(.white).padding(8)
      }
      .accessibilityLabel("Back")
      Text(editMode ? "Edit Profile" : "Become a Mentor").font(.inter(18, .bold)).foregroundStyle(.white)
      Spacer()
      Button {
        showingHelp = true
      } label: {
        Image(systemName: "headphones").font(.system(size: 20)).foregroundStyle(.white).padding(12)
      }
      .accessibilityLabel("Help")
    }
    .padding(.leading, 8).padding(.trailing, 4)
    .frame(height: 56)
    .background(AppColors.primary)
  }

  private var loadingOverlay: some View {
    ZStack {
      Color.black.opacity(0.25).ignoresSafeArea()
      HStack(spacing: 14) {
        ProgressView().tint(AppColors.primary)
        Text("Loading...").font(.inter(15, .medium)).foregroundStyle(ink)
      }
      .padding(.horizontal, 24).padding(.vertical, 18)
      .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
  }

  private var introCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 12) {
        Image("ic_menu_mentor").renderingMode(.template).resizable().foregroundStyle(.white).padding(10)
          .frame(width: 44, height: 44).background(.white.opacity(0.15), in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text("Guide NEET PG aspirants").font(.inter(17, .bold)).foregroundStyle(.white)
          Text("Earn on your own schedule").font(.inter(13)).foregroundStyle(.white.opacity(0.8))
        }
      }
      ForEach(
        [
          ("video", "1:1 video consultations with students"), ("indianrupeesign", "You set your own per-minute fee"),
          ("checkmark.seal", "Verified mentor badge on approval"),
        ], id: \.1
      ) { icon, text in
        HStack(spacing: 10) {
          Image(systemName: icon).font(.system(size: 15)).foregroundStyle(primarySoft).frame(width: 18)
          Text(text).font(.inter(13)).foregroundStyle(.white.opacity(0.9))
        }
        .padding(.top, 10)
      }
      .padding(.top, 4)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      LinearGradient(colors: [stateGreen, AppColors.primary], startPoint: .topLeading, endPoint: .bottomTrailing),
      in: RoundedRectangle(cornerRadius: 16))
  }

  private func cardBackground(error: Bool = false) -> some View {
    RoundedRectangle(cornerRadius: 16).fill(.white)
      .overlay(RoundedRectangle(cornerRadius: 16).stroke(error ? Color(hex: 0xF3B9B4) : cardBorder))
  }

  private var photoCard: some View {
    let error = errors[.photo]
    let hasPhoto = photo != nil || !(photoURL ?? "").isEmpty
    return HStack(spacing: 16) {
      Button {
        focus = nil
        choosingPhotoSource = true
      } label: {
        ZStack(alignment: .bottomTrailing) {
          Group {
            if let photo, let image = UIImage(data: photo) {
              Image(uiImage: image).resizable().scaledToFill()
            } else if let photoURL, !photoURL.isEmpty {
              NetImage(photoURL, placeholder: "home_iv_user_profile")
            } else {
              Image(systemName: "person.fill").font(.system(size: 40)).foregroundStyle(Color(hex: 0xB7C0C7))
            }
          }
          .frame(width: 76, height: 76)
          .background(Color(hex: 0xEEF2F4))
          .clipShape(Circle())
          .overlay(Circle().stroke(error != nil ? errorColor : .white, lineWidth: 3))
          .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
          Image(systemName: hasPhoto ? "camera.fill" : "camera").font(.system(size: 12)).foregroundStyle(.white)
            .frame(width: 28, height: 28).background(AppColors.primary, in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .offset(x: 2, y: 2)
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(hasPhoto ? "Change profile photo" : "Add profile photo")
      VStack(alignment: .leading, spacing: 4) {
        Text("Profile photo").font(.inter(15, .semibold)).foregroundStyle(ink)
        Text(error ?? "A clear photo helps students recognise and trust you.").font(.inter(12.5))
          .foregroundStyle(error != nil ? errorColor : muted).lineSpacing(3)
        Button(hasPhoto ? "Change photo" : "Upload photo") {
          focus = nil
          choosingPhotoSource = true
        }
        .font(.inter(13.5, .semibold)).foregroundStyle(AppColors.primary).padding(.vertical, 4).padding(.top, 2)
      }
      Spacer(minLength: 0)
    }
    .padding(16)
    .background(cardBackground(error: error != nil))
    // On the card, not the whole form: an iPad shows this as a popover pointing
    // at its view, and one anchored to the full-screen form never appears.
    .confirmationDialog("Profile photo", isPresented: $choosingPhotoSource, titleVisibility: .visible) {
      Button("Choose from gallery") { photoSource = .photoLibrary }
      Button("Take a photo") {
        if UIImagePickerController.isSourceTypeAvailable(.camera) { photoSource = .camera } else {
          app.show("Camera not available")
        }
      }
    } message: {
      Text("Use a clear, recent photo of your face.")
    }
  }

  private func section<Content: View>(_ title: String, _ subtitle: String, @ViewBuilder _ content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 0) {
      Text(title).font(.inter(15, .bold)).foregroundStyle(ink)
      Text(subtitle).font(.inter(12.5)).foregroundStyle(muted).padding(.top, 2).padding(.bottom, 14)
      content()
    }
    .padding(EdgeInsets(top: 16, leading: 16, bottom: 4, trailing: 16))
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(cardBackground())
  }

  /// Field label above a box, with an inline error or helper below.
  private func frame<Content: View>(_ label: String, error: String?, helper: String? = nil, @ViewBuilder _ content: () -> Content)
    -> some View
  {
    VStack(alignment: .leading, spacing: 6) {
      Text(label).font(.inter(13, .semibold)).foregroundStyle(labelColor)
      content()
      if let note = error ?? helper {
        HStack(alignment: .top, spacing: 4) {
          if error != nil { Image(systemName: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(errorColor) }
          Text(note).font(.inter(12)).foregroundStyle(error != nil ? errorColor : muted)
        }
        .padding(.leading, 2)
      }
    }
    .padding(.bottom, 14)
  }

  private func boxBorder(error: Bool, focused: Bool) -> some View {
    RoundedRectangle(cornerRadius: 12).stroke(
      error ? errorColor : focused ? AppColors.primary : fieldBorder, lineWidth: error || focused ? 1.5 : 1)
  }

  private func textInput(
    _ field: Field, _ label: String, _ placeholder: String, _ text: Binding<String>, prefix: String? = nil,
    suffix: String? = nil, numeric: Bool = false, helper: String? = nil
  ) -> some View {
    frame(label, error: errors[field], helper: helper) {
      HStack(spacing: 8) {
        if let prefix { Text(prefix).font(.inter(15, .semibold)).foregroundStyle(ink) }
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(hint))
          .font(.inter(15, .medium)).foregroundStyle(ink)
          .keyboardType(numeric ? (editMode ? .decimalPad : .numberPad) : .default)
          .textInputAutocapitalization(numeric ? .never : .words)
          .textContentType(numeric ? nil : .name)
          .focused($focus, equals: field)
          .onChangeCompat(of: text.wrappedValue) { _, new in if !numeric, new.count > 60 { text.wrappedValue = String(new.prefix(60)) } }
        if let suffix { Text(suffix).font(.inter(14)).foregroundStyle(muted) }
      }
      .padding(.horizontal, 14)
      .frame(minHeight: 52)
      .background(fieldFill, in: RoundedRectangle(cornerRadius: 12))
      .overlay(boxBorder(error: errors[field] != nil, focused: focus == field))
      .id(field)
    }
  }

  /// A read-only value with a lock (bg_mentor_reg_field_locked).
  private func lockedInput(_ label: String, _ value: String) -> some View {
    frame(label, error: nil) {
      HStack(spacing: 8) {
        Text(value).font(.inter(15, .medium)).foregroundStyle(muted).multilineTextAlignment(.leading)
        Spacer(minLength: 8)
        Image(systemName: "lock.fill").font(.system(size: 14)).foregroundStyle(hint)
      }
      .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
      .frame(minHeight: 52)
      .background(lockedFill, in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(fieldBorder))
      .accessibilityElement(children: .combine)
      .accessibilityLabel("\(label), \(value), locked")
    }
  }

  private func selectInput(
    _ field: Field?, _ label: String, _ placeholder: String, _ value: String?, disabled: Bool = false,
    action: @escaping () -> Void
  ) -> some View {
    let error = field.flatMap { errors[$0] }
    return frame(label, error: error) {
      Button {
        focus = nil
        action()
      } label: {
        HStack(spacing: 8) {
          Text(value ?? placeholder).font(.inter(15, value != nil ? .medium : .regular))
            .foregroundStyle(value != nil ? ink : hint).multilineTextAlignment(.leading)
          Spacer()
          Image(systemName: "chevron.right").font(.system(size: 15, weight: .medium)).foregroundStyle(disabled ? hint : muted)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 10))
        .frame(minHeight: 52)
        .background(disabled ? lockedFill : fieldFill, in: RoundedRectangle(cornerRadius: 12))
        .overlay(boxBorder(error: error != nil, focused: false))
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("\(label), \(value ?? placeholder)")
      .id(field)
    }
  }

  /// tvInstitutePending: the request waiting for the admin.
  private func pendingNotice(_ requested: String) -> some View {
    Text("Change requested: \(requested)\nWaiting for admin approval. Your current institute stays until then.")
      .font(.inter(12.5, .medium)).foregroundStyle(Color(hex: 0x8A5A00)).lineSpacing(2)
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(hex: 0xFFF7E6), in: RoundedRectangle(cornerRadius: 12))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xF5D48A)))
      .padding(.bottom, 12)
  }

  private var requestInstituteButton: some View {
    Button {
      focus = nil
      if pendingInstitute != nil {
        app.show("You already have a pending institute change request.")
      } else {
        requestingInstitute = true
      }
    } label: {
      Text("Request institute change").font(.inter(14, .semibold)).foregroundStyle(AppColors.primary)
        .frame(maxWidth: .infinity).frame(height: 48)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.primary))
    }
    .buttonStyle(.plain)
    .padding(.bottom, 14)
  }

  /// The sticky bottom bar: Submit (or Save changes) and, when registering, the terms note.
  private var submitBar: some View {
    VStack(spacing: 8) {
      Button(action: submit) {
        HStack(spacing: 12) {
          if submitting { ProgressView().tint(.white) }
          Text(
            editMode ? (submitting ? "Saving..." : "Save changes") : (submitting ? "Submitting…" : "Submit application")
          )
          .font(.inter(16, .bold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity).frame(height: 52)
        .background(submitting ? Color(hex: 0x5E8A82) : AppColors.primary, in: RoundedRectangle(cornerRadius: 12))
      }
      .buttonStyle(.plain)
      .disabled(submitting || loadingRest)
      if !editMode {
        Button {
          showingTerms = true
        } label: {
          (Text("By submitting, you agree to our ") + Text("Terms & Conditions").foregroundColor(AppColors.primary).fontWeight(.semibold))
            .font(.inter(12)).foregroundStyle(muted).multilineTextAlignment(.center)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
    .background(.white)
    .overlay(alignment: .top) { Rectangle().fill(cardBorder).frame(height: 1) }
  }
}

extension Notification.Name {
  fileprivate static let mentorFormScroll = Notification.Name("MentorFormScroll")
}

/// bottomsheet_request_institute: asks the admin to approve a new institute.
private struct InstituteRequestSheet: View {
  let current: String
  let onSent: (String) -> Void
  let onAlreadyPending: () -> Void

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var requested = ""
  @State private var reason = ""
  @State private var error: String?
  @State private var sending = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top) {
          Text("Change institute").font(.inter(20, .bold)).foregroundStyle(AppColors.primary)
          Spacer()
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(ink).padding(4)
          }
          .accessibilityLabel("Close")
        }
        Text("Our admin team reviews this request. Your current institute stays on your profile until it's approved.")
          .font(.inter(13)).foregroundStyle(muted).lineSpacing(2).padding(.top, 6)

        label("Current institute").padding(.top, 20)
        Text(current).font(.inter(15, .medium)).foregroundStyle(labelColor)
          .padding(14).frame(maxWidth: .infinity, alignment: .leading)
          .background(lockedFill, in: RoundedRectangle(cornerRadius: 12))
          .overlay(RoundedRectangle(cornerRadius: 12).stroke(fieldBorder))

        label("New institute name").padding(.top, 18)
        TextField("", text: $requested, prompt: Text("Enter institute name").foregroundColor(hint))
          .font(.inter(15, .medium)).foregroundStyle(ink).textInputAutocapitalization(.words)
          .padding(.horizontal, 14).frame(height: 52)
          .background(fieldFill, in: RoundedRectangle(cornerRadius: 12))
          .overlay(RoundedRectangle(cornerRadius: 12).stroke(error != nil ? errorColor : fieldBorder))
          .onChangeCompat(of: requested) { _, _ in error = nil }
        if let error {
          Text(error).font(.inter(12)).foregroundStyle(errorColor).padding(.top, 6).padding(.leading, 2)
        }

        label("Reason (optional)").padding(.top, 18)
        MultilineTextField($reason, prompt: Text("Why are you changing your institute?").foregroundColor(hint), lines: 2...4)
          .font(.inter(15, .medium)).foregroundStyle(ink)
          .padding(14).frame(minHeight: 66, alignment: .topLeading)
          .background(fieldFill, in: RoundedRectangle(cornerRadius: 12))
          .overlay(RoundedRectangle(cornerRadius: 12).stroke(fieldBorder))

        Button(action: send) {
          HStack(spacing: 12) {
            if sending { ProgressView().tint(.white) }
            Text(sending ? "Sending..." : "Send request").font(.inter(16, .bold))
          }
          .foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 52)
          .background(AppColors.primary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(sending)
        .padding(.top, 22)
      }
      .padding(EdgeInsets(top: 28, leading: 20, bottom: 20, trailing: 20))
    }
    .background(.white)
  }

  private func label(_ text: String) -> some View {
    Text(text).font(.inter(13, .semibold)).foregroundStyle(labelColor).padding(.bottom, 6)
  }

  private func send() {
    let name = requested.trimmingCharacters(in: .whitespaces)
    if name.isEmpty { return error = "Please enter the institute name" }
    if name.caseInsensitiveCompare(current) == .orderedSame { return error = "This is already your institute" }
    sending = true
    Task {
      defer { sending = false }
      do {
        _ = try await app.api.request(
          "POST", "college/counsellor/institute-change-request/",
          body: [
            "requested_institute_name": name, "current_institute_name": current,
            "reason": reason.trimmingCharacters(in: .whitespaces),
          ])
        // The sheet closes only once the request is sent, so a failure doesn't lose what was typed.
        onSent(name)
        app.show("Request sent to admin")
        dismiss()
      } catch let failure as APIError {
        switch failure.statusCode {
        case 409:
          // A request is already waiting for the admin (e.g. sent from another device).
          app.show("You already have a pending institute change request.")
          onAlreadyPending()
          dismiss()
        case 404:
          // Server without this feature yet.
          app.show("Institute change requests aren't available yet. Please contact support.")
        case nil:
          app.show("Network error. Please try again.")
        default:
          app.show(MentorRegistrationView.errorMessage(failure.payload))
        }
      } catch {
        app.show("Network error. Please try again.")
      }
    }
  }
}

/// The system photo picker / camera with the square crop editor.
private struct SquarePhotoPicker: UIViewControllerRepresentable {
  let source: UIImagePickerController.SourceType
  let onImage: (UIImage) -> Void
  @Environment(\.dismiss) private var dismiss

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeUIViewController(context: Context) -> UIImagePickerController {
    let picker = UIImagePickerController()
    picker.sourceType = source
    picker.allowsEditing = true
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let parent: SquarePhotoPicker
    init(_ parent: SquarePhotoPicker) { self.parent = parent }

    func imagePickerController(
      _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
      // Backing out of the editor keeps the current photo.
      if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage { parent.onImage(image) }
      parent.dismiss()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
  }
}

// MARK: - Pickers

/// Shared picker chrome, as CounsellorPickActivity: green header, then a
/// green-outlined search box on white, then the list.
private struct PickerScaffold<Body: View, Bottom: View>: View {
  let title: String
  @Binding var query: String
  @ViewBuilder let content: Body
  @ViewBuilder let bottom: Bottom
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Button {
          dismiss()
        } label: {
          Image(systemName: "arrow.left").font(.system(size: 20, weight: .medium)).foregroundStyle(.white).padding(8)
        }
        .accessibilityLabel("Back")
        Text(title).font(.inter(18, .bold)).foregroundStyle(.white).lineLimit(1)
        Spacer()
      }
      .padding(.leading, 8)
      .frame(height: 56)
      .background(AppColors.primary)
      VStack(spacing: 0) {
        HStack(spacing: 10) {
          Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .medium)).foregroundStyle(muted)
          TextField("", text: $query, prompt: Text("Search").foregroundColor(hint)).font(.inter(15)).foregroundStyle(ink)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(.white, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppColors.primary, lineWidth: 1))
        .padding(EdgeInsets(top: 12, leading: 16, bottom: 6, trailing: 16))
        content.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      .background(.white)
      bottom
    }
    .background(AppColors.primary.ignoresSafeArea(edges: .top))
    .hiddenNavigationBar()
    .coversTabBar()
  }
}

/// A picker row (row_counsellor_pick): the name, and a green verified tick when chosen.
private func pickRow(_ name: String, _ checked: Bool, action: @escaping () -> Void) -> some View {
  Button(action: action) {
    HStack(spacing: 12) {
      Text(name).font(.inter(15)).foregroundStyle(ink).multilineTextAlignment(.leading).padding(.vertical, 14)
      Spacer()
      Image(systemName: "checkmark.seal.fill").font(.system(size: 20)).foregroundStyle(AppColors.primary)
        .opacity(checked ? 1 : 0)
    }
    .padding(.horizontal, 20)
    .frame(minHeight: 50)
    .contentShape(Rectangle())
  }
  .buttonStyle(.plain)
  .accessibilityAddTraits(checked ? .isSelected : [])
}

/// The multi-select Done bar: "Done (3 selected)".
private func doneBar(_ count: Int, action: @escaping () -> Void) -> some View {
  Button(action: action) {
    Text(count > 0 ? "Done (\(count) selected)" : "Done").font(.inter(16, .bold)).foregroundStyle(.white)
      .frame(maxWidth: .infinity).frame(height: 52)
      .background(AppColors.primary, in: RoundedRectangle(cornerRadius: 12))
  }
  .buttonStyle(.plain)
  .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
  .background(.white)
}

private func pickerMessage(_ icon: String, _ text: String) -> some View {
  VStack(spacing: 12) {
    Image(systemName: icon).font(.system(size: 36)).foregroundStyle(hint)
    Text(text).font(.inter(14)).foregroundStyle(muted).multilineTextAlignment(.center)
  }
  .padding(32)
  .frame(maxWidth: .infinity, maxHeight: .infinity)
}

/// Single-select options (speciality, designation, state, institute), or a fixed list (degree).
private struct OptionPickerView: View {
  let title: String
  let endpoint: String
  let query: [String: String]
  var options: [String]? = nil
  let selected: String?
  let onPick: (String) -> Void

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var all: [Expert]?
  @State private var search = ""

  var body: some View {
    let q = search.trimmingCharacters(in: .whitespaces).lowercased()
    let shown = (all ?? []).filter { q.isEmpty || $0.name.lowercased().contains(q) }
    PickerScaffold(title: title, query: $search) {
      if all == nil {
        ProgressView().tint(AppColors.primary).controlSize(.large)
      } else if all!.isEmpty {
        pickerMessage("tray", "Nothing to show right now")
      } else if shown.isEmpty {
        pickerMessage("magnifyingglass", "No matches for your search")
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(shown) { item in
              pickRow(item.name, item.name == selected) {
                onPick(item.name)
                dismiss()
              }
            }
          }
        }
      }
    } bottom: {
      EmptyView()
    }
    .task {
      if let options {
        all = options.enumerated().map { Expert(id: $0.offset, name: $0.element) }
        return
      }
      let json = try? await app.api.get(endpoint, query: query)
      // The drop-downs come without ids (all would be 0 and the list would
      // show only the first row): positions, as CounsellorPickActivity uses.
      all = (json.map(items) ?? []).enumerated().map { Expert(id: $0.offset, name: $0.element.name) }
    }
  }
}

/// Multi-select from the fixed language list. Unlike expertise an empty
/// selection is allowed: it clears them.
struct LanguagesPickerView: View {
  /// Lowercase API values.
  let selected: [String]
  let onDone: ([String]) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var chosen: Set<String> = []
  @State private var search = ""

  /// The fixed list, plus any saved language that isn't in it so it isn't dropped.
  private var names: [String] {
    MentorLanguages.all + selected.map(MentorLanguages.capitalize).filter { !MentorLanguages.all.contains($0) }
  }

  var body: some View {
    let q = search.trimmingCharacters(in: .whitespaces).lowercased()
    let shown = names.filter { q.isEmpty || $0.lowercased().contains(q) }
    PickerScaffold(title: "Select languages", query: $search) {
      if shown.isEmpty {
        pickerMessage("magnifyingglass", "No matches for your search")
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(shown, id: \.self) { name in
              let value = name.lowercased()
              pickRow(name, chosen.contains(value)) {
                if chosen.remove(value) == nil { chosen.insert(value) }
              }
            }
          }
          .padding(.bottom, 8)
        }
      }
    } bottom: {
      doneBar(chosen.count) {
        // Keep the order they appear in the list.
        onDone(names.map { $0.lowercased() }.filter(chosen.contains))
        dismiss()
      }
    }
    .onAppear { chosen = Set(selected) }
  }
}

/// Multi-select expertise over the paged list.
private struct ExpertsPickerView: View {
  let selected: [Expert]
  let onDone: ([Expert]) -> Void

  @EnvironmentObject private var app: AppState
  @Environment(\.dismiss) private var dismiss
  @State private var all: [Expert] = []
  @State private var chosen: [Int: Expert] = [:]
  @State private var search = ""
  @State private var page = 1
  @State private var hasNext = true
  @State private var loading = false
  @State private var loadedOnce = false

  var body: some View {
    let q = search.trimmingCharacters(in: .whitespaces).lowercased()
    let shown = all.filter { q.isEmpty || $0.name.lowercased().contains(q) }
    PickerScaffold(title: "Select expertise", query: $search) {
      if !loadedOnce {
        ProgressView().tint(AppColors.primary).controlSize(.large)
      } else if all.isEmpty {
        pickerMessage("tray", "Nothing to show right now")
      } else if shown.isEmpty {
        pickerMessage("magnifyingglass", "No matches for your search")
      } else {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
              pickRow(item.name, chosen[item.id] != nil) {
                if chosen.removeValue(forKey: item.id) == nil { chosen[item.id] = item }
              }
              .onAppear { if index >= shown.count - 5 { Task { await load() } } }
            }
            if loading { ProgressView().tint(AppColors.primary).padding(16) }
          }
          .padding(.bottom, 8)
        }
      }
    } bottom: {
      doneBar(chosen.count) {
        guard !chosen.isEmpty else { return app.show("Please select at least one") }
        // Keep the order they appear in the list.
        onDone(all.filter { chosen[$0.id] != nil } + chosen.values.filter { e in !all.contains(e) })
        dismiss()
      }
    }
    .task {
      chosen = Dictionary(selected.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      await load()
    }
  }

  private func load() async {
    guard !loading, hasNext else { return }
    loading = true
    do {
      let json = try await app.api.get("college/counsellor-expert/", query: ["page": "\(page)", "limit": "50"])
      hasNext = json.object("data")?.bool("next") == true
      page += 1
      var seen = Set(all.map(\.id))
      all += items(json).filter { seen.insert($0.id).inserted }
    } catch {
      hasNext = false
    }
    loading = false
    loadedOnce = true
  }
}
