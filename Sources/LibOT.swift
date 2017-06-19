/* Text OT!
 * This is an OT implementation for text. It is a swift port of the standard
 * text OT implementation used by ShareJS.
 *
 * This type is composable but non-invertable. Its similar to ShareJS's old
 * text-composable type, but its not invertable. Its also very similar to the
 * text-tp2 implementation but it doesn't support tombstones or purging.
 *
 * Be aware there is a unicode incompatibility with the JS version of this lib:
 * the JS version currently counts UTF-16 surrogate pairs, not code points.
 * As a result some conversion will be required to ingest JS operations which
 * edit documents containing characters in the astral plane.
 *
 * Ops are lists of components which iterate over the document.
 * Components are either:
 *   .skip(n)    : Skip (keep) N characters in the original document
 *   .ins("str") : Insert "str" at the current position in the document
 *   .del(n)     : Delete N characters at the current position in the document
 *
 * Eg: [.skip(3), .ins('hi'), .skip(5), .del(8)]
 *
 * Character position are counted in unicode code points, as they are well
 * defined across multiple languages and multiple versions of unicode. Also
 * using unicode code points means its impossible to make a document contain
 * invalid unicode.
 *
 * The operation does not have to skip the last characters in the document.
 *
 * There is an implementation of apply() which edits and returns a string
 * directly. Be aware that this implementation is slow for large strings. You
 * will get better performance using a high performance rope implementation.
 */

public enum TextOpComponent {
    case skip(UInt)
    case ins(String)
    case del(UInt)
    
    func count() -> UInt { // TODO: Is this used in contexts other than isNoOp?
        switch self {
        case let .skip(n): return n
        case let .ins(str): return UInt(str.unicodeScalars.count)
        case let .del(n): return n
        }
    }
    func isNoop() -> Bool { return self.count() == 0 }
    
    var precount: UInt {
        switch self {
        case let .skip(n): return n
        case .ins(_): return 0
        case let .del(n): return n
        }
    }
    
    var postcount: UInt {
        switch self {
        case let .skip(n): return n
        case let .ins(str): return UInt(str.unicodeScalars.count)
        case .del(_): return 0
        }
    }
    
    func slice(offset: UInt, len: UInt) -> TextOpComponent {
        switch self {
        case .skip(_): return .skip(len)
        case let .ins(str):
            // This is pretty inefficient.
            let uniScale = str.unicodeScalars
            let start = uniScale.index(
                uniScale.startIndex, offsetBy: Int(offset))
            let end = uniScale.index(
                start, offsetBy: Int(len))
            return .ins(String(str.unicodeScalars[start ..< end]))

        case .del(_): return .del(len)
        }
    }
}

extension TextOpComponent: Equatable {
    public static func ==(lhs: TextOpComponent, rhs: TextOpComponent) -> Bool {
        switch (lhs, rhs) {
        case let (.skip(a), .skip(b)): return a == b
        case let (.ins(a), .ins(b)): return a == b
        case let (.del(a), .del(b)): return a == b
        case (.skip, _), (.ins, _), (.del, _): return false
        }
    }
}

extension TextOpComponent: CustomStringConvertible {
    public var description: String {
        switch self {
        case let .skip(s): return "(skip \(s))"
        case let .ins(str): return "(ins '\(str)')"
        case let .del(n): return "(del \(n))"
        }
    }
}

public typealias TextOp = [TextOpComponent]

func append(op: inout TextOp, c: TextOpComponent) {
    if c.isNoop() { return }
    
    else if let last = op.popLast() {
        // Modify the element in-place if the type matches
        switch (last, c) {
        case let (.skip(a), .skip(b)):
            op.append(TextOpComponent.skip(a + b))
        case let (.ins(a), .ins(b)):
            op.append(TextOpComponent.ins(a + b))
        case let (.del(a), .del(b)):
            op.append(TextOpComponent.del(a + b))
        default:
            op.append(last); op.append(c)
        }
        
    } else {
        op.append(c)
    }
}

