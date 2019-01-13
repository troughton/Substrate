//
//  ImGui.swift
//  InterdimensionalLlama
//
//  Created by Thomas Roughton on 12/11/16.
//
//

import Swift
import SwiftMath
import CDebugDrawTools
import Utilities
import SwiftFrameGraph

func scan<
    S : Sequence, U
    >(_ seq: S, _ initial: U, _ combine: (U, S.Iterator.Element) -> U) -> [U] {
    var result: [U] = []
    result.reserveCapacity(seq.underestimatedCount)
    var runningResult = initial
    for element in seq {
        runningResult = combine(runningResult, element)
        result.append(runningResult)
    }
    return result
}

func withArrayOfCStrings<R>(
    _ args: [String], _ body: ([UnsafePointer<CChar>?]) -> R
    ) -> R {
    let argsCounts = Array(args.map { $0.utf8.count + 1 })
    let argsOffsets = [ 0 ] + scan(argsCounts, 0, +)
    let argsBufferSize = argsOffsets.last!
    
    var argsBuffer: [UInt8] = []
    argsBuffer.reserveCapacity(argsBufferSize)
    for arg in args {
        argsBuffer.append(contentsOf: arg.utf8)
        argsBuffer.append(0)
    }
    
    return argsBuffer.withUnsafeMutableBufferPointer {
        (argsBuffer) in
        let ptr = UnsafeMutableRawPointer(argsBuffer.baseAddress!).bindMemory(
            to: CChar.self, capacity: argsBuffer.count)
        var cStrings: [UnsafeMutablePointer<CChar>?] = argsOffsets.map { ptr + $0 }
        cStrings[cStrings.count - 1] = nil
        return body(cStrings)
    }
}

public final class TextureLookup {
    private static var maxIndex : UInt32 = 1
    private static var labelsToIdentifiers = [String : UInt32]()
    private static var identifiersToTextures = [UInt32 : Texture]()
    
    public static func register<S : RawRepresentable>(_ texture: Texture, label: S) where S.RawValue == String {
        self.register(texture, label: label.rawValue)
    }
    
    public static func register(_ texture: Texture, label: String) {
        let index = self.transientTextureReference(label: label)
        self.identifiersToTextures[index] = texture
    }
    
    public static func transientTextureReference<S : RawRepresentable>(label: S) -> UInt32 where S.RawValue == String {
        return self.transientTextureReference(label: label.rawValue)
    }
    
    public static func transientTextureReference(label: String) -> UInt32 {
        if let index = self.labelsToIdentifiers[label] {
            return index
        } else {
            let index = self.maxIndex
            self.maxIndex += 1
            self.labelsToIdentifiers[label] = index
            return index
        }
    }
    
    public static func textureWithId(_ identifier: UInt32) -> Texture? {
        return self.identifiersToTextures[identifier]
    }
}


fileprivate extension Vector2f {
    
    init(_ imVec: ImVec2) {
        self = unsafeBitCast(imVec, to: Vector2f.self)
    }
    
    var imVec : ImVec2 {
        return unsafeBitCast(self, to: ImVec2.self)
    }
}

fileprivate extension Vector4f {
    init(_ imVec: ImVec4) {
        self = unsafeBitCast(imVec, to: Vector4f.self)
    }
    
    var imVec : ImVec4 {
        return unsafeBitCast(self, to: ImVec4.self)
    }
}


fileprivate extension RGBAColour {
    init(_ imVec: ImVec4) {
        self = unsafeBitCast(imVec, to: RGBAColour.self)
    }
    
    var imVec : ImVec4 {
        return unsafeBitCast(self, to: ImVec4.self)
    }
}

extension ImDrawData {
    public mutating func scaleClipRects(by factor: Vector2f) {
        ImDrawData_ScaleClipRects(&self, factor.imVec)
    }
    
    public mutating func deindexAllBuffers() {
        ImDrawData_DeIndexAllBuffers(&self)
    }
}

@_fixed_layout
public final class ImGui {
    
    public typealias IO = ImGuiIO
    public typealias Style = ImGuiStyle
    public typealias Font = UnsafeMutablePointer<ImFont>
    public typealias Storage = UnsafeMutablePointer<ImGuiStorage>
    
    @_fixed_layout
    public struct DrawList {
        private let imList : UnsafeMutablePointer<ImDrawList>
        
        init(_ imList: UnsafeMutablePointer<ImDrawList>) {
            self.imList = imList
        }
        
        public var vertexBufferSize : Int {
            return Int(imList.pointee.VtxBuffer.Size)
        }
        
        public subscript(vertex n: Int) -> ImDrawVert {
            get {
                return imList.pointee.VtxBuffer.Data[n]
            }
            set {
                imList.pointee.VtxBuffer.Data[n] = newValue
            }
        }
        
        public subscript(vertexPtr n: Int) -> UnsafeMutablePointer<ImDrawVert> {
            return imList.pointee.VtxBuffer.Data.advanced(by: n)
        }
        
        public var indexBufferSize : Int {
            return Int(self.imList.pointee.IdxBuffer.Size)
        }
        
        public subscript(index n: Int) -> ImDrawIdx {
            get {
                return self.imList.pointee.IdxBuffer.Data[n]
            }
            set {
                self.imList.pointee.IdxBuffer.Data[n] = newValue
            }
        }
        
        public subscript(indexPtr n: Int) -> UnsafeMutablePointer<ImDrawIdx> {
            return self.imList.pointee.IdxBuffer.Data.advanced(by: n)
        }
        
        public var commandSize : Int {
            return Int(self.imList.pointee.CmdBuffer.Size)
        }
        
        public subscript(command n: Int) -> ImDrawCmd {
            get {
                return self.imList.pointee.CmdBuffer.Data[n]
            }
            set {
                self.imList.pointee.CmdBuffer.Data[n] = newValue
            }
        }
        
        public func addText(_ text: String, position: Vector2f, colour: RGBAColour) {
            self.addText(text, position: position, colour: colour.packed)
        }
        
        public func addText(_ text: String, position: Vector2f, colour: UInt32) {
            text.withCString { text in
                self.addText(text, position: position, colour: colour)
            }
        }
        
        public func addText(_ text: UnsafePointer<CChar>, position: Vector2f, colour: UInt32) {
            ImDrawList_AddText(self.imList, position.imVec, colour, text, text + strlen(text))
        }
        
        public func clear() {
            ImDrawList_Clear(self.imList)
        }
        
        public func clearFreeMemory() {
            ImDrawList_ClearFreeMemory(self.imList)
        }
    }
    
    public struct WindowFlags : OptionSet {
    
        public let rawValue: ImGuiWindowFlags
        
        public init(rawValue: ImGuiWindowFlags) {
            self.rawValue = rawValue
        }
        
        /// Disable title-bar
        public static let noTitleBar                   = WindowFlags(rawValue: 1 << 0)
        /// Disable user resizing with the lower-right grip
        public static let noResize                     = WindowFlags(rawValue: 1 << 1)
        /// Disable user moving the window
        public static let noMove                       = WindowFlags(rawValue: 1 << 2)
        /// Disable scrollbars (window can still scroll with mouse or programatically)
        public static let noScrollbar                  = WindowFlags(rawValue: 1 << 3)
        /// Disable user vertically scrolling with mouse wheel
        public static let noScrollWithMouse            = WindowFlags(rawValue: 1 << 4)
        /// Disable user collapsing window by double-clicking on it
        public static let noCollapse                   = WindowFlags(rawValue: 1 << 5)
        /// Resize every window to its content every frame
        public static let alwaysAutoResize             = WindowFlags(rawValue: 1 << 6)
        /// Show borders around windows and items
        public static let showBorders                  = WindowFlags(rawValue: 1 << 7)
        /// Never load/save settings in .ini file
        public static let noSavedSettings              = WindowFlags(rawValue: 1 << 8)
        /// Disable catching mouse or keyboard inputs
        public static let noInputs                     = WindowFlags(rawValue: 1 << 9)
        /// Has a menu-bar
        public static let menuBar                      = WindowFlags(rawValue: 1 << 10)
        /// Allow horizontal scrollbar to appear (off by default). You may use SetNextWindowContentSize(ImVec2(width,0.0f)); prior to calling Begin() to specify width. Read code in imgui_demo in the "Horizontal Scrolling" section.
        public static let horizontalScrollbar          = WindowFlags(rawValue: 1 << 11)
        /// Disable taking focus when transitioning from hidden to visible state
        public static let noFocusOnAppearing           = WindowFlags(rawValue: 1 << 12)
        /// Disable bringing window to front when taking focus (e.g. clicking on it or programatically giving it focus)
        public static let noBringToFrontOnFocus        = WindowFlags(rawValue: 1 << 13)
        /// Always show vertical scrollbar (even if ContentSize.y < Size.y)
        public static let alwaysVerticalScrollbar      = WindowFlags(rawValue: 1 << 14)
        /// Always show horizontal scrollbar (even if ContentSize.x < Size.x)
        public static let alwaysHorizontalScrollbar    = WindowFlags(rawValue: 1 << 15)
        /// Ensure child windows without border uses style.WindowPadding (ignored by default for non-bordered child windows, because more convenient)
        public static let alwaysUseWindowPadding       = WindowFlags(rawValue: 1 << 16)
    }
    
    public struct TreeNodeFlags : OptionSet {
        
        public let rawValue: ImGuiTreeNodeFlags
        
