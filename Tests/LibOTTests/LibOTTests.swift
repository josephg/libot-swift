import XCTest
@testable import LibOT

class LibOTTests: XCTestCase {
    func checkApply(_ doc: String, _ op: TextOp, expect: String) {
        let actual = apply(doc: doc, op: op)
        XCTAssertEqual(expect, actual, "Applied '\(doc)' + \(op) -> '\(actual)'")
    }
    
    func checkCompose(op1: TextOp, op2: TextOp, expect: TextOp) {
        let actual = compose(op1, op2)
        XCTAssertEqual(expect, actual, "Composed \(op1) + \(op2) -> \(actual)")
    }
    
    func checkTransform(isLeft: Bool, _ op1: TextOp, _ op2: TextOp, expect: TextOp) {
        let actual = transform(op1, op2, isLeft: isLeft)
        XCTAssertEqual(expect, actual, "Trasformed \(op1) x \(op2) (left=\(isLeft)) -> \(actual)")
    }
    
    func checkTransformBoth(_ op1: TextOp, _ op2: TextOp, expect: TextOp) {
        checkTransform(isLeft: true, op1, op2, expect: expect)
        checkTransform(isLeft: false, op1, op2, expect: expect)
    }
    
    // Tests hand ported from C libot implementation.
    func testSanity() {
        checkApply("", [.ins("hi there")], expect: "hi there")
        checkCompose(
            op1: [.skip(1), .ins("hi")],
            op2: [.ins("yo")],
            expect: [.ins("yo"), .skip(1), .ins("hi")]
        )
        checkTransformBoth([.skip(1), .ins("hi")], [.ins("yo")], expect: [.skip(3), .ins("hi")])
    }
    
    func testApplySimple() {
        checkApply("ABCDE", [.skip(2), .ins("xx"), .skip(1), .del(1)], expect: "ABxxCE")
    }
    
    func testLHInserts() {
        checkTransform(isLeft: true,
                       [.skip(100), .ins("abc")],
                       [.skip(100), .ins("def")],
                       expect: [.skip(100), .ins("abc")])
        
        checkTransform(isLeft: false,
                       [.skip(100), .ins("abc")],
                       [.skip(100), .ins("def")],
                       expect: [.skip(103), .ins("abc")])
    }
    
    
    static var allTests = [
        ("testSanity", testSanity),
        ("testApplySimple", testApplySimple),
        ("testLHInserts", testLHInserts),
    ]
}
