public enum SessionCommand: Equatable, Sendable {
    case selectTool(Tool), undo, redo, clearAll, copy, save
}

public enum SessionKey: Equatable, Hashable, Sendable {
    case digit(Int), escape, delete, undo, redo, returnKey, copy, save
}

public func command(for key: SessionKey, mode: AppMode, isEditingText: Bool) -> SessionCommand? {
    guard !isEditingText, mode != .idle else { return nil }
    switch key {
    case .digit(let d): return Tool.forDigit(d).map(SessionCommand.selectTool)
    case .delete: return .clearAll
    case .undo: return .undo
    case .redo: return .redo
    case .returnKey, .copy: return mode == .capturing ? .copy : nil
    case .save: return mode == .capturing ? .save : nil
    case .escape: return nil
    }
}
