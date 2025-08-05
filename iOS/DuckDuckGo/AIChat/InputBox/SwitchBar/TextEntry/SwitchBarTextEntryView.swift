//
//  SwitchBarTextEntryView.swift
//  DuckDuckGo
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

import UIKit
import SwiftUI
import Combine
import DesignResourcesKitIcons

class SwitchBarTextEntryView: UIView {

    private enum Constants {
        static let maxHeight: CGFloat = 120
        static let minHeight: CGFloat = 44
        static let fontSize: CGFloat = 16

        // Text container insets
        static let textTopInset: CGFloat = 12
        static let textBottomInset: CGFloat = 12
        static let textHorizontalInset: CGFloat = 12

        // Placeholder positioning
        static let placeholderTopOffset: CGFloat = 12
        static let placeholderHorizontalOffset: CGFloat = 16
    }

    private let handler: SwitchBarHandling

    private let textView = SwitchBarTextView()
    private let placeholderLabel = UILabel()
    private var buttonsView = SwitchBarButtonsView()
    private var currentButtonState: SwitchBarButtonState {
        get { buttonsView.buttonState }
        set { buttonsView.buttonState = newValue }
    }

    private var currentMode: TextEntryMode {
        handler.currentToggleState
    }
    private var cancellables = Set<AnyCancellable>()

    private var heightConstraint: NSLayoutConstraint?

    var hasBeenTouched = false
    var isURL: Bool {
        // TODO some kind of text length check?
        URL(string: textView.text)?.navigationalScheme != nil
    }

    var isExpandable: Bool = false {
        didSet {
            updateTextViewHeight()
        }
    }

    // MARK: - Initialization
    init(handler: SwitchBarHandling) {
        self.handler = handler
        super.init(frame: .zero)

        setupView()
        setupSubscriptions()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        textView.font = UIFont.systemFont(ofSize: Constants.fontSize)
        textView.backgroundColor = UIColor.clear
        textView.tintColor = UIColor(designSystemColor: .accent)
        textView.textColor = UIColor(designSystemColor: .textPrimary)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.delegate = self
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false

        placeholderLabel.font = UIFont.systemFont(ofSize: Constants.fontSize)
        placeholderLabel.textColor = UIColor(designSystemColor: .textSecondary)

        // Truncate text in case it exceeds single line
        placeholderLabel.numberOfLines = 1

        setupButtonsView()

        addSubview(textView)
        addSubview(placeholderLabel)
        addSubview(buttonsView)

        buttonsView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        heightConstraint = heightAnchor.constraint(equalToConstant: Constants.minHeight)
        heightConstraint?.isActive = true

        setupConstraints()

        updateButtonState()
        updateForCurrentMode()
        updateTextViewHeight()

        textView.onTouchesBeganHandler = self.onTextViewTouchesBegan
    }

    // MARK: - Setup Methods

    private func onTextViewTouchesBegan() {
        textView.onTouchesBeganHandler = nil
        hasBeenTouched = true
        updateTextViewHeight()
    }

    private func setupButtonsView() {
        buttonsView.onClearTapped = { [weak self] in
            self?.handler.clearText()
        }
    }

    private func setupConstraints() {

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: Constants.placeholderTopOffset),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: Constants.placeholderHorizontalOffset),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -Constants.placeholderHorizontalOffset),

            buttonsView.centerYAnchor.constraint(equalTo: placeholderLabel.centerYAnchor),
            buttonsView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    // MARK: - UI Updates

    private func updateForCurrentMode() {
        switch currentMode {
        case .search:
            placeholderLabel.text = UserText.searchInputFieldPlaceholderSearchWeb
            textView.keyboardType = .webSearch
            textView.returnKeyType = .search
            textView.autocapitalizationType = .none
            textView.autocorrectionType = .no
            textView.spellCheckingType = .no
        case .aiChat:
            placeholderLabel.text = UserText.searchInputFieldPlaceholderDuckAI
            textView.keyboardType = .default
            textView.returnKeyType = .go
            textView.autocapitalizationType = .sentences
            textView.autocorrectionType = .default
            textView.spellCheckingType = .default
        }

        updatePlaceholderVisibility()
        updateButtonState()
        updateTextViewHeight()
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }

    private func updateButtonState() {
        let hasText = !textView.text.isEmpty
        let newButtonState: SwitchBarButtonState

        if hasText {
            newButtonState = .clearOnly
        } else {
            newButtonState = .noButtons
        }

        if newButtonState != currentButtonState {
            currentButtonState = newButtonState
            adjustTextViewContentInset()
        }
    }

    private func adjustTextViewContentInset() {
        let buttonsIntersectionWidth = textView.frame.intersection(buttonsView.frame).width

        // Use default inset or the amount of how buttons interset with the view + required spacing
        let rightInset = currentButtonState.showsClearButton ? buttonsIntersectionWidth : Constants.textHorizontalInset

        textView.textContainerInset = UIEdgeInsets(
            top: Constants.textTopInset,
            left: Constants.textHorizontalInset,
            bottom: Constants.textBottomInset,
            right: rightInset
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        adjustTextViewContentInset()
    }

    private func updateTextViewHeight() {

        let size = textView.systemLayoutSizeFitting(CGSize(width: textView.frame.width, height: CGFloat.greatestFiniteMagnitude))
        let contentExceedsMaxHeight = size.height > Constants.maxHeight

        // Reset defaults
        textView.textContainer.lineBreakMode = .byWordWrapping

        if !hasBeenTouched && isURL { // https://app.asana.com/1/137249556945/project/392891325557410/task/1210835160047733?focus=true
            heightConstraint?.constant = Constants.minHeight
            textView.isScrollEnabled = false
            textView.showsVerticalScrollIndicator = false
            textView.textContainer.lineBreakMode = .byTruncatingTail
        } else if isExpandable {
            let newHeight = max(Constants.minHeight, min(Constants.maxHeight, size.height))

            heightConstraint?.constant = newHeight

            textView.isScrollEnabled = contentExceedsMaxHeight
            textView.showsVerticalScrollIndicator = contentExceedsMaxHeight
        } else {
            heightConstraint?.constant = Constants.minHeight
            textView.isScrollEnabled = true
            textView.showsVerticalScrollIndicator = true
            return
        }

        if contentExceedsMaxHeight {
            let range: NSRange
            if textView.selectedRange.length > 0 && isExpandable {
                range = NSRange(location: textView.text.count, length: 0)
            } else {
                range = NSRange(location: 0, length: 0)
            }
            textView.scrollRangeToVisible(range)
        }
    }

    private func setupSubscriptions() {
        handler.toggleStatePublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateForCurrentMode()
            }
            .store(in: &cancellables)

        handler.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self = self else { return }

                if self.textView.text != text {
                    self.textView.text = text
                    self.updatePlaceholderVisibility()
                    self.updateButtonState()
                    self.updateTextViewHeight()
                }
            }
            .store(in: &cancellables)
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        return textView.becomeFirstResponder()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        return textView.resignFirstResponder()
    }

    func selectAllText() {
        textView.selectAll(nil)
    }
}

extension SwitchBarTextEntryView: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        updatePlaceholderVisibility()
        updateButtonState()
        updateTextViewHeight()
        handler.updateCurrentText(textView.text ?? "")
        handler.markUserInteraction()

        textView.reloadInputViews()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            /// https://app.asana.com/1/137249556945/project/1204167627774280/task/1210629837418046?focus=true
            let currentText = textView.text ?? ""
            if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                handler.submitText(currentText)
            }
        }
        return true
    }
}
