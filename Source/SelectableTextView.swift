//
//  SelectableTextView.swift
//  SelectableTextView
//
//  Created by Jeff Hurray on 2/4/17.
//  Copyright © 2017 jhurray. All rights reserved.
//

import Foundation
import UIKit

public enum TextAlignment {
    case left
    case center
    case right
}

// Goal: Add character wrapping
public enum LineBreakMode {
    case wordWrap
}

// Goal: Support head and middle truncation
public enum TruncationMode {
    case clipping
    case truncateTail
}

public protocol SelectableTextViewDelegate: class {
    
    /// Resolves conflict between multiple validates that return `true` from their `validate:` method
    //
    // i.e. PrefixTextValidator for `#` and `#my` will both return true for `#myCoolHashtag`,
    // but the actions they are registered for may differ
    //
    /// Default behavior is to choose the first validator in the composite validator's `validators` array
    func resolveValidationConflictsForSelectableTextView(textView: SelectableTextView, conflictingValidators: [TextSelectionValidator]) -> TextSelectionValidator
    
    /// Defaults to `false`
    func animateExpansionButtonForSelectableTextView(textView: SelectableTextView) -> Bool
    
    /// Defaults to `.truncateTail`
    func truncationModeForWordsThatDontFitForSelectableTextView(textView: SelectableTextView) -> TruncationMode
    
    /// Optional, Default empty implementation provideed
    func selectableTextViewContentHeightDidChange(textView: SelectableTextView, oldHeight: CGFloat, newHeight: CGFloat)
}

public extension SelectableTextViewDelegate {
    
    public func resolveValidationConflictsForSelectableTextView(textView: SelectableTextView, conflictingValidators: [TextSelectionValidator]) -> TextSelectionValidator {
        assert(!conflictingValidators.isEmpty, "Conflicting validators should never be empty")
        guard let validator = conflictingValidators.first else {
            return DefaultInvalidTextValidator()
        }
        return validator
    }
    
    public func truncationModeForWordsThatDontFitForSelectableTextView(textView: SelectableTextView) -> TruncationMode {
        return .truncateTail
    }
    
    public func animateExpansionButtonForSelectableTextView(textView: SelectableTextView) -> Bool {
        return false
    }
    
    public func selectableTextViewContentHeightDidChange(textView: SelectableTextView, oldHeight: CGFloat, newHeight: CGFloat) {}
}

public typealias TextSelectionAction = (String, TextSelectionValidator) -> Void

@IBDesignable
public final class SelectableTextView : UIView, TextViewLayoutDataSource, UICollectionViewDataSource, UICollectionViewDelegate {
    