        public init(rawValue: ImGuiTreeNodeFlags) {
            self.rawValue = rawValue
        }
        
        /// Draw as selected
        public static let selected             = TreeNodeFlags(rawValue: 1 << 0)
        /// Full colored frame (e.g. for CollapsingHeader)
        public static let framed               = TreeNodeFlags(rawValue: 1 << 1)
        /// Hit testing to allow subsequent widgets to overlap this one
        public static let allowItemOverlap     = TreeNodeFlags(rawValue: 1 << 2)
        /// Don't do a TreePush() when open (e.g. for CollapsingHeader) = no extra indent nor pushing on ID stack
        public static let noTreePushOnOpen     = TreeNodeFlags(rawValue: 1 << 3)
        /// Don't automatically and temporarily open node when Logging is active (by default logging will automatically open tree nodes)
        public static let noAutoOpenOnLog      = TreeNodeFlags(rawValue: 1 << 4)
        /// Default node to be open
        public static let defaultOpen          = TreeNodeFlags(rawValue: 1 << 5)
        /// Need double-click to open node
        public static let openOnDoubleClick    = TreeNodeFlags(rawValue: 1 << 6)
        /// Only open when clicking on the arrow part. If openOnDoubleClick is also set, single-click arrow or double-click all box to open.
        public static let openOnArrow          = TreeNodeFlags(rawValue: 1 << 7)
        /// No collapsing, no arrow (use as a convenience for leaf nodes).
        public static let leaf                 = TreeNodeFlags(rawValue: 1 << 8)
        /// Display a bullet instead of arrow
        public static let bullet               = TreeNodeFlags(rawValue: 1 << 9)
        /// Use FramePadding (even for an unframed text node) to vertically align text baseline to regular widget height. Equivalent to calling alignTextToFramePadding().
        public static let framePadding         = TreeNodeFlags(rawValue: 1 << 10)
        public static let collapsingHeader     = [TreeNodeFlags.framed, TreeNodeFlags.noAutoOpenOnLog]
    }
    
    
    /// Flags for ImGui.selectable()
    public struct SelectableFlags : OptionSet {
        public let rawValue: ImGuiSelectableFlags
        
        public init(rawValue: ImGuiSelectableFlags) {
            self.rawValue = rawValue
        }
        
        /// Clicking this don't close parent popup window
        public static let dontClosePopups    = SelectableFlags(rawValue: 1 << 0)
        /// Selectable frame can span all columns (text will still fit in current column)
        public static let spanAllColumns     = SelectableFlags(rawValue: 1 << 1)
        // Generate press events on double clicks too
        public static let allowDoubleClick   = SelectableFlags(rawValue: 1 << 2)
    }
    
    /// Flags for ImGui.beginCombo()
    public struct ComboFlags : OptionSet {
        public let rawValue: ImGuiComboFlags
        
        public init(rawValue: ImGuiComboFlags) {
            self.rawValue = rawValue
        }
        
        /// Align the popup toward the left by default
        public static let popupAlignLeft          = ComboFlags(rawValue: 1 << 0)
        /// Max ~4 items visible. Tip: If you want your combo popup to be a specific size you can use SetNextWindowSizeConstraints() prior to calling BeginCombo()
        public static let heightSmall             = ComboFlags(rawValue: 1 << 1)
        /// Max ~8 items visible (default)
        public static let heightRegular           = ComboFlags(rawValue: 1 << 2)
        /// Max ~20 items visible
        public static let heightLarge             = ComboFlags(rawValue: 1 << 3)
        /// As many fitting items as possible
        public static let heightLargest           = ComboFlags(rawValue: 1 << 4)
        /// Display on the preview box without the square arrow button
        public static let noArrowButton           = ComboFlags(rawValue: 1 << 5)
        /// Display only a square arrow button
        public static let noPreview               = ComboFlags(rawValue: 1 << 6)
    }
    
    /// Flags for ImGui.isWindowFocused()
    public struct FocusedFlags : OptionSet {
        public let rawValue: ImGuiFocusedFlags
        
        public init(rawValue: ImGuiFocusedFlags) {
            self.rawValue = rawValue
        }
        
        /// IsWindowFocused(): Return true if any children of the window is focused
        public static let childWindows                  = FocusedFlags(rawValue: 1 << 0)
        /// IsWindowFocused(): Test from root window (top most parent of the current hierarchy)
        public static let rootWindow                    = FocusedFlags(rawValue: 1 << 1)
        /// IsWindowFocused(): Return true if any window is focused
        public static let anyWindow                     = FocusedFlags(rawValue: 1 << 2)
        
        public static let rootAndChildWindows : FocusedFlags = [.rootWindow, .childWindows]
    };
    
    /// Flags for ImGui.isItemHovered(), ImGui.isWindowHovered()
    /// Note: If you are trying to check whether your mouse should be dispatched to imgui or to your app, you should use the 'io.WantCaptureMouse' boolean for that. Please read the FAQ!
    public struct HoveredFlags : OptionSet {
        public let rawValue: ImGuiHoveredFlags
        
        public init(rawValue: ImGuiHoveredFlags) {
            self.rawValue = rawValue
        }
        
         /// Return true if directly over the item/window, not obstructed by another window, not obstructed by an active popup or modal blocking inputs under them.
        public static let `default` : HoveredFlags      = []
        /// IsWindowHovered() only: Return true if any children of the window is hovered
        public static let childWindows                  = HoveredFlags(rawValue: 1 << 0)
        /// IsWindowHovered() only: Test from root window (top most parent of the current hierarchy)
        public static let rootWindow                    = HoveredFlags(rawValue: 1 << 1)
        /// IsWindowHovered() only: Return true if any window is hovered
        public static let anyWindow                     = HoveredFlags(rawValue: 1 << 2)
        /// Return true even if a popup window is normally blocking access to this item/window
        public static let allowWhenBlockedByPopup       = HoveredFlags(rawValue: 1 << 3)
        /// Return true even if a modal popup window is normally blocking access to this item/window. FIXME-TODO: Unavailable yet.
        public static let allowWhenBlockedByModal       = HoveredFlags(rawValue: 1 << 4)
        /// Return true even if an active item is blocking access to this item/window. Useful for Drag and Drop patterns.
        public static let allowWhenBlockedByActiveItem  = HoveredFlags(rawValue: 1 << 5)
        /// Return true even if the position is overlapped by another window
        public static let allowWhenOverlapped           = HoveredFlags(rawValue: 1 << 6)
        public static let rectOnly : HoveredFlags       = [.allowWhenBlockedByPopup, .allowWhenBlockedByActiveItem, .allowWhenOverlapped]
        public static let rootAndChildWindows : HoveredFlags = [.rootWindow, .childWindows]
    };
    
    /// Flags for ImGui.beginDragDropSource(), ImGui.acceptDragDropPayload()
    public struct DragDropFlags : OptionSet {
        public let rawValue: ImGuiDragDropFlags
        
        public init(rawValue: ImGuiDragDropFlags) {
            self.rawValue = rawValue
        }
        
        // MARK: BeginDragDropSource() flags
        
        /// By default, a successful call to BeginDragDropSource opens a tooltip so you can display a preview or description of the source contents. This flag disables this behavior.
        public static let sourceNoPreviewTooltip       = DragDropFlags(rawValue: 1 << 0)
        /// By default, when dragging we clear data so that IsItemHovered() will return true, to avoid subsequent user code submitting tooltips. This flag disables this behavior so you can still call IsItemHovered() on the source item.
        public static let sourceNoDisableHover         = DragDropFlags(rawValue: 1 << 1)
        /// Disable the behavior that allows to open tree nodes and collapsing header by holding over them while dragging a source item.
        public static let sourceNoHoldToOpenOthers     = DragDropFlags(rawValue: 1 << 2)
        /// Allow items such as Text(), Image() that have no unique identifier to be used as drag source, by manufacturing a temporary identifier based on their window-relative position. This is extremely unusual within the dear imgui ecosystem and so we made it explicit.
        public static let sourceAllowNullID            = DragDropFlags(rawValue: 1 << 3)
        /// External source (from outside of imgui), won't attempt to read current item/window info. Will always return true. Only one Extern source can be active simultaneously.
        public static let sourceExtern                 = DragDropFlags(rawValue: 1 << 4)
        
        // MARK: AcceptDragDropPayload() flags
        
        /// AcceptDragDropPayload() will returns true even before the mouse button is released. You can then call IsDelivery() to test if the payload needs to be delivered.
        public static let acceptBeforeDelivery         = DragDropFlags(rawValue: 1 << 10)
        /// Do not draw the default highlight rectangle when hovering over target.
        public static let acceptNoDrawDefaultRect      = DragDropFlags(rawValue: 1 << 11)
        /// For peeking ahead and inspecting the payload before delivery.
        public static let acceptPeekOnly : DragDropFlags = [.acceptBeforeDelivery, .acceptNoDrawDefaultRect]
    }
    
    public struct ColorEditFlags : OptionSet {
        public let rawValue: ImGuiColorEditFlags
    
        public init(rawValue: ImGuiColorEditFlags) {
            self.rawValue = rawValue
        }
        
