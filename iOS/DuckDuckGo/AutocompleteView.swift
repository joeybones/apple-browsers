//
//  AutocompleteView.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons

struct AutocompleteView: View {

    @ObservedObject var model: AutocompleteViewModel

    var body: some View {
        List {
            if model.isMessageVisible {
                HistoryMessageView {
                    model.onDismissMessage()
                }
                .listRowBackground(Color(designSystemColor: .surface))
                .onAppear {
                    model.onShownToUser()
                }
            }
            
            SuggestionsSection(suggestions: model.topHits,
                               query: model.query,
                               onSuggestionSelected: model.onSuggestionSelected,
                               onSuggestionDeleted: model.deleteSuggestion)

            SuggestionsSection(suggestions: model.ddgSuggestions,
                               query: model.query,
                               onSuggestionSelected: model.onSuggestionSelected,
                               onSuggestionDeleted: model.deleteSuggestion)

            SuggestionsSection(suggestions: model.localResults,
                               query: model.query,
                               onSuggestionSelected: model.onSuggestionSelected,
                               onSuggestionDeleted: model.deleteSuggestion)

        }
        .offset(x: 0, y: -28)
        .padding(.bottom, -20)
        .padding(.top, model.isPad ? 10 : 0)
        .modifier(HideScrollContentBackground())
        .background(Color(designSystemColor: .background))
        .modifier(CompactSectionSpacing())
        .modifier(DisableSelection())
        .modifier(DismissKeyboardOnSwipe())
        .environmentObject(model)
   }

}

private struct HistoryMessageView: View {

    var onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                onDismiss()
            } label: {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                    .foregroundColor(.primary)
            }
            .padding(.top, 4)
            .buttonStyle(.plain)

            VStack {
                Image(.remoteMessageAnnouncement)
                    .padding(8)

                Text(UserText.autocompleteHistoryWarningTitle)
                    .multilineTextAlignment(.center)
                    .daxHeadline()
                    .padding(2)

                Text(UserText.autocompleteHistoryWarningDescription)
                    .multilineTextAlignment(.center)
                    .daxFootnoteRegular()
                    .frame(maxWidth: 536)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }

}

private struct DismissKeyboardOnSwipe: ViewModifier {

    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content.scrollDismissesKeyboard(.immediately)
        } else {
            content
        }
    }

}

private struct DisableSelection: ViewModifier {

    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.selectionDisabled()
        } else {
            content
        }
    }

}

private struct CompactSectionSpacing: ViewModifier {

    func body(content: Content) -> some View {
        if #available(iOS 17, *) {
            content.listSectionSpacing(.compact)
        } else {
            content
        }
    }

}

private struct HideScrollContentBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16, *) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

private struct SuggestionsSection: View {

    @EnvironmentObject var autocompleteViewModel: AutocompleteViewModel

    let suggestions: [AutocompleteViewModel.SuggestionModel]
    let query: String?
    var onSuggestionSelected: (AutocompleteViewModel.SuggestionModel) -> Void
    var onSuggestionDeleted: (AutocompleteViewModel.SuggestionModel) -> Void

    let selectedColor = Color(designSystemColor: .accent)
    let unselectedColor = Color(designSystemColor: .surface)

    private struct Metrics {
        static let rowInsets = EdgeInsets(top: 10, leading: 10, bottom: 8, trailing: 14)
    }

    var body: some View {
        Section {
            ForEach(suggestions.indices, id: \.self) { index in
                 Button {
                     onSuggestionSelected(suggestions[index])
                 } label: {
                    SuggestionView(model: suggestions[index], query: query)
                 }
                 .listRowBackground(autocompleteViewModel.selection == suggestions[index] ? selectedColor : unselectedColor)
                 .listRowInsets(Metrics.rowInsets)
                 .listRowSeparatorTint(Color(designSystemColor: .lines), edges: [.bottom])
                 .modifier(SwipeDeleteHistoryModifier(suggestion: suggestions[index], onSuggestionDeleted: onSuggestionDeleted))
            }
        }
    }

}

private struct SwipeDeleteHistoryModifier: ViewModifier {

    let suggestion: AutocompleteViewModel.SuggestionModel
    var onSuggestionDeleted: (AutocompleteViewModel.SuggestionModel) -> Void

    func body(content: Content) -> some View {

        switch suggestion.suggestion {
        case .historyEntry:
            content.swipeActions {
                Button(role: .destructive) {
                    onSuggestionDeleted(suggestion)
                } label: {
                    Label {
                        Text("Delete")
                    } icon: {
                        Image(uiImage: DesignSystemImages.Glyphs.Size24.trash)
                    }
                }
            }

        default:
            content
        }

    }

}

private struct SuggestionView: View {

    @EnvironmentObject var autocompleteModel: AutocompleteViewModel

    let model: AutocompleteViewModel.SuggestionModel
    let query: String?

    var tapAheadImage: Image? {
        guard model.canShowTapAhead else { return nil }
        return Image(uiImage: autocompleteModel.isAddressBarAtBottom ?
                     DesignSystemImages.Glyphs.Size16.arrowCircleDownLeft : DesignSystemImages.Glyphs.Size16.arrowCircleUpLeft)
    }

