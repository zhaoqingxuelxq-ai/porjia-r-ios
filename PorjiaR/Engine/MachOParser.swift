import Foundation

/// 纯 Swift Mach-O / FAT 解析器（标准库，无外部依赖）。
/// 对齐 breaker.py 的解析能力：thin/FAT、符号表、段映射、vm→file 偏移换算。
struct MachOParser {

    struct Segment {
        var name: String
        var vmaddr: UInt64
        var vmsize: UInt64
        var fileoff: UInt64
        var filesize: UInt64
    }

    struct Symbol {
        var name: String
        var value: UInt64       // vmaddr
        var fileoff: UInt64?    // 换算后的文件偏移
    }

    struct Slice {
        var label: String
        var cputype: UInt32
        var is64: Bool
        var segments: [Segment]
        var symbols: [Symbol]
        var base: Int           // 该 slice 在整个文件里的起始偏移
    }

    // MARK: - 字节读取（小端 / 大端安全）

    private static func u32(_ d: Data, _ off: Int, big: Bool = false) -> UInt32? {
        guard off >= 0, off + 4 <= d.count else { return nil }
        let b = [UInt8](d[off..<(off + 4)])
        if big {
            return (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
        }
        return (UInt32(b[3]) << 24) | (UInt32(b[2]) << 16) | (UInt32(b[1]) << 8) | UInt32(b[0])
    }

    private static func u64(_ d: Data, _ off: Int, big: Bool = false) -> UInt64? {
        guard off >= 0, off + 8 <= d.count else { return nil }
        let b = [UInt8](d[off..<(off + 8)])
        var v: UInt64 = 0
        if big {
            for i in 0..<8 { v = (v << 8) | UInt64(b[i]) }
        } else {
            for i in (0..<8).reversed() { v = (v << 8) | UInt64(b[i]) }
        }
        return v
    }

    // MARK: - 入口

    /// data 可以是 thin Mach-O、FAT，或是 IPA(zip) —— zip 时自动取最大的 Mach-O 条目。
    static func parse(_ data: Data, ipaName: inout String?) -> [Slice] {
        var payload = data
        if isZip(data) {
            if let (name, inner) = largestMachOInZip(data) {
                ipaName = name
                payload = inner
            }
        }
        let magic = [UInt8](payload.prefix(4))
        if magic == [0xca, 0xfe, 0xba, 0xbe] || magic == [0xbe, 0xba, 0xfe, 0xca] {
            return parseFat(payload)
        }
        if let s = parseThin(payload, base: 0, label: "thin") { return [s] }
        return []
    }

    private static func isZip(_ d: Data) -> Bool {
        let m = [UInt8](d.prefix(4))
        return m == [0x50, 0x4b, 0x03, 0x04]
    }

    /// 从 zip central directory 里找最大的、名字像主程序的可执行 Mach-O。
    /// 用系统 Compression 框架 inflate；这里只做定位，真正解析交给 parseThin。
    private static func largestMachOInZip(_ d: Data) -> (String, Data)? {
        // 找 EOCD (0x06054b50)，从尾部倒查
        var eocd: Int? = nil
        let maxBack = min(d.count, 1 << 20)
        for i in stride(from: d.count - 22, through: max(0, d.count - maxBack), by: -1) {
            if u32(d, i) == 0x06054b50 { eocd = i; break }
        }
        guard let e = eocd, let n = u16(d, e + 10), let cdOffI = u32(d, e + 16) else { return nil }
        var p = Int(cdOffI)
        var best: (String, Int, UInt32)? = nil  // name, compressedSize, method
        for _ in 0..<Int(n) {
            guard u32(d, p) == 0x02014b50 else { break }
            guard let method = u16(d, p + 10),
                  let csize = u32(d, p + 20),
                  let usize = u32(d, p + 24),
                  let nameLen = u16(d, p + 28),
                  let extraLen = u16(d, p + 30),
                  let commentLen = u16(d, p + 32),
                  let lho = u32(d, p + 42) else { break }
            guard p + 46 + Int(nameLen) <= d.count else { break }
            let name = String(data: d[p + 46..<(p + 46 + Int(nameLen))], encoding: .utf8) ?? ""
            let skip = name.contains("/Frameworks/") || name.hasSuffix(".dylib")
            if !skip, usize > 1_000_000, (best == nil || Int(usize) > best!.1) {
                best = (name, Int(usize), UInt32(method))
            }
            p += 46 + Int(nameLen) + Int(extraLen) + Int(commentLen)
        }
        guard let b = best else { return nil }
        // 读 local header 拿数据起点
        guard let lho = findLocalHeaderOffset(d, name: b.0) else { return nil }
        guard u32(d, lho) == 0x04034b50,
              let lnLen = u16(d, lho + 26), let exLen = u16(d, lho + 28) else { return nil }
        let dataStart = lho + 30 + Int(lnLen) + Int(exLen)
        let slice = d[dataStart..<min(d.count, dataStart + Int(u32(d, lho + 18) ?? 0))]
        let inflated: Data
        if b.2 == 0 {
            inflated = Data(slice)
        } else {
            guard let inf = Inflate.decompress(Data(slice), expected: b.1) else { return nil }
            inflated = inf
        }
        return (b.0, inflated)
    }

    private static func findLocalHeaderOffset(_ d: Data, name: String) -> Int? {
        var eocd: Int? = nil
        for i in stride(from: d.count - 22, through: max(0, d.count - (1 << 20)), by: -1) {
            if u32(d, i) == 0x06054b50 { eocd = i; break }
        }
        guard let e = eocd, let n = u16(d, e + 10), let cdOffI = u32(d, e + 16) else { return nil }
        var p = Int(cdOffI)
        for _ in 0..<Int(n) {
            guard u32(d, p) == 0x02014b50 else { break }
            guard let nameLen = u16(d, p + 28), let extraLen = u16(d, p + 30),
                  let commentLen = u16(d, p + 32), let lho = u32(d, p + 42) else { break }
            let nm = String(data: d[p + 46..<(p + 46 + Int(nameLen))], encoding: .utf8) ?? ""
            if nm == name { return Int(lho) }
            p += 46 + Int(nameLen) + Int(extraLen) + Int(commentLen)
        }
        return nil
    }

    private static func u16(_ d: Data, _ off: Int, big: Bool = false) -> UInt16? {
        guard off >= 0, off + 2 <= d.count else { return nil }
        let b = [UInt8](d[off..<(off + 2)])
        return big ? (UInt16(b[0]) << 8) | UInt16(b[1]) : (UInt16(b[1]) << 8) | UInt16(b[0])
    }

    private static func parseFat(_ d: Data) -> [Slice] {
        let magic = [UInt8](d.prefix(4))
        let big = magic == [0xca, 0xfe, 0xba, 0xbe]
        guard let n = u32(d, 4, big: big) else { return [] }
        var out: [Slice] = []
        let count = min(Int(n), 32)
        for i in 0..<count {
            let o = 8 + i * 20
            guard let ct = u32(d, o, big: big),
                  let so = u32(d, o + 8, big: big),
                  let sz = u32(d, o + 12, big: big) else { continue }
            let start = Int(so), size = Int(sz)
            guard start >= 0, start + size <= d.count else { continue }
            if let s = parseThin(d[start..<(start + size)], base: start, label: "cpu\(ct)", cpu: ct) {
                out.append(s)
            }
        }
        return out
    }

    private static func parseThin(_ d: Data, base: Int, label: String, cpu: UInt32? = nil) -> Slice? {
        let m = [UInt8](d.prefix(4))
        let is64: Bool
        if m == [0xcf, 0xfa, 0xed, 0xfe] { is64 = true }
        else if m == [0xce, 0xfa, 0xed, 0xfe] { is64 = false }
        else { return nil }
        guard let ncmds = u32(d, 16) else { return nil }
        let cputype = cpu ?? (u32(d, 4) ?? 0)
        var segs: [Segment] = []
        var syms: [Symbol] = []

        var off = is64 ? 32 : 28
        for _ in 0..<Int(ncmds) {
            guard let cmd = u32(d, off), let sz = u32(d, off + 4), sz >= 8 else { break }
            let cs = Int(sz)
            if cmd == 0x19 || cmd == 0x1 { // LC_SEGMENT_64 / LC_SEGMENT
                if let seg = parseSegment(d, off, is64: is64) { segs.append(seg) }
            } else if cmd == 0x2 { // LC_SYMTAB
                if let parsed = parseSymtab(d, off, is64: is64, segs: segs) { syms = parsed }
            }
            off += cs
            if off + 8 > d.count { break }
        }
        return Slice(label: label, cputype: cputype, is64: is64,
                     segments: segs, symbols: syms, base: base)
    }

    private static func parseSegment(_ d: Data, _ off: Int, is64: Bool) -> Segment? {
        let nameBytes = [UInt8](d[off + 8..<min(d.count, off + 24)])
        let name = String(bytes: nameBytes, encoding: .utf8)?
            .split(separator: "\0").first.map(String.init) ?? ""
        if is64 {
            guard let va = u64(d, off + 24), let vs = u64(d, off + 32),
                  let fo = u64(d, off + 40), let fs = u64(d, off + 48) else { return nil }
            return Segment(name: name, vmaddr: va, vmsize: vs, fileoff: fo, filesize: fs)
        } else {
            guard let va = u32(d, off + 24).map({ UInt64($0) }),
                  let vs = u32(d, off + 28).map({ UInt64($0) }),
                  let fo = u32(d, off + 32).map({ UInt64($0) }),
                  let fs = u32(d, off + 36).map({ UInt64($0) }) else { return nil }
            return Segment(name: name, vmaddr: va, vmsize: vs, fileoff: fo, filesize: fs)
        }
    }

    private static func parseSymtab(_ d: Data, _ off: Int, is64: Bool, segs: [Segment]) -> [Symbol]? {
        guard let symoff = u32(d, off + 8).map({ Int($0) }),
              let nsyms = u32(d, off + 12).map({ Int($0) }),
              let stroff = u32(d, off + 16).map({ Int($0) }),
              let strsize = u32(d, off + 20).map({ Int($0) }) else { return nil }
        let ent = is64 ? 16 : 12
        var out: [Symbol] = []
        let cap = min(nsyms, 500_000)
        for i in 0..<cap {
            let p = symoff + i * ent
            guard p + ent <= d.count else { break }
            guard let strx = u32(d, p) else { continue }
            let type = d[p + 4]
            if (type & 0xE0) != 0 { continue } // STAB
            let value: UInt64 = is64 ? (u64(d, p + 8) ?? 0) : (u32(d, p + 8).map { UInt64($0) } ?? 0)
            let sp = stroff + Int(strx)
            guard sp >= stroff, sp < d.count, sp < stroff + strsize else { continue }
            // 找字符串结尾
            var ep = sp
            let limit = min(d.count, stroff + strsize)
            while ep < limit, d[ep] != 0 { ep += 1 }
            guard ep > sp, let name = String(data: d[sp..<ep], encoding: .utf8), !name.isEmpty else { continue }
            var fo: UInt64? = nil
            for s in segs where value >= s.vmaddr && value < s.vmaddr + s.vmsize {
                fo = s.fileoff + (value - s.vmaddr)
                break
            }
            out.append(Symbol(name: name, value: value, fileoff: fo))
        }
        return out
    }
}

/// zlib/deflate 解压（用系统 Compression 框架，iOS 标准库的一部分）。
import Compression

enum Inflate {
    static func decompress(_ data: Data, expected: Int) -> Data? {
        let src = [UInt8](data)
        let dstCap = max(expected, 1)
        var dst = [UInt8](repeating: 0, count: dstCap)
        let got = dst.withUnsafeMutableBytes { dstBuf -> Int in
            src.withUnsafeBytes { srcBuf -> Int in
                // ZIP 条目用的是 raw deflate（无 zlib 头），Swift 导入的常量名为 compression_deflate
                compression_decode_buffer(dstBuf.baseAddress!, dstCap,
                                          srcBuf.baseAddress!, src.count,
                                          nil, compression_deflate)
            }
        }
        guard got > 0 else { return nil }
        return Data(dst[0..<got])
    }
}