    public var textAlignment: TextAlignment = .left {
        didSet {
            reloadData()
        }
    }
    public var lineBreakMode: LineBreakMode = .wordWrap {
        didSet {
            reloadData()
        }
    }
    public var truncationMode: TruncationMode = .clipping {
        didSet {
            reloadData()
        }
    }
    @IBInspectable public var numberOfLines: Int = 1 {
        didSet {
            if let _ = expansionButtonModel {
                expansionButtonModel!.expanded = (numberOfLines == expansionButtonModel!.expandedNumberOfLines)
            }
            reloadData()
        }
    }
    @IBInspectable public var text: String? {
        get {
            return _text
        }
        set(newValue) {
            _text = newValue
            if let text = _text {
                _attributedText = NSAttributedString(string: text, attributes: defaultAttributes)
            }
            reloadData()
        }
    }
    public var font: UIFont = .systemFont(ofSize: 17) {
        didSet {
           reloadData()
        }
    }
    @IBInspectable public var textColor: UIColor = .darkText {
        didSet {
            reloadData()
        }
    }
    public var attributedText: NSAttributedString? {
        get {
            return _attributedText
        }
        set(newValue) {
            _attributedText = newValue
            _text = newValue?.string
            reloadData()
        }
    }
    public var textContainerInsets: UIEdgeInsets = .zero {
        didSet {
            layout.invalidateLayout()
            setNeedsLayout()
        }
    }
    public var selectionAttributes: [String:AnyObject]? {
        didSet {
            reloadData()
        }
    }
    @IBInspectable public var lineSpacing: CGFloat = 0 {
        didSet {
            reloadData()
        }
    }
    public var isExpanded: Bool? {
        get {
            return expansionButtonModel?.expanded
        }
        set {
            if let expansionModel = expansionButtonModel, expansionModel.expanded != newValue {
                toggleExpansion(animated: false)
            }
        }
    }
    public var textContentSize: CGSize {
        return collectionView.contentSize
    }
    @IBInspectable public var isSelectionEnabled: Bool = true
    @IBInspectable public var isScrollEnabled: Bool = false
    public weak var delegate: SelectableTextViewDelegate?
    public weak var scrollDelegate: SelectableTextViewScrollDelegate?

    
    // MARK: Private
    fileprivate var _text: String?
    fileprivate var _attributedText: NSAttributedString?
    internal var textModels: [TextCellModel] = []
    internal var collectionView: UICollectionView! = nil
    fileprivate let layout: TextViewLayout = TextViewLayout()
    fileprivate var validatorIdentifierToActionMapping: [String: TextSelectionAction] = [:]
    fileprivate var validators: [TextSelectionValidator] = []
    fileprivate var expansionButtonModel: TextExpansionButtonModel? = nil
    fileprivate var ContentSizeObservationContext: UnsafeMutableRawPointer? = nil
    fileprivate var defaultAttributes: [String: Any] {
        let attributes = [
            NSForegroundColorAttributeName:textColor,
            NSFontAttributeName:font
            ] as [String : Any]
        return attributes
    }
    fileprivate var _selectionAttributes: [String: Any] {
        let defaultSelectionAttributes = [
            NSForegroundColorAttributeName: tintColor,
            NSFontAttributeName: UIFont.boldSystemFont(ofSize: font.pointSize + 2)
            ] as [String : Any]
        return selectionAttributes += defaultSelectionAttributes
    }
    fileprivate var defaultExpansionAttributes: [String: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let defaultSelectionAttributes = [
            NSForegroundColorAttributeName: tintColor,
            NSFontAttributeName: UIFont.boldSystemFont(ofSize: font.pointSize - 2),
            NSParagraphStyleAttributeName: paragraphStyle
            ] as [String : Any]
        return selectionAttributes += defaultSelectionAttributes
    }
    fileprivate struct LayoutHelper {
        static var layout: TextViewLayout = TextViewLayout()
        static var collectionView: UICollectionView = UICollectionView(frame: .zero, collectionViewLayout:layout)
        
        static func sizeThatFits(size: CGSize, dataSource: TextViewLayoutDataSource) -> CGSize {
            collectionView.frame = CGRect(x: 0, y: 0, width: size.width, height: .greatestFiniteMagnitude)
            layout.dataSource = dataSource
            layout.invalidateLayout()
            layout.prepare()
            let contentSize = layout.collectionViewContentSize
            return CGSize(width: size.width, height: min(contentSize.height, size.height))
        }
    }
    
    
    // MARK: Initializers
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    convenience init() {
        self.init(frame: .zero)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }
    
    fileprivate func commonInit() {
        layout.dataSource = self
        layout.onLayout = { [unowned self] in
            self.handleTruncationIfNecessary()
            self.setNeedsLayout()
        }
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.register(TextCell.self, forCellWithReuseIdentifier: TextCell.defaultIdentifier)
        collectionView.register(TextExpansionButtonCell.self, forCellWithReuseIdentifier: TextExpansionButtonCell.defaultIdentifier)
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.backgroundColor = .clear
        addSubview(collectionView)
        
        setupContentSizeObservation()
    }
    
    deinit {
        collectionView.removeObserver(self, forKeyPath: ContentSizeKeyPath)
    }
    
    // MARK: Overrides
    public override func layoutSubviews() {
        super.layoutSubviews()
        collectionView.frame = UIEdgeInsetsInsetRect(bounds, textContainerInsets)
    }
    
    public override func sizeThatFits(_ size: CGSize) -> CGSize {
        return LayoutHelper.sizeThatFits(size: size, dataSource: self)
    }
    
    // MARK: Public
    public func addExpansionButton(collapsedState: (text: String, lines: Int), expandedState: (text: String, lines: Int), attributes: [String: Any]? = nil) {
        assert(collapsedState.lines != 0)
        assert(expandedState.lines == 0 || collapsedState.lines < expandedState.lines)
        let textAttributes = attributes += defaultExpansionAttributes
        expansionButtonModel = TextExpansionButtonModel(expanded: true, // will be toggled to collapsed
                                                        expandedText: expandedState.text,
                                                        collapsedText: collapsedState.text,
                                                        expandedNumberOfLines: expandedState.lines,
                                                        collapsedNumberOfLines: collapsedState.lines,
                                                        attributes: textAttributes)
        toggleExpansion(animated: false)
    }
    
