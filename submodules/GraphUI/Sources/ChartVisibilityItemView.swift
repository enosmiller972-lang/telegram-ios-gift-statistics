//
//  ChartVisibilityItemCell.swift
//  GraphTest
//
//  Created by Andrei Salavei on 4/7/19.
//  Copyright © 2019 Andrei Salavei. All rights reserved.
//

import UIKit
import GraphCore

class ChartVisibilityItemView: UIView {
    static let textFont = UIFont.systemFont(ofSize: 14, weight: .medium)

    let checkButton: UIButton = UIButton(type: .system)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupView()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupView()
    }
    
    func setupView() {
        checkButton.frame = bounds
        checkButton.titleLabel?.font = ChartVisibilityItemView.textFont
        checkButton.layer.cornerRadius = 15
        checkButton.layer.masksToBounds = true
        checkButton.addTarget(self, action: #selector(didTapButton), for: .touchUpInside)
        let pressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(didRecognizedLongPress(recognizer:)))
        pressRecognizer.cancelsTouchesInView = true
        checkButton.addGestureRecognizer(pressRecognizer)
        addSubview(checkButton)
    }
    
    var tapClosure: (() -> Void)?
    var longTapClosure: (() -> Void)?

    private func updateStyle(animated: Bool) {
        guard let item = item else {
            return
        }
        UIView.perform(animated: animated, animations: {
            if self.isChecked {
                // Light series colors get a dark title.
                var white: CGFloat = 0.0
                var alpha: CGFloat = 0.0
                let isLight = self.giftStyle && item.color.getWhite(&white, alpha: &alpha) && white > 0.85
                self.checkButton.setTitleColor(isLight ? UIColor(white: 0.1, alpha: 0.85) : .white, for: .normal)
                self.checkButton.backgroundColor = item.color
                self.checkButton.layer.borderColor = nil
                self.checkButton.layer.borderWidth = 0
                self.checkButton.setTitle("✓ " + item.title, for: .normal)
            } else {
                self.checkButton.backgroundColor = .clear
                self.checkButton.layer.borderColor = item.color.cgColor
                self.checkButton.layer.borderWidth = 1
                self.checkButton.setTitleColor(item.color, for: .normal)
                self.checkButton.setTitle(item.title, for: .normal)
            }

        })
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        checkButton.frame = bounds
    }
    
    @objc private func didTapButton() {
        tapClosure?()
    }

    @objc private func didRecognizedLongPress(recognizer: UIGestureRecognizer) {
        if recognizer.state == .began {
            longTapClosure?()
        }
    }
    
    var giftStyle: Bool = false {
        didSet {
            if self.giftStyle != oldValue {
                self.updateStyle(animated: false)
            }
        }
    }
    
    var item: ChartVisibilityItem? = nil {
        didSet {
            updateStyle(animated: false)
        }
    }
    
    private(set) var isChecked: Bool = true
    func setChecked(isChecked: Bool, animated: Bool) {
        self.isChecked = isChecked
        updateStyle(animated: true)
    }
}