        public static let noAlpha = ColorEditFlags(rawValue: 1 << 1)
        public static let noPicker = ColorEditFlags(rawValue: 1 << 2)
        public static let noOptions = ColorEditFlags(rawValue: 1 << 3)
        public static let noSmallPreview = ColorEditFlags(rawValue: 1 << 4)
        public static let noInputs = ColorEditFlags(rawValue: 1 << 5)
        public static let noTooltips = ColorEditFlags(rawValue: 1 << 6)
        public static let noLabel = ColorEditFlags(rawValue: 1 << 7)
        public static let noSidePreview = ColorEditFlags(rawValue: 1 << 8)
        public static let noDragDrop = ColorEditFlags(rawValue: 1 << 9)
        
        public static let alphaBar = ColorEditFlags(rawValue: 1 << 16)
        public static let alphaPreview = ColorEditFlags(rawValue: 1 << 17)
        public static let alphaPreviewHalf = ColorEditFlags(rawValue: 1 << 18)
        public static let hdr = ColorEditFlags(rawValue: 1 << 19)
        public static let rgb = ColorEditFlags(rawValue: 1 << 20)
        public static let hsv = ColorEditFlags(rawValue: 1 << 21)
        public static let hex = ColorEditFlags(rawValue: 1 << 22)
        public static let uint8 = ColorEditFlags(rawValue: 1 << 23)
        public static let float = ColorEditFlags(rawValue: 1 << 24)
        public static let pickerHueBar = ColorEditFlags(rawValue: 1 << 25)
        public static let pickerHueWheel = ColorEditFlags(rawValue: 1 << 26)
    }
    
    /// Condition for ImGui::SetWindow***(), SetNextWindow***(), SetNextTreeNode***() functions
    /// All those functions treat 0 as a shortcut to ImGuiCond_Always. From the point of view of the user use this as an enum (don't combine multiple values into flags).
    public enum Condition : ImGuiCond {
        /// Set the variable
        case always        = 1
        /// Set the variable once per runtime session (only the first call with succeed)
        case once          = 2
        /// Set the variable if the window has no saved data (if doesn't exist in the .ini file)
        case firstUseEver  = 4
        /// Set the variable if the window is appearing after being hidden/inactive (or the first time)
        case appearing     = 8
    }
    
    /// Standard Drag and Drop payload types. You can define you own payload types using 12-characters long strings. Types starting with '_' are defined by Dear ImGui.
    public enum DragDropPayload : String {
        /// Standard type for colors, without alpha. User code may use this type.
        case color3F = "_COL3F"
        /// Standard type for colors. User code may use this type.
        case color4F = "_COL4F"
    }
    
    public enum Cursor : Int32 {
        case none = -1
        case arrow = 0
        case textInput
        case move
        case resizeNS
        case resizeEW
        case resizeNESW
        case resizeNWSE
    }
    
    public static var io : UnsafeMutablePointer<IO> {
        return igGetIO()
    }

    public static var platformIO : UnsafeMutablePointer<ImGuiPlatformIO> {
        return igGetPlatformIO()
    }

    public static var style : UnsafeMutablePointer<Style> {
        return igGetStyle()
    }
    
    public static var drawData : UnsafeMutablePointer<ImDrawData>? {
        return igGetDrawData()
    }
    
    public static func newFrame()  {
        igNewFrame()
        self.beginImGuizmoFrame()
    }
    
    public static func updatePlatformWindows() {
        igUpdatePlatformWindows()
    }

    public static func render() {
        igRender()
    }
    
    public static func createContext(fontAtlas: UnsafeMutablePointer<ImFontAtlas>? = nil)  {
        let context = igCreateContext(fontAtlas)
        igSetCurrentContext(context)
    }
    
    public static func destroyContext() {
        igDestroyContext(igGetCurrentContext())
    }
    
    public static func showUserGuide()  {
        igShowUserGuide()
    }
    
    public static func showStyleEditor(ref: Style)  {
        var ref = ref
        igShowStyleEditor(&ref)
    }
    
    public static func showDemoWindow(opened: inout Bool)  {
        igShowDemoWindow(&opened)
    }
    
    public static func showMetricsWindow(opened: inout Bool)  {
        igShowMetricsWindow(&opened)
    }
    
    
    // Window
    public static func begin(name: String, pOpen: inout Bool, flags: WindowFlags) -> Bool {
        return igBegin(name, &pOpen, flags.rawValue)
    }
    
    public static func end()  {
        igEnd()
    }
    
    public static func beginChild(strId: String, size: Vector2f, border: Bool, extraFlags: WindowFlags) -> Bool {
        return igBeginChild(strId, size.imVec, border, extraFlags.rawValue)
    }
    
    public static func beginChild(id: ImGuiID, size: Vector2f, border: Bool, extraFlags: WindowFlags) -> Bool {
        return igBeginChildID(id, size.imVec, border, extraFlags.rawValue)
    }
    
    public static func endChild()  {
        igEndChild()
    }
    
    public static var contentRegionMax : Vector2f {
        return Vector2f(igGetContentRegionMax())
    }
    
    public static var contentRegionAvail : Vector2f  {
        return Vector2f(igGetContentRegionAvail())
    }
    
    public static var contentRegionAvailWidth : Float {
        return igGetContentRegionAvailWidth()
    }
    
    public static var windowContentRegionMin : Vector2f  {
        return Vector2f(igGetWindowContentRegionMin())
    }
    
    public static var windowContentRegionMax : Vector2f  {
        return Vector2f(igGetWindowContentRegionMax())
    }
    
    public static var windowContentRegionWidth : Float {
        return igGetWindowContentRegionWidth()
    }
    
    public static func windowDrawList() -> DrawList {
        return DrawList(igGetWindowDrawList())
    }
    
    public static var windowPos : Vector2f  {
        return Vector2f(igGetWindowPos())
    }
    
    public static var windowSize : Vector2f  {
        return Vector2f(igGetWindowSize())
    }
    
    public static var windowWidth : Float {
        return igGetWindowWidth()
    }
    
    public static var windowHeight : Float {
        return igGetWindowHeight()
    }
    
    public static var isWindowCollapsed : Bool {
        return igIsWindowCollapsed()
    }
    
    public static func setWindowFontScale(scale: Float)  {
        igSetWindowFontScale(scale)
    }
    
    
    public static func setNextWindowPos(pos: Vector2f, condition: Condition = .always, pivot: ImVec2)  {
        igSetNextWindowPos(pos.imVec, condition.rawValue, pivot)
    }
    
    public static func setNextWindowSize(size: Vector2f, condition: Condition = .always)  {
        igSetNextWindowSize(size.imVec, condition.rawValue)
    }
    
    public static func setNextWindowSizeConstraints(sizeMin: Vector2f, sizeMax: Vector2f, customCallback: @escaping ImGuiSizeCallback, customCallbackData: UnsafeMutableRawPointer)  {
        igSetNextWindowSizeConstraints(sizeMin.imVec, sizeMax.imVec, customCallback, customCallbackData)
    }
    
    public static func setNextWindowContentSize(size: Vector2f)  {
        igSetNextWindowContentSize(size.imVec)
    }
    
    public static func setNextWindowCollapsed(collapsed: Bool, condition: Condition = .always)  {
        igSetNextWindowCollapsed(collapsed, condition.rawValue)
    }
    
    public static func setNextWindowFocus()  {
        igSetNextWindowFocus()
    }
    
    public static func setWindowPos(pos: Vector2f, condition: Condition = .always)  {
        igSetWindowPosVec2(pos.imVec, condition.rawValue)
    }
    
    public static func setWindowSize(size: Vector2f, condition: Condition = .always)  {
        igSetWindowSizeVec2(size.imVec, condition.rawValue)
    }
    
    public static func setWindowCollapsed(collapsed: Bool, condition: Condition = .always)  {
        igSetWindowCollapsedBool(collapsed, condition.rawValue)
    }
    
    public static func setWindowFocus()  {
        igSetWindowFocus()
    }
    
    public static func setWindow(name: String, pos: Vector2f, condition: Condition = .always)  {
        igSetWindowPosStr(name, pos.imVec, condition.rawValue)
    }
    
    public static func setWindowSize(name: String, size: Vector2f, condition: Condition = .always)  {
        igSetWindowSizeStr(name, size.imVec, condition.rawValue)
    }
    
    public static func setWindowCollapsed(name: String, collapsed: Bool, condition: Condition = .always)  {
        igSetWindowCollapsedStr(name, collapsed, condition.rawValue)
    }
    
    public static func setWindowFocus2(name: String)  {
        igSetWindowFocusStr(name)
    }
    
    public static var scrollX : Float {
        get {
            return igGetScrollX()
        }
        set {
            igSetScrollX(newValue)
        }
    }
    
    public static var scrollY : Float {
        get {
            return igGetScrollY()
        }
        set {
            igSetScrollY(newValue)
        }
    }
    
    public static var scrollMaxX : Float {
        get {
            return igGetScrollMaxX()
        }
    }
    
    public static var scrollMaxY : Float {
        get {
            return igGetScrollMaxY()
        }
    }
    
    public static func setScrollHere(centerYRatio: Float)  {
        igSetScrollHereY(centerYRatio)
    }
    
    public static func setScrollFromPosY(posY: Float, centerYRatio: Float)  {
        igSetScrollFromPosY(posY, centerYRatio)
    }
    
    public static func setKeyboardFocusHere(offset: Int)  {
        igSetKeyboardFocusHere(Int32(offset))
    }
    
    public static func setStateStorage(tree: Storage)  {
        igSetStateStorage(tree)
    }
    