    public func removeExpansionButton(numberOfLines: Int = 1) {
        expansionButtonModel = nil
        self.numberOfLines = numberOfLines
        reloadData()
    }
    
    public func toggleExpansion(animated: Bool) {
        assert(expansionButtonModel != nil)
        guard let _ = expansionButtonModel else {
            return
        }
        expansionButtonModel!.expanded.toggle()
        numberOfLines = expansionButtonModel!.numberOfLines
        
        if animated {
            let layout = TextViewLayout()
            layout.dataSource = self
            collectionView.setCollectionViewLayout(layout, animated: true) { _ in
                self.reloadData()
            }
        }
        else {
            reloadData()
        }
    }
    
    public func registerValidator(validator: TextSelectionValidator!, textSelectionAction:@escaping TextSelectionAction = {_, _ in}) {
        let validatorHasNotBeenRegistered: Bool = validatorIdentifierToActionMapping[validator.identifier] == nil
        assert(validatorHasNotBeenRegistered, "Validator of type \(validator.typeString) with identifier \(validator.identifier) has already been registered")
        guard validatorHasNotBeenRegistered else {
            return
        }
        
        let actionIsValid: Bool = textSelectionAction != nil
        assert(actionIsValid, "Validator of type \(validator.typeString) with identifier \(validator.identifier) registered with nil 'textSelectionAction'")
        guard actionIsValid else {
            return
        }
        
        validatorIdentifierToActionMapping[validator.identifier] = textSelectionAction
        validators.append(validator)
        reloadData()
    }
    
    public func removeValidator(validator: TextSelectionValidator) {
        validatorIdentifierToActionMapping.removeValue(forKey: validator.identifier)
        validators = validators.filter { $0.identifier == validator.identifier }
    }
    
    public func framesOfWordsMatchingValidator(validator: TextSelectionValidator) -> [CGRect] {
        var matchingAttributes: [UICollectionViewLayoutAttributes] = []
        let numberOfCells = self.collectionView.numberOfItems(inSection: 0)
        for index in 0..<numberOfCells {
            if let word = textModels[index] as? Word,
                validator.validate(text: word.text),
                let attributes = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))
            {
                matchingAttributes.append(attributes)
            }
        }
        return matchingAttributes.map { $0.frame.translate(x: textContainerInsets.left, y: textContainerInsets.top) }
    }
    
    // MARK: Helpers
    fileprivate func reloadData() {
        let oldHeight = textContentSize.height
        accessibilityLabel = text
        buildTextModels()
        collectionView.reloadData()
        setNeedsLayout()
    }
    
    fileprivate func handleTruncationIfNecessary() {
        if let truncationContext = layout.truncationContext {
            let model = textModels[truncationContext.indexOfCellModelNeedingTruncation]
            guard var word = model as? Word else {
                assert(false, "Model for truncation should always be of type Word")
                return
            }
            if word.displayText != nil {
                word.displayText = truncationContext.transformedText
            }
            else {
                word.text = truncationContext.transformedText
            }
            textModels[truncationContext.indexOfCellModelNeedingTruncation] = word
        }
    }
    
    fileprivate func buildTextModels() {
        let factory = TextCellModelFactory()
        var models = factory.buildTextModels(attributedText: _attributedText)
        var textModels: [TextCellModel] = []
        for model in models {
            if var word = model as? Word {
                if let validator = validatorForModel(textModel: word) {
                    word = transformWord(word: word, appearance: validator)
                }
                 textModels.append(word)
            }
            else {
                 textModels.append(model)
            }
        }
        self.textModels = textModels
    }
    
    fileprivate func transformWord(word: Word, appearance: TextSelectionAppearance) -> Word {
        var word = word
        var attributes = _selectionAttributes
        if let extraAttributes = appearance.selectionAttributes {
            attributes = attributes += extraAttributes
        }
        word.attributes = attributes
        if let replacementText = appearance.replacementText {
            word.displayText = replacementText
        }
        word.highlightable = true
        return word
    }
    
    fileprivate func validatorForModel(textModel: TextCellModel) -> TextSelectionValidator? {
        var validValidators: [TextSelectionValidator] = []
        for validator in validators {
            if validator.validate(text: textModel.text) {
                validValidators.append(validator)
            }
        }
        var fulfillableValidator: TextSelectionValidator?
        switch validValidators.count {
        case 0:
            return nil
        case 1:
            return validValidators.first
        default:
            if let delegate = delegate {
                return delegate.resolveValidationConflictsForSelectableTextView(textView: self, conflictingValidators: validValidators as! [TextSelectionValidator])
            }
            else {
                return validValidators.first
            }
        }
    }
    
    fileprivate func performActionForSelectionOfModel(textModel: TextCellModel!, validator: TextSelectionValidator!) {
        if let action = validatorIdentifierToActionMapping[validator.identifier] {
            action(textModel.text, validator)
        }
    }
}


