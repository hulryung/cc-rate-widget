import XCTest

final class JSONLTailerTests: XCTestCase {
    var tmpFile: URL!

    override func setUp() {
        super.setUp()
        tmpFile = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tailer-\(UUID().uuidString).jsonl")
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpFile)
        super.tearDown()
    }

    private func write(_ s: String) {
        try? s.write(to: tmpFile, atomically: true, encoding: .utf8)
    }
    private func append(_ s: String) {
        guard let h = try? FileHandle(forWritingTo: tmpFile) else { return }
        try? h.seekToEnd()
        h.write(s.data(using: .utf8)!)
        try? h.close()
    }

    func test_firstReadFromZero_returnsAllLines_andAdvancesOffset() throws {
        write("a\nb\nc\n")
        let tailer = JSONLTailer(url: tmpFile)
        let (lines, newOffset) = try tailer.tail(from: 0)
        XCTAssertEqual(lines, ["a", "b", "c"])
        XCTAssertEqual(newOffset, 6)
    }

    func test_incrementalRead_returnsOnlyNewLines() throws {
        write("a\nb\n")
        let tailer = JSONLTailer(url: tmpFile)
        let (_, off1) = try tailer.tail(from: 0)
        append("c\nd\n")
        let (lines, off2) = try tailer.tail(from: off1)
        XCTAssertEqual(lines, ["c", "d"])
        XCTAssertGreaterThan(off2, off1)
    }

    func test_trailingPartialLine_isNotEmitted_offsetStaysAtLineStart() throws {
        write("a\nb\npartia")
        let tailer = JSONLTailer(url: tmpFile)
        let (lines, off) = try tailer.tail(from: 0)
        XCTAssertEqual(lines, ["a", "b"])
        XCTAssertEqual(off, 4)
        append("l\n")
        let (lines2, _) = try tailer.tail(from: off)
        XCTAssertEqual(lines2, ["partial"])
    }

    func test_fileShrunk_resetsOffsetAndRereads() throws {
        write("a\nb\nc\n")
        let tailer = JSONLTailer(url: tmpFile)
        _ = try tailer.tail(from: 0)
        write("x\n")
        let (lines, _) = try tailer.tail(from: 999)   // cached offset > new size
        XCTAssertEqual(lines, ["x"])
    }
}