    public static func stateStorage() -> Storage {
        return igGetStateStorage()
    }
    
    
    // Parameters stacks (shared)
    public static func pushFont(font: Font)  {
        igPushFont(font)
    }
    
    public static func popFont()  {
        igPopFont()
    }
    
    public static func styleColorsDark() {
        igStyleColorsDark(nil)
    }
    
    public static func pushStyleColor(idx: ImGuiCol, col: Vector4f)  {
        igPushStyleColor(idx, col.imVec)
    }
    
    public static func popStyleColor(count: Int)  {
        igPopStyleColor(Int32(count))
    }
    
    public static func pushStyleVar(idx: ImGuiStyleVar, val: Float)  {
        igPushStyleVarFloat(idx, val)
    }
    
    public static func pushStyleVar(idx: ImGuiStyleVar, val: Vector2f)  {
        igPushStyleVarVec2(idx, val.imVec)
    }
    
    public static func popStyleVar(count: Int)  {
        igPopStyleVar(Int32(count))
    }
    
    public static var font : Font {
        return igGetFont()
    }
    
    public static var fontSize : Float {
        return igGetFontSize()
    }
    
    public static func fontTexUvWhitePixel() -> Vector2f  {
        return Vector2f(igGetFontTexUvWhitePixel())
    }
    
//    public static func colorU32(idx: ImGuiCol, alphaMul: Float) -> ImU32 {
//        return igGetColorU32(idx, alphaMul)
//    }
//    
//    public static func colorU32Vec(col: Vector4f) -> ImU32 {
//        var col = col.imVec
//        return igGetColorU32Vec(&col)
//    }
    
    
    // Parameters stacks (current window)
    public static func pushItemWidth(itemWidth: Float)  {
        igPushItemWidth(itemWidth)
    }
    
    public static func popItemWidth()  {
        igPopItemWidth()
    }
    
    public static func calcItemWidth() -> Float {
        return igCalcItemWidth()
    }
    
    public static func pushTextWrapPos(wrapPosX: Float)  {
        igPushTextWrapPos(wrapPosX)
    }
    
    public static func popTextWrapPos()  {
        igPopTextWrapPos()
    }
    
    public static func pushAllowKeyboardFocus(v: Bool)  {
        igPushAllowKeyboardFocus(v)
    }
    
    public static func popAllowKeyboardFocus()  {
        igPopAllowKeyboardFocus()
    }
    
    public static func pushButtonRepeat(repeat: Bool)  {
        igPushButtonRepeat(`repeat`)
    }
    
    public static func popButtonRepeat()  {
        igPopButtonRepeat()
    }
    
    
    // Layout
    public static func separator()  {
        igSeparator()
    }
    
    public static func sameLine(posX: Float = 0.0, spacingW: Float = -1.0)  {
        igSameLine(posX, spacingW)
    }
    
    public static func newLine()  {
        igNewLine()
    }
    
    public static func spacing()  {
        igSpacing()
    }
    
    public static func dummy(size: Vector2f)  {
        igDummy(size.imVec)
    }
    
    public static func indent(indentW: Float = 0.0)  {
        igIndent(indentW)
    }
    
    public static func unindent(indentW: Float = 0.0)  {
        igUnindent(indentW)
    }
    
    public static func beginGroup()  {
        igBeginGroup()
    }
    
    public static func endGroup()  {
        igEndGroup()
    }
    
    public static var cursorPos : Vector2f {
        get {
            return Vector2f(igGetCursorPos())
        }
        set {
            igSetCursorPos(newValue.imVec)
        }
    }
    
    public static var cursorPosX : Float {
        get {
            return igGetCursorPosX()
        }
        set {
            igSetCursorPosX(newValue)
        }
    }
    
    public static var cursorPosY : Float {
        get {
            return igGetCursorPosY()
        }
        set {
            igSetCursorPosY(newValue)
        }
    }
    
    
    public static var cursorStartPos : Vector2f {
        return Vector2f(igGetCursorStartPos())
    }
    
    public static var cursorScreenPos : Vector2f {
        get {
            return Vector2f(igGetCursorScreenPos())
        }
        set {
            igSetCursorScreenPos(newValue.imVec)
        }
    }
    
    public static func alignTextToFramePadding()  {
        igAlignTextToFramePadding()
    }
    
    public static var textLineHeight : Float {
        return igGetTextLineHeight()
    }
    
    public static var textLineHeightWithSpacing : Float {
        return igGetTextLineHeightWithSpacing()
    }
    
    public static var frameHeightWithSpacing : Float {
        return igGetFrameHeightWithSpacing()
    }
    
    // MARK: Drag and drop
    
    public static func beginDragDropSource(flags: DragDropFlags) -> Bool {
        return igBeginDragDropSource(flags.rawValue)
    }
    
    public static func setDragDropPayload<T>(_ value: T, type: DragDropPayload, condition: Condition) -> Bool {
        var value = value
        return withUnsafeBytes(of: &value) { igSetDragDropPayload(type.rawValue, $0.baseAddress, $0.count, condition.rawValue) }
    }
    
    public static func endDragDropSource() {
        return igEndDragDropSource()
    }
    
    public static func beginDragDropTarget() -> Bool {
        return igBeginDragDropTarget()
    }
    
    public static func acceptDragDropPayload(type: DragDropPayload, flags: DragDropFlags) -> UnsafePointer<ImGuiPayload>? {
        return igAcceptDragDropPayload(type.rawValue, flags.rawValue)
    }
    
    public static func endDragDroupTarget() {
        return igEndDragDropTarget()
    }
    
    // MARK: Columns
    public static func columns(count: Int, id: String, border: Bool)  {
        igColumns(Int32(count), id, border)
    }
    
    public static func nextColumn()  {
        igNextColumn()
    }
    
    public static var columnIndex : Int {
        return Int(igGetColumnIndex())
    }
    
    public static func columnOffset(columnIndex: Int) -> Float {
        return igGetColumnOffset(Int32(columnIndex))
    }
    
    public static func setColumnOffset(columnIndex: Int, offsetX: Float)  {
        igSetColumnOffset(Int32(columnIndex), offsetX)
    }
    
    public static func columnWidth(columnIndex: Int) -> Float {
        return igGetColumnWidth(Int32(columnIndex))
    }
    
    public static var columnsCount : Int {
        return Int(igGetColumnsCount())
    }
    
    
    // ID scopes
    // If you are creating widgets in a loop you most likely want to push a unique identifier so ImGui can differentiate them
    // You can also use "##extra" within your widget name to distinguish them from each others (see 'Programmer Guide')
    public static func pushID(_ strId: String)  {
        igPushIDStr(strId)
    }
    
    public static func pushIDStrRange(strBegin: String, strEnd: String)  {
        igPushIDRange(strBegin, strEnd)
    }
    
    public static func pushID(identifier: AnyObject)  {
        igPushIDPtr(Unmanaged.passUnretained(identifier).toOpaque())
    }
    
    public static func pushID(pointer: UnsafeRawPointer!)  {
        igPushIDPtr(pointer)
    }
    
    public static func pushID(_ id: Int)  {
        igPushIDInt(Int32(id))
    }
    
    public static func popID()  {
        igPopID()
    }
    
    public static func idStr(strId: String) -> ImGuiID {
        return igGetIDStr(strId)
    }
    
    public static func idStrRange(strBegin: String, strEnd: String) -> ImGuiID {
        return igGetIDRange(strBegin, strEnd)
    }
    
    public static func idPtr(ptrId: UnsafeRawPointer) -> ImGuiID {
        return igGetIDPtr(ptrId)
    }
    
    
    // Widgets
    public static func text(_ text: String)  {
        igText(text)
    }
    
    public static func textColored(text: String, col: Vector4f)  {
        igTextColored(col.imVec, text)
    }
    
    public static func textDisabled(text: String)  {
        igTextDisabled(text)
    }
    
    public static func textWrapped(text: String)  {
        igTextWrapped(text)
    }
    
    public static func textUnformatted(text: String, textEnd: String)  {
        igTextUnformatted(text, textEnd)
    }
    
    public static func labelText(label: String, text: String)  {
        igLabelText(label, text)
    }
    
    public static func bullet()  {
        igBullet()
    }
    
    public static func bulletText(text: String)  {
        igBulletText(text)
    }
    
    public static func button(label: String, size: Vector2f) -> Bool {
        return igButton(label, size.imVec)
    }
    
    public static func smallButton(label: String) -> Bool {
        return igSmallButton(label)
    }
    
    public static func invisibleButton(strId: String, size: Vector2f) -> Bool {
        return igInvisibleButton(strId, size.imVec)
    }
    
    public static func image(label: String, size: Vector2f, uv0: Vector2f = vec2(0), uv1: Vector2f = vec2(1), tintColour: Vector4f = vec4(1), borderColour: Vector4f = vec4(0))  {
        let identifier = TextureLookup.transientTextureReference(label: label)
        igImage(UnsafeMutableRawPointer(bitPattern: UInt(identifier)), size.imVec, uv0.imVec, uv1.imVec, tintColour.imVec, borderColour.imVec)
    }
    
    public static func image<S : RawRepresentable>(label: S, size: Vector2f, uv0: Vector2f = vec2(0), uv1: Vector2f = vec2(1), tintColour: Vector4f = vec4(1), borderColour: Vector4f = vec4(0)) where S.RawValue == String {
        let identifier = TextureLookup.transientTextureReference(label: label)
        igImage(UnsafeMutableRawPointer(bitPattern: UInt(identifier)), size.imVec, uv0.imVec, uv1.imVec, tintColour.imVec, borderColour.imVec)
    }
    
