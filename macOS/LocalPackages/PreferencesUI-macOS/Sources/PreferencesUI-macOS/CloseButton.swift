//
//  CloseButton.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import SwiftUI
import SwiftUIExtensions

public struct CloseButton: View {
    let icon: NSImage
    let size: CGFloat
    let backgroundColor: Color
    let backgroundColorOnHover: Color
    let action: () -> Void

    @State var isHovering = false

    public init(icon: NSImage, size: CGFloat, backgroundColor: Color = .clear, backgroundColorOnHover: Color? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.size = size
        self.backgroundColor = backgroundColor
        self.backgroundColorOnHover = backgroundColorOnHover ?? Color(.hover)
        self.action = action
        self.isHovering = isHovering
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isHovering ? backgroundColorOnHover : backgroundColor)
                    .frame(width: size, height: size)
                Image(nsImage: icon)
                    .foregroundColor(Color(.blackWhite80))
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            self.isHovering = isHovering
            if isHovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pointingHand.pop()
            }
        }
    }
}
