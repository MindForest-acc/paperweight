import Foundation

let corpus = Corpus.load()
var failures = 0
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print("\(ok ? "✓" : "✗") \(label)\(detail.isEmpty ? "" : "  \(detail)")")
    if !ok { failures += 1 }
}

// 1. 语料完整性
let books = Set(corpus.quotes.map(\.book))
check("书目齐全", books == ["yi", "laozi", "sunzi", "mozi", "zhuangzi", "yangming", "zeng", "maoxuan"], "\(books.sorted())")
check("无重复原文", Set(corpus.quotes.map(\.text)).count == corpus.quotes.count)
check("每条都有出处与释义",
      corpus.quotes.allSatisfy { !$0.source.isEmpty && !($0.note ?? "").isEmpty })
check("每本书都有闲章", corpus.books.values.allSatisfy { !$0.seal.isEmpty })

// 2. 竖排切分不丢字
let lost = corpus.quotes.filter { q in
    let stripped = q.text.filter { !"，。；：、！？「」《》（）·—“”".contains($0) }
    return TextLayout.columns(q.text).joined() != String(stripped)
}
check("竖排切分不丢字", lost.isEmpty, lost.first.map { "例：\($0.text)" } ?? "")

// 3. 竖排候选的高度上限（最长栏 ≤ 7 字）
let vertical = corpus.quotes.filter { TextLayout.fitsVertical($0.text) }
let overLong = vertical.filter { (TextLayout.columns($0.text).map(\.count).max() ?? 0) > 7 }
check("竖排卡片不会过高", overLong.isEmpty)
print("   竖排 \(vertical.count) 条 / 横排 \(corpus.quotes.count - vertical.count) 条")

// 4. 抽样器：无放回洗牌袋
let pool = corpus.quotes
UserDefaults.standard.removeObject(forKey: "shuffleBag")
UserDefaults.standard.removeObject(forKey: "shuffleLast")
let sh = Shuffler()
var cur: Quote? = nil
var seen: [String: Int] = [:]
var lastIndexOf: [String: Int] = [:]
var maxGap = 0
var immediateRepeats = 0
let draws = pool.count * 20
for i in 0 ..< draws {
    guard let n = sh.next(from: pool, avoiding: cur) else { break }
    if let c = cur, c.id == n.id { immediateRepeats += 1 }
    if let prev = lastIndexOf[n.id] { maxGap = max(maxGap, i - prev) }
    lastIndexOf[n.id] = i
    seen[n.id, default: 0] += 1
    cur = n
}
check("零立即重复", immediateRepeats == 0, "\(draws) 次抽样")
check("全语料都被抽到过", seen.count == pool.count, "覆盖 \(seen.count)/\(pool.count)")
let counts = seen.values.sorted()
check("每句出现次数最多差 1 次", (counts.last ?? 0) - (counts.first ?? 0) <= 1,
      "最少 \(counts.first ?? 0) / 最多 \(counts.last ?? 0)")
check("两次出现间隔有界（≤ 2N−1）", maxGap <= 2 * pool.count - 1,
      "实测最大间隔 \(maxGap)，上限 \(2 * pool.count - 1)")

// 候选池中途缩小（用户关掉几本书）时不能卡死
let narrowed = pool.filter { $0.book == "mozi" }
var ok = true
for _ in 0 ..< 200 where sh.next(from: narrowed, avoiding: nil) == nil { ok = false }
check("候选池缩小后仍能持续出句", ok)

// 5. 校验覆盖率
let verified = corpus.quotes.filter { $0.verified != nil }
print("   底本校验 \(verified.count)/\(corpus.quotes.count) 条")

print(failures == 0 ? "\n全部通过" : "\n\(failures) 项未通过")
exit(failures == 0 ? 0 : 1)