    public static func imageButton(label: String, size: Vector2f, uv0: Vector2f, uv1: Vector2f, framePadding: Int, backgroundColour: Vector4f, tintColour: Vector4f) -> Bool {
        let identifier = TextureLookup.transientTextureReference(label: label)
        return igImageButton(UnsafeMutableRawPointer(bitPattern: UInt(identifier)), size.imVec, uv0.imVec, uv1.imVec, Int32(framePadding), backgroundColour.imVec, tintColour.imVec)
    }
    
    public static func imageButton<S : RawRepresentable>(label: S, size: Vector2f, uv0: Vector2f, uv1: Vector2f, framePadding: Int, backgroundColour: Vector4f, tintColour: Vector4f) -> Bool where S.RawValue == String {
        let identifier = TextureLookup.transientTextureReference(label: label)
        return igImageButton(UnsafeMutableRawPointer(bitPattern: UInt(identifier)), size.imVec, uv0.imVec, uv1.imVec, Int32(framePadding), backgroundColour.imVec, tintColour.imVec)
    }
    
    public static func image(_ texture: Texture, size: Vector2f, uv0: Vector2f = vec2(0), uv1: Vector2f = vec2(1), tintColour: Vector4f = vec4(1), borderColour: Vector4f = vec4(0))  {
        igImage(UnsafeMutableRawPointer(bitPattern: UInt(exactly: texture.handle)!), size.imVec, uv0.imVec, uv1.imVec, tintColour.imVec, borderColour.imVec)
    }
    
    public static func imageButton(_ texture: Texture, size: Vector2f, uv0: Vector2f = vec2(0), uv1: Vector2f = vec2(1), framePadding: Int, backgroundColour: Vector4f, tintColour: Vector4f) -> Bool {
        return igImageButton(UnsafeMutableRawPointer(bitPattern: UInt(exactly: texture.handle)!), size.imVec, uv0.imVec, uv1.imVec, Int32(framePadding), backgroundColour.imVec, tintColour.imVec)
    }
    
    public static func checkbox(label: String, v: inout Bool) -> Bool {
        return igCheckbox(label, &v)
    }
    
    public static func checkboxFlags(label: String, flags: inout [UInt32], flagsValue: UInt) -> Bool {
        return igCheckboxFlags(label, &flags, UInt32(flagsValue))
    }
    
    public static func radioButton(label: String, active: Bool) -> Bool {
        return igRadioButtonBool(label, active)
    }
    
    public static func radioButton(label: String, v: inout Int, vButton: Int) -> Bool {
        var value = Int32(v)
        let result = igRadioButtonIntPtr(label, &value, Int32(vButton))
        v = Int(value)
        return result
    }
    
    public static func combo(label: String, currentItem: inout Int, items: [String], heightInItems: Int) -> Bool {
        return self.combo(label: label, currentItem: &currentItem, itemsSeparatedByZeros: items.joined(separator: "\0") + "\0", heightInItems: heightInItems)
    }

    public static func combo<T : Equatable>(label: String, currentItem: inout T, items: [T], itemToString: (T) -> String = { String(describing: $0) }, heightInItems: Int) -> Bool {
        var currentIndex = items.index(of: currentItem)!
        defer {
            currentItem = items[currentIndex]
        }
        return self.combo(label: label, currentItem: &currentIndex, itemsSeparatedByZeros: items.map(itemToString).joined(separator: "\0") + "\0", heightInItems: heightInItems)
    }
    
    public static func combo(label: String, currentItem: inout Int, itemsSeparatedByZeros: String, heightInItems: Int) -> Bool {
        var value = Int32(currentItem)
        
        let result = igComboStr(label, &value, itemsSeparatedByZeros, Int32(heightInItems))
        currentItem = Int(value)
        
        return result
    }
    
    //    public static func combo(label: String, currentItem: inout Int, itemsGetter: (data: UnsafeRawPointer, index: Int, outText: inout String) -> Bool, data: UnsafeRawPointer, itemsCount: Int, heightInItems: Int) -> Bool {
    //        return igCombo3(label, currentItem, Bool(*itemsGetter)
    //    }
    
    @discardableResult
    public static func colorButton(descriptionId: String, color: RGBAColour, flags: ColorEditFlags = [], size: Vector2f = Vector2f(0)) -> Bool {
        return igColorButton(descriptionId, color.imVec, flags.rawValue, size.imVec)
    }
    
    public static func colorEdit3(label: String, color: inout RGBColour, flags: ColorEditFlags) -> Bool {
        return withUnsafeMutableBytes(of: &color) { color in
            return igColorEdit3(label, color.baseAddress!.assumingMemoryBound(to: Float.self), flags.rawValue)
        }
    }
    
    public static func colorEdit4(label: String, color: inout RGBAColour, flags: ColorEditFlags) -> Bool {
        return withUnsafeMutableBytes(of: &color) { color in
            return igColorEdit4(label, color.baseAddress!.assumingMemoryBound(to: Float.self), flags.rawValue)
        }
    }
    
    public static func plotLines(label: String, values: [Float], valuesCount: Int, valuesOffset: Int, overlayText: String, scaleMin: Float, scaleMax: Float, graphSize: Vector2f, stride: Int)  {
        igPlotLines(label, values, Int32(valuesCount), Int32(valuesOffset), overlayText, scaleMin, scaleMax, graphSize.imVec, Int32(stride))
    }
    
    //        public static func plotLines(label: String, Float(*valuesGetter: )  {
    //            igPlotLines2(label, Float(*valuesGetter)
    //        }
    
    public static func plotHistogram(label: String, values: [Float], valuesCount: Int, valuesOffset: Int, overlayText: String, scaleMin: Float, scaleMax: Float, graphSize: Vector2f, stride: Int)  {
        igPlotHistogramFloatPtr(label, values, Int32(valuesCount), Int32(valuesOffset), overlayText, scaleMin, scaleMax, graphSize.imVec, Int32(stride))
    }
    
    //        public static func plotHistogram2(label: String, Float(*valuesGetter: )  {
    //        igPlotHistogram2(label, Float(*valuesGetter)
    //        }
    
    public static func progressBar(fraction: Float, sizeArg: Vector2f, overlay: String)  {
        igProgressBar(fraction, sizeArg.imVec, overlay)
    }
    
    // Widgets: Sliders (tip: ctrl+click on a slider to input text)
    @discardableResult
    public static func slider(label: String, v: inout Float, vMin: Float, vMax: Float, displayFormat: String = "%.3f", power: Float = 1.0) -> Bool {
        return igSliderFloat(label, &v, vMin, vMax, displayFormat, power)
    }
    
    public static func slider(label: String, v: inout Vector2f, vMin: Float, vMax: Float, displayFormat: String, power: Float) -> Bool {
        return withUnsafeMutableBytes(of: &v) { v in
            return igSliderFloat2(label, v.baseAddress!.assumingMemoryBound(to: Float.self), vMin, vMax, displayFormat, power)
        }
    }
    
    public static func slider(label: String, v: inout Vector3f, vMin: Float, vMax: Float, displayFormat: String, power: Float) -> Bool {
        return withUnsafeMutableBytes(of: &v) { v in
            return igSliderFloat3(label, v.baseAddress!.assumingMemoryBound(to: Float.self), vMin, vMax, displayFormat, power)
        }
    }
    
    public static func slider(label: String, v: inout Vector4f, vMin: Float, vMax: Float, displayFormat: String, power: Float) -> Bool {
        return withUnsafeMutableBytes(of: &v) { v in
            return igSliderFloat4(label, v.baseAddress!.assumingMemoryBound(to: Float.self), vMin, vMax, displayFormat, power)
        }
    }
    
    public static func slider(label: String, vRad: inout Float, vDegreesMin: Float, vDegreesMax: Float) -> Bool {
        return igSliderAngle(label, &vRad, vDegreesMin, vDegreesMax)
    }
    
    public static func slider(label: String, v: inout Int, vMin: Int, vMax: Int, displayFormat: String = "%.0f") -> Bool {
        var value = Int32(v)
        defer { v = Int(value) }
        return igSliderInt(label, &value, Int32(vMin), Int32(vMax), displayFormat)
    }
    
    public static func slider(label: String, v: inout [Int32], vMin: Int, vMax: Int, displayFormat: String) -> Bool {
        switch v.count {
        case 2:
            return igSliderInt2(label, &v, Int32(vMin), Int32(vMax), displayFormat)
        case 3:
            return igSliderInt3(label, &v, Int32(vMin), Int32(vMax), displayFormat)
        case 4:
            return igSliderInt4(label, &v, Int32(vMin), Int32(vMax), displayFormat)
        default:
            assertionFailure()
            return false
        }
    }
    
    public static func vSlider(label: String, size: Vector2f, v: inout [Float], vMin: Float, vMax: Float, displayFormat: String, power: Float) -> Bool {
        return igVSliderFloat(label, size.imVec, &v, vMin, vMax, displayFormat, power)
    }
    