func trimOp(op: inout TextOp) {
    if let last = op.last, case .skip(_) = last {
        op.removeLast()
    }
}

public func apply(doc: String, op: TextOp) -> String {
    var result = String()
    
    // Text operations count characters in unicode scalars.
    var view = doc.unicodeScalars
    
    for c in op {
        switch c {
        case let .skip(len):
            let nextIndex = view.index(view.startIndex, offsetBy: Int(len))
            result.append(String(view.prefix(upTo: nextIndex)))
            view = view.suffix(from: nextIndex)
            
        case let .ins(str):
            result.append(str)
            
        case let .del(len):
            let nextIndex = view.index(view.startIndex, offsetBy: Int(len))
            view = view.suffix(from: nextIndex)
        }
    }
    
    result.append(String(view))
    return result
}

enum Context {
    case pre
    case post
}

func componentLen(_ c: TextOpComponent, context: Context) -> UInt {
    switch context {
    case .pre: return c.precount
    case .post: return c.postcount
    }
}

func makeTake(_ op: TextOp, context: Context) -> ((UInt) -> TextOpComponent) {
    // TODO: This will allocate a closure. Probably faster to use a cursor
    // struct instead.
    var idx = 0
    var offset: UInt = 0
    
    return { num in
        if idx == op.count { return .skip(UInt(num)) }
        
        let c = op[idx]
        let clen = componentLen(c, context: context)
        if clen == 0 {
            // The component is invisible in the specified context.
            // TODO: This case is might not be needed?
            assert(offset == 0)
            idx += 1
            return c
        } else if clen - offset <= num {
            // We can take the rest of the component.
            let result = c.slice(offset: offset, len: clen - offset)
            idx += 1
            offset = 0
            return result
        } else {
            // Take num length from the component.
            let result = c.slice(offset: offset, len: num)
            offset += num
            return result
        }
    }
}

func opValid(_ op: TextOp) -> Bool {
    // TODO.
    return true
}


public func transform(_ op: TextOp, _ other: TextOp, isLeft: Bool) -> TextOp {
    assert(opValid(op) && opValid(other))
    
    var result: TextOp = []
    let take = makeTake(op, context: .pre)
    
    for c in other {
        switch c {
        case let .skip(skip): // Skip. Copy input -> output.
            var len = skip
            while len > 0 {
                let chunk = take(len)
                append(op: &result, c: chunk)
                len -= chunk.postcount
            }
            
        case .ins(_):
            // The left's insert should go first in the output.
            if isLeft { append(op: &result, c: take(0)) }
            
            // Add a skip for the other op's insert.
            append(op: &result, c: .skip(c.postcount))
            
        case let .del(num):
            var len = num
            while len > 0 {
                let chunk = take(len)
                len -= chunk.precount
                
                // Discard all chunks except for inserts.
                if case .skip(_) = chunk {
                    append(op: &result, c: chunk)
                }
            }
        }
    }
    
    while true {
        // Copy rest of a across.
        let chunk = take(UInt.max)
        if case .skip(UInt.max) = chunk { break }
        append(op: &result, c: chunk)
    }
    
    trimOp(op: &result)
    assert(opValid(result))
    return result
}

public func compose(_ a: TextOp, _ b: TextOp) -> TextOp {
    assert(opValid(a) && opValid(b))
    
    var result: TextOp = []
    
    let take = makeTake(a, context: .post)
    
    for c in b {
        switch c {
        case let .skip(skip):
            var len = skip
            while len > 0 {
                let chunk = take(len)
                append(op: &result, c: chunk)
                len -= chunk.postcount
            }
            
        case .ins(_):
            append(op: &result, c: c)
            
        case let .del(num):
            var len = num
            while len > 0 {
                let chunk = take(len)
                len -= chunk.postcount
            }
        }
    }
    
    while true {
        // Copy rest of a across.
        let chunk = take(UInt.max)
        if case .skip(UInt.max) = chunk { break }
        append(op: &result, c: chunk)
    }
    
    trimOp(op: &result)
    assert(opValid(result))
    return result
}
