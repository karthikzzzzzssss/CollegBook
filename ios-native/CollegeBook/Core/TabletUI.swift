import SwiftUI

/// iPad layout tweaks, mirroring Android's TabletUi (values-sw600dp/tablet.xml).
/// Everything keys off the regular horizontal size class (an iPad full screen
/// or a wide split view), so on iPhones each helper is a no-op and the phone UI
/// stays exactly as it was.
enum TabletUI {
  /// @integer/list_columns on tablets.
  static let listColumns = 2
  /// @dimen/content_max_width: reading-width column for Home and Premium.
  static let contentMaxWidth: CGFloat = 840
  /// @dimen/login_card_max_width.
  static let loginCardMaxWidth: CGFloat = 560
}

private struct ListCellWidthKey: EnvironmentKey {
  static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
  /// Width of the list column a card sits in, when a TabletList has split the
  /// screen into columns; nil means the card spans the whole screen.
  var listCellWidth: CGFloat? {
    get { self[ListCellWidthKey.self] }
    set { self[ListCellWidthKey.self] = newValue }
  }
}

/// TabletUi.verticalList: rows of a main card list (Colleges, Mentors,
/// Community). Phones get the same plain column as before; tablets a 2-column
/// grid. Drop it inside the list's existing LazyVStack, so headers and footers
/// around it still span the full width.
struct TabletList<Data: RandomAccessCollection, ID: Hashable, Content: View>: View {
  let data: Data
  let id: KeyPath<Data.Element, ID>
  @ViewBuilder let content: (Data.Element) -> Content

  @Environment(\.horizontalSizeClass) private var sizeClass
  @State private var width: CGFloat = 0

  init(_ data: Data, id: KeyPath<Data.Element, ID>, @ViewBuilder content: @escaping (Data.Element) -> Content) {
    self.data = data
    self.id = id
    self.content = content
  }

  var body: some View {
    if sizeClass == .regular {
      let columns = TabletUI.listColumns
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .top), count: columns),
        alignment: .leading, spacing: 0
      ) {
        ForEach(data, id: id) { element in
          content(element).environment(\.listCellWidth, width > 0 ? width / CGFloat(columns) : nil)
        }
      }
      .background(
        GeometryReader { geo in
          Color.clear
            .onAppear { width = geo.size.width }
            .onChangeCompat(of: geo.size.width) { _, new in width = new }
        }
      )
    } else {
      ForEach(data, id: id) { content($0) }
    }
  }
}

extension TabletList where Data.Element: Identifiable, ID == Data.Element.ID {
  init(_ data: Data, @ViewBuilder content: @escaping (Data.Element) -> Content) {
    self.init(data, id: \.id, content: content)
  }
}

/// TabletUi.limitContentWidth: on tablets the content sits in a centred column
/// no wider than 840pt, so cards and text don't stretch edge to edge; whatever
/// background is behind it still fills the full width.
private struct TabletContentWidth: ViewModifier {
  let maxWidth: CGFloat
  @Environment(\.horizontalSizeClass) private var sizeClass

  func body(content: Content) -> some View {
    if sizeClass == .regular {
      content.frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
    } else {
      content
    }
  }
}

extension View {
  func tabletContentWidth(_ maxWidth: CGFloat = TabletUI.contentMaxWidth) -> some View {
    modifier(TabletContentWidth(maxWidth: maxWidth))
  }
}