    public static func vSlider(label: String, size: Vector2f, v: inout [Int32], vMin: Int, vMax: Int, displayFormat: String) -> Bool {
        return igVSliderInt(label, size.imVec, &v, Int32(vMin), Int32(vMax), displayFormat)
    }
    
    
    // Widgets: Drags (tip: ctrl+click on a drag box to input text)
    @discardableResult
    public static func dragFloat(label: String, v: inout Float, vSpeed: Float = 1.0, vMin: Float = 0.0, vMax: Float = 0.0, displayFormat: String = "%.3f", power: Float = 1.0) -> Bool {
        return igDragFloat(label, &v, vSpeed, vMin, vMax, displayFormat, power)
    }
    
    @discardableResult
    public static func dragFloat(label: String, v: inout Vector2f, vSpeed: Float = 1.0, vMin: Float = 0.0, vMax: Float = 0.0, displayFormat: String = "%.3f", power: Float = 1.0) -> Bool {
        var value = v
        defer { v = value }
        
        return withExtendedLifetime(value) {
            return igDragFloat2(label, escapingCastMutablePointer(to: &value), vSpeed, vMin, vMax, displayFormat, power)
        }
    }
    
    @discardableResult
    public static func dragFloat(label: String, v: inout Vector3f, vSpeed: Float = 1.0, vMin: Float = 0.0, vMax: Float = 0.0, displayFormat: String = "%.3f", power: Float = 1.0) -> Bool {
        var value = v
        defer { v = value }
        
        return withExtendedLifetime(value) {
            return igDragFloat3(label, escapingCastMutablePointer(to: &value), vSpeed, vMin, vMax, displayFormat, power)
        }
    }
    
    @discardableResult
    public static func dragFloat(label: String, v: inout Vector4f, vSpeed: Float = 1.0, vMin: Float = 0.0, vMax: Float = 0.0, displayFormat: String = "%.3f", power: Float = 1.0) -> Bool {
        var value = v
        defer { v = value }
        
        return withExtendedLifetime(value) {
            return igDragFloat4(label, escapingCastMutablePointer(to: &value), vSpeed, vMin, vMax, displayFormat, power)
        }
    }
    
    @discardableResult
    public static func dragFloatRange(label: String, vCurrentMin: inout Float, vCurrentMax: inout Float, vSpeed: Float = 1.0, vMin: Float = 0.0, vMax: Float = 0.0, displayFormatMin: String = "%.3f", displayFormatMax: String = "%.3f", power: Float = 1.0) -> Bool {
        return igDragFloatRange2(label, &vCurrentMin, &vCurrentMax, vSpeed, vMin, vMax, displayFormatMin, displayFormatMax, power)
    }
    
    @discardableResult
    public static func dragInt(label: String, v: inout Int, vSpeed: Float, vMin: Int, vMax: Int, displayFormat: String) -> Bool {
        var value = Int32(v)
        defer { v = Int(value) }
        return igDragInt(label, &value, vSpeed, Int32(vMin), Int32(vMax), displayFormat)
    }
    
    public static func dragInt(label: String, v: inout [Int], vSpeed: Float, vMin: Int, vMax: Int, displayFormat: String) -> Bool {
        var int32Vals = v.map { Int32($0) }
        
        let result : Bool
        switch v.count {
        case 1:
            return igDragInt(label, &int32Vals, vSpeed, Int32(vMin), Int32(vMax), displayFormat)
        case 2:
            result = igDragInt2(label, &int32Vals, vSpeed, Int32(vMin), Int32(vMax), displayFormat)
        case 3:
            result = igDragInt3(label, &int32Vals, vSpeed, Int32(vMin), Int32(vMax), displayFormat)
        case 4:
            result = igDragInt4(label, &int32Vals, vSpeed, Int32(vMin), Int32(vMax), displayFormat)
        default:
            assertionFailure()
            return false
        }
        
        for (i, val) in int32Vals.enumerated() {
            v[i] = Int(val)
        }
        
        return result
    }
    
    
    public static func dragIntRange(label: String, vCurrentMin: inout Int, vCurrentMax: inout Int, vSpeed: Float, vMin: Int, vMax: Int, displayFormat: String, displayFormatMax: String) -> Bool {
        var curMin = Int32(vCurrentMin)
        var curMax = Int32(vCurrentMax)
        defer { vCurrentMin = Int(curMin); vCurrentMax = Int(curMax) }
        return igDragIntRange2(label, &curMin, &curMax, vSpeed, Int32(vMin), Int32(vMax), displayFormat, displayFormatMax)
    }
    
    
    
    // Widgets: Input
//    public static func inputText(label: String, string: inout String, flags: ImGuiInputTextFlags = 0, callback: @escaping ImGuiTextEditCallback) -> Bool {
//        let bufferSize = 256
//        var buffer = [CChar](repeating: 0, count: bufferSize)
//        assert(string.getCString(&buffer, maxLength: bufferSize, encoding: .utf8))
//
//        return withExtendedLifetime(buffer, {
//            return igInputTextEx(label, &buffer, bufferSize, flags, callback, nil)
//        })
//    }
    
    public static func inputText(label: String, string: inout String, flags: ImGuiInputTextFlags = 0, callback: ImGuiInputTextCallback? = nil, userData: UnsafeMutableRawPointer? = nil) -> Bool {
        let bufferSize = 256
        var buffer = [CChar](repeating: 0, count: bufferSize)
        string.withCString { cString in
            buffer.withUnsafeMutableBytes { buffer in
                buffer.baseAddress?.copyMemory(from: string, byteCount: strlen(cString))
            }
        }
        
        let shouldUpdate = igInputText(label, &buffer, bufferSize, flags, callback, userData)
        
        if shouldUpdate {
            buffer.withUnsafeBufferPointer { buffer in
                let buffer = UnsafeRawPointer(buffer.baseAddress!).assumingMemoryBound(to: UInt8.self)
                string = String(cString: buffer)
            }
        }
        return shouldUpdate
    }
    
    public static func inputTextMultiline(label: String, buf: inout [CChar], bufSize: Int, size: Vector2f, flags: ImGuiInputTextFlags, callback: @escaping ImGuiInputTextCallback, userData: UnsafeMutableRawPointer?) -> Bool {
        return igInputTextMultiline(label, &buf, bufSize, size.imVec, flags, callback, userData)
    }
    
    public static func inputFloat(label: String, v: inout Float, step: Float, stepFast: Float, format: String = "%f", extraFlags: ImGuiInputTextFlags = 0) -> Bool {
        return igInputFloat(label, &v, step, stepFast, format, extraFlags)
    }
    
    public static func inputFloat(label: String, v: inout Vector2f, format: String = "%f", extraFlags: ImGuiInputTextFlags = 0) -> Bool {
        return withUnsafeMutableBytes(of: &v) { v in
            return igInputFloat2(label, v.baseAddress!.assumingMemoryBound(to: Float.self),format, extraFlags)
        }
    }
    
    public static func inputFloat(label: String, v: inout Vector3f, format: String = "%f", extraFlags: ImGuiInputTextFlags = 0) -> Bool {
        return withUnsafeMutableBytes(of: &v) { v in
            return igInputFloat3(label, v.baseAddress!.assumingMemoryBound(to: Float.self), format, extraFlags)
        }
    }
    
    public static func inputFloat(label: String, v: inout Vector4f, format: String = "%f", extraFlags: ImGuiInputTextFlags = 0) -> Bool {
        return withUnsafeMutableBytes(of: &v) { v in
            return igInputFloat4(label, v.baseAddress!.assumingMemoryBound(to: Float.self), format, extraFlags)
        }
    }
    
    public static func inputInt(label: String, v: inout Int, step: Int, stepFast: Int, extraFlags: ImGuiInputTextFlags) -> Bool {
        var value = Int32(v)
        defer { v = Int(value) }
        return igInputInt(label, &value, Int32(step), Int32(stepFast), extraFlags)
    }
    
    public static func inputInt(label: String, v: inout [Int32], extraFlags: ImGuiInputTextFlags) -> Bool {
        switch v.count {
        case 2:
            return igInputInt2(label, &v, extraFlags)
        case 3:
            return igInputInt3(label, &v, extraFlags)
        case 4:
            return igInputInt4(label, &v, extraFlags)
        default:
            assertionFailure()
            return false
        }
    }
    
    
    // Widgets: Trees
    public static func treeNode(label: String) -> Bool {
        return igTreeNodeStr(label)
    }
    
    public static func treeNode(strId: String, fmt: String) -> Bool {
        return igTreeNodeStrStr(strId, fmt)
    }
    
    public static func treeNode(label: String, flags: TreeNodeFlags) -> Bool {
        return igTreeNodeExStr(label, flags.rawValue)
    }
    
    public static func treeNode(strId: String, flags: TreeNodeFlags, fmt: String) -> Bool {
        return igTreeNodeExStrStr(strId, flags.rawValue, fmt)
    }

    public static func treeNode(identifier: Int, label: String, flags: TreeNodeFlags = []) -> Bool {
        return igTreeNodeExPtr(UnsafeRawPointer(bitPattern: identifier), flags.rawValue, label)
    }
    
    public static func treeNode(identifier: AnyObject, label: String, flags: TreeNodeFlags = []) -> Bool {
        return igTreeNodeExPtr(Unmanaged.passUnretained(identifier).toOpaque(), flags.rawValue, label)
    }
    
    public static func treePushStr(strId: String)  {
        igTreePushStr(strId)
    }
    
    public static func treePushPtr(ptrId: UnsafeRawPointer)  {
        igTreePushPtr(ptrId)
    }
    
    public static func treePop()  {
        igTreePop()
    }
    