    var body: some View {
        Group {

            switch model.suggestion {
            case .phrase(let phrase):
                SuggestionListItem(icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.findSearchSmall),
                                   title: phrase,
                                   query: query,
                                   indicator: tapAheadImage) {
                    autocompleteModel.onTapAhead(model)
                }.accessibilityIdentifier("Autocomplete.Suggestions.ListItem.SearchPhrase-\(phrase)")

            case .website(let url):
                SuggestionListItem(icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.globe),
                                   title: url.formattedForSuggestion())
                .accessibilityIdentifier("Autocomplete.Suggestions.ListItem.Website-\(url.formattedForSuggestion())")

            case .bookmark(let title, let url, let isFavorite, _) where isFavorite:
                SuggestionListItem(icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.bookmarkFavorite),
                                   title: title,
                                   subtitle: url.formattedForSuggestion())
                .accessibilityIdentifier("Autocomplete.Suggestions.ListItem.Favorite-\(url.formattedForSuggestion())")

            case .bookmark(let title, let url, _, _):
                SuggestionListItem(icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.bookmark),
                                   title: title,
                                   subtitle: url.formattedForSuggestion())
                .accessibilityIdentifier("Autocomplete.Suggestions.ListItem.Bookmark-\(url.formattedForSuggestion())")

            case .historyEntry(_, let url, _) where url.isDuckDuckGoSearch:
                SuggestionListItem(icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.history),
                                   title: url.searchQuery ?? "",
                                   subtitle: UserText.autocompleteSearchDuckDuckGo)
                .accessibilityIdentifier("Autocomplete.Suggestions.ListItem.SERPHistory-\(url.searchQuery ?? "")")

            case .historyEntry(let title, let url, _):
                SuggestionListItem(icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.history),
                                   title: title ?? "",
                                   subtitle: url.formattedForSuggestion())
                .accessibilityIdentifier("Autocomplete.Suggestions.ListItem.History-\(url.formattedForSuggestion())")

            case .openTab(title: let title, url: let url, _, _):
                SuggestionListItem(icon: Image(uiImage: DesignSystemImages.Glyphs.Size24.tabsMobile),
                                   title: title,
                                   subtitle: "\(UserText.autocompleteSwitchToTab) · \(url.formattedForSuggestion())")
                .accessibilityIdentifier("Autocomplete.Suggestions.ListItem.OpenTab-\(url.formattedForSuggestion())")

            case .internalPage, .unknown:
                FailedAssertionView("Unknown or unsupported suggestion type")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

private struct SuggestionListItem: View {

    @EnvironmentObject var autocompleteModel: AutocompleteViewModel

    let icon: Image
    let title: String
    let subtitle: String?
    let query: String?
    let indicator: Image?
    let onTapIndicator: (() -> Void)?

    init(icon: Image,
         title: String,
         subtitle: String? = nil,
         query: String? = nil,
         indicator: Image? = nil,
         onTapIndicator: ( () -> Void)? = nil) {

        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.query = query
        self.indicator = indicator
        self.onTapIndicator = onTapIndicator
    }

    var body: some View {
        HStack(spacing: 0) {
            icon
                .resizable()
                .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                .tintIfAvailable(Color(designSystemColor: .icons))

            VStack(alignment: .leading, spacing: Metrics.subtitleSpacing) {

                Group {
                    // Can't use dax modifiers because they are not typed for Text
                    if let query, title.hasPrefix(query) {
                        Text(query)
                            .font(Font(uiFont: UIFont.daxBodyRegular()))
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                        +
                        Text(title.dropping(prefix: query))
                            .font(Font(uiFont: UIFont.daxBodyBold()))
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                    } else {
                        Text(title)
                            .font(Font(uiFont: UIFont.daxBodyRegular()))
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                    }
                }
                .lineLimit(1)

                if let subtitle {
                    Text(subtitle)
                        .daxFootnoteRegular()
                        .foregroundColor(Color(designSystemColor: .textSecondary))
                        .lineLimit(1)
                }
            }
            .padding(.leading, Metrics.verticalSpacing)

            if indicator == nil {
                // No indicator means we want to preserve the room for icon,
                // so all the titles from other cells are aligned.
                Spacer(minLength: Metrics.trailingPadding)
            } else {
                Spacer()
            }

            if let indicator {
                indicator
                    .highPriorityGesture(TapGesture().onEnded {
                        onTapIndicator?()
                    })
                    .tintIfAvailable(Color.init(designSystemColor: .iconsSecondary))
                    .padding(.leading, Metrics.indicatorLeadingPadding)
            }
        }
    }

    private struct Metrics {
        static let iconSize: CGFloat = 24
        static let verticalSpacing: CGFloat = 10
        static let subtitleSpacing: CGFloat = 2
        static let trailingPadding: CGFloat = 20
        static let indicatorLeadingPadding: CGFloat = 4
    }

}

private extension URL {

    func formattedForSuggestion() -> String {
        let string = absoluteString
            .dropping(prefix: "https://")
            .dropping(prefix: "http://")
            .droppingWwwPrefix()
        return pathComponents.isEmpty ? string : string.dropping(suffix: "/")
    }

}
