import Foundation

struct JSONLTailer {
    let url: URL

    /// Reads complete lines starting at `offset`. Returns the lines (without trailing \n)
    /// and the new offset to persist. If the file is now smaller than `offset` (rotation /
    /// truncation), starts from 0.
    func tail(from offset: UInt64) throws -> (lines: [String], newOffset: UInt64) {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? UInt64) ?? 0
        var start = offset
        if start > size { start = 0 }
        if start == size { return ([], size) }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: start)
        let data = try handle.readToEnd() ?? Data()

        // Find last newline; everything after is a partial line we leave for next tick.
        guard let lastNewline = data.lastIndex(of: 0x0a) else {
            return ([], start)
        }
        let completeData = data.prefix(lastNewline + 1)
        let text = String(data: completeData, encoding: .utf8) ?? ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let newOffset = start + UInt64(completeData.count)
        return (lines, newOffset)
    }
}