    public static func treeAdvanceToLabelPos()  {
        igTreeAdvanceToLabelPos()
    }
    
    public static var treeNodeToLabelSpacing : Float {
        return igGetTreeNodeToLabelSpacing()
    }
    
    public static func setNextTreeNodeOpen(opened: Bool, condition: Condition = .always)  {
        igSetNextTreeNodeOpen(opened, condition.rawValue)
    }
    
    public static func collapsingHeader(label: String, flags: TreeNodeFlags = []) -> Bool {
        return igCollapsingHeader(label, flags.rawValue)
    }
    
    public static func collapsingHeader(label: String, pOpen: inout Bool, flags: TreeNodeFlags = []) -> Bool {
        return igCollapsingHeaderBoolPtr(label, &pOpen, flags.rawValue)
    }
    
    
    // Widgets: Selectable / Lists
    public static func selectable(label: String, selected: Bool = false, flags: SelectableFlags = [], size: Vector2f = vec2(0)) -> Bool {
        return igSelectable(label, selected, flags.rawValue, size.imVec)
    }
    
    public static func selectable(label: String, pSelected: inout Bool, flags: SelectableFlags = [], size: Vector2f = vec2(0)) -> Bool {
        return igSelectableBoolPtr(label, &pSelected, flags.rawValue, size.imVec)
    }
    
    public static func listBox(label: String, currentItem: inout Int, items: [String], itemsCount: Int, heightInItems: Int) -> Bool {
        var curItem = Int32(currentItem)
        defer { currentItem = Int(curItem) }
        
        return withArrayOfCStrings(items) { (array) -> Bool in
            var array = array
            return igListBoxStr_arr(label, &curItem, &array, Int32(itemsCount), Int32(heightInItems))
        }
    }
    
    //        public static func listBox2(label: String, currentItem: inout Int, Bool(*itemsGetter: ) -> Bool {
    //        return igListBox2(label, currentItem, Bool(*itemsGetter)
    //        }
    
    public static func listBoxHeader(label: String, size: Vector2f) -> Bool {
        return igListBoxHeaderVec2(label, size.imVec)
    }
    
    public static func listBoxHeader2(label: String, itemsCount: Int, heightInItems: Int) -> Bool {
        return igListBoxHeaderInt(label, Int32(itemsCount), Int32(heightInItems))
    }
    
    public static func listBoxFooter()  {
        igListBoxFooter()
    }
    
    
    // Widgets: Value() Helpers. Output single value in "name: value" format (tip: freely declare your own within the ImGui namespace!)
    public static func valueBool(prefix: String, b: Bool)  {
        igValueBool(prefix, b)
    }
    
    public static func valueInt(prefix: String, v: Int)  {
        igValueInt(prefix, Int32(v))
    }
    
    public static func valueUInt(prefix: String, v: UInt)  {
        igValueUint(prefix, UInt32(v))
    }
    
    public static func valueFloat(prefix: String, v: Float, FloatFormat: String)  {
        igValueFloat(prefix, v, FloatFormat)
    }
    
    // Tooltip
    public static func setTooltip(fmt: String)  {
        igSetTooltip(fmt)
    }
    
    
    public static func beginTooltip()  {
        igBeginTooltip()
    }
    
    public static func endTooltip()  {
        igEndTooltip()
    }
    
    // Widgets: Menus
    public static func beginMainMenuBar() -> Bool {
        return igBeginMainMenuBar()
    }
    
    public static func endMainMenuBar()  {
        igEndMainMenuBar()
    }
    
    public static func beginMenuBar() -> Bool {
        return igBeginMenuBar()
    }
    
    public static func endMenuBar()  {
        igEndMenuBar()
    }
    
    public static func beginMenu(label: String, enabled: Bool = true) -> Bool {
        return igBeginMenu(label, enabled)
    }
    
    public static func endMenu()  {
        igEndMenu()
    }
    
    public static func menuItem(label: String, shortcut: String = "", selected: Bool = false, enabled: Bool = true) -> Bool {
        return igMenuItemBool(label, shortcut, selected, enabled)
    }
    
    public static func menuItem(label: String, shortcut: String = "", pSelected: inout Bool, enabled: Bool = true) -> Bool {
        return igMenuItemBoolPtr(label, shortcut, &pSelected, enabled)
    }
    
    
    // Popup
    public static func openPopup(strId: String)  {
        igOpenPopup(strId)
    }
    
    public static func beginPopup(strId: String, flags: WindowFlags) -> Bool {
        return igBeginPopup(strId, flags.rawValue)
    }
    
    public static func beginPopupModal(name: String, pOpen: inout Bool, extraFlags: WindowFlags) -> Bool {
        return igBeginPopupModal(name, &pOpen, extraFlags.rawValue)
    }
    
    public static func beginPopupContextItem(strId: String, mouseButton: Int = 1) -> Bool {
        return igBeginPopupContextItem(strId, Int32(mouseButton))
    }
    
    public static func beginPopupContextWindow(strId: String, mouseButton: Int = 1, alsoOverItems: Bool) -> Bool {
        return igBeginPopupContextWindow(strId, Int32(mouseButton), alsoOverItems)
    }
    
    public static func beginPopupContextVoid(strId: String, mouseButton: Int = 1) -> Bool {
        return igBeginPopupContextVoid(strId, Int32(mouseButton))
    }
    
    public static func endPopup()  {
        igEndPopup()
    }
    
    public static func closeCurrentPopup()  {
        igCloseCurrentPopup()
    }
    
    
    // Logging: all text output from Interface is redirected to tty/file/clipboard. Tree nodes are automatically opened.
    public static func logToTTY(maxDepth: Int)  {
        igLogToTTY(Int32(maxDepth))
    }
    
    public static func logToFile(maxDepth: Int, filename: String)  {
        igLogToFile(Int32(maxDepth), filename)
    }
    
    public static func logToClipboard(maxDepth: Int)  {
        igLogToClipboard(Int32(maxDepth))
    }
    
    public static func logFinish()  {
        igLogFinish()
    }
    
    public static func logButtons()  {
        igLogButtons()
    }
    
    public static func logText(fmt: String)  {
        igLogText(fmt)
    }
    
    
    // Clipping
    public static func pushClipRect(clipRectMin: Vector2f, clipRectMax: Vector2f, IntersectWithCurrentClipRect: Bool)  {
        igPushClipRect(clipRectMin.imVec, clipRectMax.imVec, IntersectWithCurrentClipRect)
    }
    
    public static func popClipRect()  {
        igPopClipRect()
    }
    
    
    // Utilities
    public static var wantsCaptureMouse : Bool {
        return io.pointee.WantCaptureMouse
    }
    
    public static var wantsCaptureKeyboard : Bool {
        return io.pointee.WantCaptureKeyboard
    }
    
    public static func isItemHovered(flags: HoveredFlags) -> Bool {
        return igIsItemHovered(flags.rawValue)
    }
    
    public static func isItemActive() -> Bool {
        return igIsItemActive()
    }
    
    public static func isItemClicked(mouseButton: Int) -> Bool {
        return igIsItemClicked(Int32(mouseButton))
    }
    
    public static func isItemVisible() -> Bool {
        return igIsItemVisible()
    }
    
    public static func isAnyItemHovered() -> Bool {
        return igIsAnyItemHovered()
    }
    
    public static func isAnyItemActive() -> Bool {
        return igIsAnyItemActive()
    }
    
    public static var itemRectMin : Vector2f {
        return Vector2f(igGetItemRectMin())
    }
    
    public static var itemRectMax : Vector2f {
        return Vector2f(igGetItemRectMax())
    }
    
    public static var itemRectSize : Vector2f {
        return Vector2f(igGetItemRectSize())
    }
    
    public static func setItemAllowOverlap()  {
        igSetItemAllowOverlap()
    }
    
    public static func isWindowHovered(flags: HoveredFlags) -> Bool {
        return igIsWindowHovered(flags.rawValue)
    }
    
    public static func isWindowFocused(flags: FocusedFlags) -> Bool {
        return igIsWindowFocused(flags.rawValue)
    }
    
    public static func isRectVisible(itemSize: Vector2f) -> Bool {
        return igIsRectVisible(itemSize.imVec)
    }
    
    public static var time : Double {
        return igGetTime()
    }
    
    public static var frameCount : Int {
        return Int(igGetFrameCount())
    }
    
    public static func styleColorName(idx: ImGuiCol) -> String {
        return String(cString: igGetStyleColorName(idx))
    }
    
    public static func calcTextSize(text: String, textEnd: String, hideTextAfterDoubleHash: Bool, wrapWidth: Float) -> Vector2f {
        return Vector2f(igCalcTextSize(text, textEnd, hideTextAfterDoubleHash, wrapWidth))
    }
    
    public static func calcListClipping(itemsCount: Int, itemsHeight: Float) -> Range<Int>  {
        var outItemsDisplayStart = Int32(0)
        var outItemsDisplayEnd = Int32(0)
        igCalcListClipping(Int32(itemsCount), itemsHeight, &outItemsDisplayStart, &outItemsDisplayEnd)
        return Int(outItemsDisplayStart)..<Int(outItemsDisplayEnd + 1)
    }
    
    
    public static func beginChildFrame(id: ImGuiID, size: Vector2f, extraFlags: ImGuiWindowFlags) -> Bool {
        return igBeginChildFrame(id, size.imVec, extraFlags)
    }
    
