public enum SessionCommand: Equatable, Sendable {
    case selectTool(Tool), toggleTool, thinner, thicker, undo, redo, clearAll, copy, save
}

public enum SessionKey: Equatable, Hashable, Sendable {
    case digit(Int), tab, leftBracket, rightBracket, escape, delete, undo, redo, returnKey, copy, save
}

public func command(for key: SessionKey, mode: AppMode, isEditingText: Bool) -> SessionCommand? {
    guard !isEditingText, mode != .idle else { return nil }
    switch key {
    case .digit(let d): return Tool.forDigit(d, mode: mode).map(SessionCommand.selectTool)
    case .tab: return .toggleTool
    case .leftBracket: return .thinner
    case .rightBracket: return .thicker
    case .delete: return .clearAll
    case .undo: return .undo
    case .redo: return .redo
    case .returnKey, .copy: return mode == .capturing ? .copy : nil
    case .save: return mode == .capturing ? .save : nil
    case .escape: return nil
    }
}