// MARK: UICollectionViewDataSource + UICollectionViewDelegate
public extension SelectableTextView {
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        guard let _ = expansionButtonModel else {
            return textModels.count
        }
        return textModels.count + 1
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        switch indexPath.item {
        case textModels.count:
            let cell: TextExpansionButtonCell = collectionView.dequeueReusableCell(withReuseIdentifier: TextExpansionButtonCell.defaultIdentifier, for: indexPath) as! TextExpansionButtonCell
            assert(expansionButtonModel != nil, "expansionButtonModel should not be nil if a cell at this index is being asked for")
            cell.model = expansionButtonModel
            cell.tintColor = tintColor
            cell.reloadData()
            return cell
        default:
            let cell: TextCell = collectionView.dequeueReusableCell(withReuseIdentifier: TextCell.defaultIdentifier, for: indexPath) as! TextCell
            cell.model = textModels[indexPath.item]
            if let context = layout.malformedTextCellContext,
                context.indicesOfMalformedCells.contains(indexPath.item),
                let truncationMode = delegate?.truncationModeForWordsThatDontFitForSelectableTextView(textView: self)
            {
                switch truncationMode {
                case .truncateTail:
                    cell.lineBreakMode = .byTruncatingTail
                    break
                case .clipping:
                    cell.lineBreakMode = .byClipping
                    break
                }
            }
            return cell
        }
        
    }
    
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        switch indexPath.item {
        case textModels.count:
            let animated = delegate != nil ? delegate!.animateExpansionButtonForSelectableTextView(textView: self) : false
            toggleExpansion(animated: animated)
            break
        default:
            guard isSelectionEnabled else {
                return
            }
            let textModel = textModels[indexPath.item]
            if let validator = validatorForModel(textModel: textModel) {
                performActionForSelectionOfModel(textModel: textModel, validator: validator)
            }
            break
        }
    }
    
    public func collectionView(_ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath) -> Bool {
        switch indexPath.item {
        case textModels.count:
            return true
        default:
            let textModel = textModels[indexPath.item]
            return textModel is Word
        }
    }
}


// MARK: TextViewLayoutDataSource
internal extension SelectableTextView {
    
    func lineSpacingForLayout(layout: TextViewLayout) -> CGFloat {
        return lineSpacing
    }
    
    func numberOfLinesForLayout(layout: TextViewLayout) -> Int {
        return numberOfLines
    }
    
    func numberOfTextModelsForLayout(layout: TextViewLayout) -> Int {
        return textModels.count
    }
    
    func truncationModeForLayout(layout: TextViewLayout) -> TruncationMode {
        return truncationMode
    }
    
    func textAlignmentForLayout(layout: TextViewLayout) -> TextAlignment {
        return textAlignment
    }
    
    func cellModelAtIndex(index:Int, layout: TextViewLayout) -> TextCellModel {
        return textModels[index]
    }
    
    func expansionButtonModel(layout: TextViewLayout) -> TextExpansionButtonModel? {
        return expansionButtonModel
    }
}

// MARK: KVO
let ContentSizeKeyPath = "contentSize"
fileprivate extension SelectableTextView {
    
    func setupContentSizeObservation() {
        collectionView.addObserver(self, forKeyPath: ContentSizeKeyPath, options: NSKeyValueObservingOptions.old.union(.new), context: &ContentSizeObservationContext)
    }
    
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == ContentSizeKeyPath && context == &ContentSizeObservationContext {
            if let change = change as? [NSKeyValueChangeKey: NSValue],
                let oldSize = change[NSKeyValueChangeKey.oldKey]?.cgSizeValue,
                let newSize = change[NSKeyValueChangeKey.newKey]?.cgSizeValue,
                oldSize.height != newSize.height
            {
                let additions = topTextInsets + bottomTextInsets
                delegate?.selectableTextViewContentHeightDidChange(textView: self, oldHeight: oldSize.height + additions, newHeight: newSize.height + additions)
            }
        }
    }
}