    public static func endChildFrame()  {
        igEndChildFrame()
    }
    
    
    public static func colorConvertU32ToFloat4(_ in: ImU32) -> Vector4f {
        return Vector4f(igColorConvertU32ToFloat4(`in`))
    }
    
    public static func colorConvertFloat4ToU32(_ color: Vector4f) -> ImU32 {
        return igColorConvertFloat4ToU32(color.imVec)
    }
    
    public static func colorConvertRGBtoHSV(r: Float, g: Float, b: Float) -> (h: Float, s: Float, v: Float) {
        var h : Float = 0
        var s : Float = 0
        var v : Float = 0
        igColorConvertRGBtoHSV(r, g, b, &h, &s, &v)
        return (h, s, b)
    }
    
    public static func colorConvertHSVtoRGB(h: Float, s: Float, v: Float) -> (r: Float, g: Float, b: Float)  {
        var r : Float = 0
        var g : Float = 0
        var b : Float = 0
        igColorConvertHSVtoRGB(h, s, v, &r, &g, &b)
        return (r, g, b)
    }
    
    
    public static func keyIndex(key: ImGuiKey) -> Int {
        return Int(igGetKeyIndex(key))
    }
    
    public static func isKeyDown(keyIndex: Int) -> Bool {
        return igIsKeyDown(Int32(keyIndex))
    }
    
    public static func isKeyPressed(keyIndex: Int, repeat: Bool) -> Bool {
        return igIsKeyPressed(Int32(keyIndex), `repeat`)
    }
    
    public static func isKeyReleased(keyIndex: Int) -> Bool {
        return igIsKeyReleased(Int32(keyIndex))
    }
    
    public static func isMouseDown(button: Int) -> Bool {
        return igIsMouseDown(Int32(button))
    }
    
    public static func isMouseClicked(button: Int, repeat: Bool) -> Bool {
        return igIsMouseClicked(Int32(button), `repeat`)
    }
    
    public static func isMouseDoubleClicked(button: Int) -> Bool {
        return igIsMouseDoubleClicked(Int32(button))
    }
    
    public static func isMouseReleased(button: Int) -> Bool {
        return igIsMouseReleased(Int32(button))
    }
    
    public static func isMouseHoveringRect(rMin: Vector2f, rMax: Vector2f, clip: Bool) -> Bool {
        return igIsMouseHoveringRect(rMin.imVec, rMax.imVec, clip)
    }
    
    public static func isMouseDragging(button: Int, lockThreshold: Float = -1.0) -> Bool {
        return igIsMouseDragging(Int32(button), lockThreshold)
    }
    
    public static var mousePos : Vector2f  {
        return Vector2f(igGetMousePos())
    }
    
    public static var mousePosOnOpeningCurrentPopup : Vector2f {
        return Vector2f(igGetMousePosOnOpeningCurrentPopup())
    }
    
    public static func mouseDragDelta(button: Int, lockThreshold: Float) -> Vector2f {
        return Vector2f(igGetMouseDragDelta(Int32(button), lockThreshold))
    }
    
    public static func resetMouseDragDelta(button: Int)  {
        igResetMouseDragDelta(Int32(button))
    }
    
    public static var mouseCursor : Cursor {
        get {
            return Cursor(rawValue: igGetMouseCursor())!
        }
        set {
            igSetMouseCursor(newValue.rawValue)
        }
    }
    
    public static func captureKeyboardFromApp(capture: Bool)  {
        igCaptureKeyboardFromApp(capture)
    }
    
    public static func captureMouseFromApp(capture: Bool)  {
        igCaptureMouseFromApp(capture)
    }
    
    
    // Helpers public static functions to access public static functions poInters in ImGui::GetIO()
    public static func memAlloc(sz: Int) -> UnsafeMutableRawPointer {
        return igMemAlloc(sz)
    }
    
    public static func memFree(ptr: UnsafeMutableRawPointer)  {
        igMemFree(ptr)
    }
    
    public static var clipboardText : String {
        get {
            return String(cString: igGetClipboardText())
        }
        set {
            igSetClipboardText(newValue)
        }
    }
}

public extension ImGuiIO {
    public mutating func addUTF8InputCharacters(_ c: ContiguousArray<CChar>) {
        c.withUnsafeBufferPointer {
            ImGuiIO_AddInputCharactersUTF8(&self, $0.baseAddress)
        }
    }

    public mutating func addUTF8InputCharacters(_ c: UnsafePointer<CChar>) {
        ImGuiIO_AddInputCharactersUTF8(&self, c)
    }
}

public extension ImGui {
    public static func getFontTexDataAsAlpha8() -> (buffer: UnsafeMutablePointer<UInt8>, width: Int, height: Int, bytesPerPixel: Int) {
        var w : Int32 = 0
        var h : Int32 = 0
        var bpp : Int32 = 0
        var buffer : UnsafeMutablePointer<UInt8>? = nil
        ImFontAtlas_GetTexDataAsAlpha8(self.io.pointee.Fonts, &buffer, &w, &h, &bpp)
        return (buffer!, Int(w), Int(h), Int(bpp))
    }
    
    public static func setFontTexID(_ texId: UnsafeMutableRawPointer) {
        ImFontAtlas_SetTexID(self.io.pointee.Fonts, texId)
    }
    
    public static func addFontFromFileTTF(_ path: String, pixelSize: Float) {
        ImFontAtlas_AddFontFromFileTTF(self.io.pointee.Fonts, path, pixelSize, nil, nil)
    }
}

public extension ImGui {
        
    public final class RenderData {
        public let vertexBuffer : UnsafeMutableBufferPointer<ImDrawVert>
        public let indexBuffer : UnsafeMutableBufferPointer<ImDrawIdx>
        public let drawCommands : [DrawCommand]
        public let displayPosition : Vector2f
        public let displaySize : SwiftFrameGraph.Size
        public let clipScaleFactor : Float
        
        init(vertexBuffer: UnsafeMutableBufferPointer<ImDrawVert>, indexBuffer: UnsafeMutableBufferPointer<ImDrawIdx>, drawCommands : [DrawCommand], displayPosition: Vector2f, displaySize: SwiftFrameGraph.Size, clipScaleFactor: Float) {
            self.vertexBuffer = vertexBuffer
            self.indexBuffer = indexBuffer
            self.drawCommands = drawCommands
            self.displayPosition = displayPosition
            self.displaySize = displaySize
            self.clipScaleFactor = clipScaleFactor
        }
        
        deinit {
            self.vertexBuffer.baseAddress?.deallocate()
            self.indexBuffer.baseAddress?.deallocate()
        }
    }
    
    public struct DrawCommand {
        public var vertexBufferByteOffset = 0
        public var indexBufferByteOffset = 0
        public var subCommands = [ImDrawCmd]()
    }
    
    public static func renderData(drawData: UnsafeMutablePointer<ImDrawData>, clipScale: Float) -> RenderData {
        if clipScale != 1.0 {
            drawData.pointee.scaleClipRects(by: Vector2f(clipScale))
        }
        
        let vertexBufferCount = Int(drawData.pointee.TotalVtxCount)
        let indexBufferCount = Int(drawData.pointee.TotalIdxCount)
        
        let vertexBuffer = UnsafeMutableBufferPointer(start: UnsafeMutablePointer<ImDrawVert>.allocate(capacity: vertexBufferCount), count: vertexBufferCount)
        let indexBuffer = UnsafeMutableBufferPointer(start: UnsafeMutablePointer<ImDrawIdx>.allocate(capacity: indexBufferCount), count: indexBufferCount)
        
        var drawCommands : [DrawCommand] = []
        
        var vertexBufferOffset = 0
        var indexBufferOffset = 0
        
        var drawCommand = DrawCommand()
        
        // Render command lists
        for n in 0..<Int(drawData.pointee.CmdListsCount) {
            let cmdList = ImGui.DrawList(drawData.pointee.CmdLists[n]!)

            let vertexBufferSize = cmdList.vertexBufferSize
            let indexBufferSize = cmdList.indexBufferSize
            
            vertexBuffer.baseAddress!.advanced(by: vertexBufferOffset).initialize(from: cmdList[vertexPtr: 0], count: vertexBufferSize)
            indexBuffer.baseAddress!.advanced(by: indexBufferOffset).initialize(from: cmdList[indexPtr: 0], count: indexBufferSize)
            
            for cmdI in 0..<cmdList.commandSize {
                let pcmd = cmdList[command: cmdI]
                drawCommand.subCommands.append(pcmd)
            }
            
            drawCommands.append(drawCommand)
            
            vertexBufferOffset += vertexBufferSize
            indexBufferOffset += indexBufferSize
            
            drawCommand = DrawCommand()
            drawCommand.vertexBufferByteOffset = vertexBufferOffset * MemoryLayout<ImDrawVert>.size
            drawCommand.indexBufferByteOffset = indexBufferOffset * MemoryLayout<ImDrawIdx>.size
        }
        
        let displayPosition = Vector2f(drawData.pointee.DisplayPos)
        let displaySize = Size(width: Int(drawData.pointee.DisplaySize.x), height: Int(drawData.pointee.DisplaySize.y), depth: 1)
        
        return RenderData(vertexBuffer: vertexBuffer, indexBuffer: indexBuffer, drawCommands: drawCommands, displayPosition: displayPosition, displaySize: displaySize, clipScaleFactor: clipScale)
    }
}
