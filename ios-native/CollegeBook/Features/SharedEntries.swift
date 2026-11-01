import SwiftUI

// Screens the Home tab opens that live in other features.

/// ChoiceListsPage (lib/features/choice/choice_screens.dart).
struct ChoiceListsEntry: View {
  let isSubscribed: Bool
  let openPackages: () -> Void
  var body: some View { ChoiceListsView(isSubscribed: isSubscribed, onGetPackage: openPackages) }
}

/// ReelsPlayerPage (lib/features/videos/reels_player_page.dart).
struct ReelsEntry: View {
  let startId: String
  let recommended: Bool
  var body: some View { ReelsPlayerView(startId: startId, recommended: recommended) }
}
