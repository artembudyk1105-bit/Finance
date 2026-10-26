import UIKit

/// Сметы: Excel (SpreadsheetML, 3 листа), PDF, CSV и резервная копия
@MainActor
enum Exporter {
    enum Range: Hashable {
        case month(String), year(Int), all
        var title: String {
            switch self {
            case .month(let m): return Day.monthName(m)
            case .year(let y): return "\(y) год"
            case .all: return "Всё время"
            }
        }
        var fileTag: String {
            switch self {
            case .month(let m): return m
            case .year(let y): return "\(y)"
            case .all: return "всё_время"
            }
        }
        func contains(_ t: Transaction) -> Bool {
            switch self {
            case .month(let m): return t.month == m
            case .year(let y): return t.day.hasPrefix("\(y)-")
            case .all: return true
            }
        }
    }

    static func list(_ range: Range, _ store: Store) -> [Transaction] {
        store.data.transactions.filter { range.contains($0) }.sorted { $0.day != $1.day ? $0.day < $1.day : $0.createdAt < $1.createdAt }
    }

    private static func write(_ data: Data, _ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? data.write(to: url, options: .atomic)
        return url
    }

    private static func ruDate(_ day: String) -> String { day.split(separator: "-").reversed().joined(separator: ".") }

    // MARK: CSV

    static func csv(_ range: Range, _ store: Store) -> URL {
        var rows = [["Дата", "Тип", "Название", "Категория", "Обязательная", "Сумма", "Валюта"]]
        for t in list(range, store) {
            rows.append([ruDate(t.day), t.type.title, t.name, t.cat.name, t.type == .expense ? (t.isMandatory ? "да" : "нет") : "",
                         Parser.numString(t.signedAmount).replacingOccurrences(of: ".", with: ","), store.settings.currency])
        }
        let text = rows.map { r in
            r.map { c in c.contains(";") || c.contains("\"") || c.contains("\n") ? "\"" + c.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : c }.joined(separator: ";")
        }.joined(separator: "\r\n")
        return write(Data(("\u{FEFF}" + text).utf8), "Смета_\(range.fileTag).csv")
    }

    // MARK: Excel

    private static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    private static func cell(_ v: String, _ style: String = "") -> String {
        "<Cell\(style.isEmpty ? "" : " ss:StyleID=\"\(style)\"")><Data ss:Type=\"String\">\(esc(v))</Data></Cell>"
    }
    private static func cell(_ v: Double, _ style: String = "") -> String {
        "<Cell\(style.isEmpty ? "" : " ss:StyleID=\"\(style)\"")><Data ss:Type=\"Number\">\(Parser.numString(v))</Data></Cell>"
    }
    private static func row(_ cells: [String]) -> String { "<Row>" + cells.joined() + "</Row>" }
    private static func sheet(_ name: String, _ widths: [Int], _ rows: [String]) -> String {
        "<Worksheet ss:Name=\"\(esc(name))\"><Table>" + widths.map { "<Column ss:Width=\"\($0)\"/>" }.joined() + rows.joined() + "</Table>" +
        "<WorksheetOptions xmlns=\"urn:schemas-microsoft-com:office:excel\"><FreezePanes/><SplitHorizontal>1</SplitHorizontal><TopRowBottomPane>1</TopRowBottomPane></WorksheetOptions></Worksheet>"
    }

    static func excel(_ range: Range, _ store: Store) -> URL {
        let txs = list(range, store)
        let cur = store.settings.currency
        let months = Array(Set(txs.map(\.month))).sorted()

        var r1 = [row(["Месяц", "Поступления", "Траты", "Обязательные", "Необязательные", "Остаток", "Сбережения, %"].map { cell($0, "h") })]
        var inc = 0.0, exp = 0.0, must = 0.0, opt = 0.0
        for m in months {
            let s = store.summary(m)
            inc += s.income; exp += s.expense; must += s.mandatory; opt += s.optional
            r1.append(row([cell(Day.monthName(m)), cell(s.income, "m"), cell(s.expense, "m"), cell(s.mandatory, "m"),
                           cell(s.optional, "m"), cell(s.balance, "m"), cell((s.saveRate * 1000).rounded() / 10)]))
        }
        r1.append(row([cell("ИТОГО", "b"), cell(inc, "mb"), cell(exp, "mb"), cell(must, "mb"), cell(opt, "mb"), cell(inc - exp, "mb"),
                       cell(inc > 0 ? ((inc - exp) / inc * 1000).rounded() / 10 : 0, "b")]))

        var byCat: [String: Double] = [:]
        for t in txs { byCat["\(t.type.rawValue):\(t.category)", default: 0] += t.amount }
        var r2 = [row(["Тип", "Категория", "Обязательная", "Сумма, \(cur)", "Доля, %"].map { cell($0, "h") })]
        for k in byCat.keys.sorted(by: { byCat[$0, default: 0] > byCat[$1, default: 0] }) {
            let parts = k.split(separator: ":").map(String.init)
            let isInc = parts[0] == TxType.income.rawValue
            let base = isInc ? inc : exp
            let v = byCat[k, default: 0]
            r2.append(row([cell(isInc ? "Поступление" : "Трата"), cell(Category.byId(parts[1]).name),
                           cell(isInc ? "" : (store.isMandatory(parts[1]) ? "да" : "нет")), cell(v, "m"),
                           cell(base > 0 ? (v / base * 1000).rounded() / 10 : 0)]))
        }

        var r3 = [row(["Дата", "Тип", "Название", "Категория", "Обязательная", "Сумма, \(cur)"].map { cell($0, "h") })]
        for t in txs {
            r3.append(row([cell(ruDate(t.day)), cell(t.type.title), cell(t.name), cell(t.cat.name),
                           cell(t.type == .expense ? (t.isMandatory ? "да" : "нет") : ""), cell(t.signedAmount, t.type == .income ? "mi" : "me")]))
        }

        let xml = """
        <?xml version="1.0" encoding="UTF-8"?><?mso-application progid="Excel.Sheet"?>\
        <Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet" xmlns:x="urn:schemas-microsoft-com:office:excel">\
        <Styles><Style ss:ID="Default"><Font ss:FontName="Calibri" ss:Size="11"/></Style>\
        <Style ss:ID="h"><Font ss:Bold="1" ss:Color="#FFFFFF"/><Interior ss:Color="#007AFF" ss:Pattern="Solid"/></Style>\
        <Style ss:ID="b"><Font ss:Bold="1"/></Style>\
        <Style ss:ID="m"><NumberFormat ss:Format="#,##0.00"/></Style>\
        <Style ss:ID="mb"><Font ss:Bold="1"/><NumberFormat ss:Format="#,##0.00"/></Style>\
        <Style ss:ID="mi"><Font ss:Color="#1E8E3E"/><NumberFormat ss:Format="+#,##0.00"/></Style>\
        <Style ss:ID="me"><Font ss:Color="#D93025"/><NumberFormat ss:Format="#,##0.00"/></Style></Styles>
        """ + sheet("Сводка", [110, 100, 100, 100, 110, 100, 90], r1) + sheet("Категории", [90, 150, 90, 100, 70], r2) +
            sheet("Операции", [75, 90, 200, 140, 90, 100], r3) + "</Workbook>"
        return write(Data(xml.utf8), "Смета_\(range.fileTag).xls")
    }

    // MARK: PDF

    static func pdf(_ range: Range, _ store: Store) -> URL {
        let txs = list(range, store)
        let M: (Double) -> String = { store.money($0) }
        var inc = 0.0, exp = 0.0, must = 0.0, opt = 0.0
        var byCat: [String: Double] = [:]
        for t in txs {
            if t.type == .income { inc += t.amount; continue }
            exp += t.amount
            if t.isMandatory { must += t.amount } else { opt += t.amount }
            byCat[t.category, default: 0] += t.amount
        }
        let cats = byCat.keys.sorted { byCat[$0, default: 0] > byCat[$1, default: 0] }
        var h = """
        <html><head><meta charset="utf-8"><style>
        body{font:11pt -apple-system,Helvetica,sans-serif;color:#000}h1{font-size:20pt;margin:0 0 4pt}
        h2{font-size:13pt;margin:16pt 0 6pt;border-bottom:1px solid #ccc;padding-bottom:3pt}
        .pm{color:#666;margin-bottom:10pt}table{width:100%;border-collapse:collapse}
        td,th{padding:3pt 4pt;border-bottom:1px solid #eee;text-align:left}th{background:#f2f2f7}
        .r{text-align:right;white-space:nowrap}.g{color:#1e8e3e}.sum{width:60%}.tot td{font-weight:bold;border-top:2px solid #000}
        </style></head><body>
        <h1>Смета расходов и доходов</h1>
        """
        h += "<div class=\"pm\">Период: \(range.title) · сформировано \(ruDate(Day.today))</div>"
        h += "<table class=\"sum\"><tr><td>Поступления</td><td class=\"r\">\(M(inc))</td></tr><tr><td>Траты</td><td class=\"r\">\(M(exp))</td></tr>"
        h += "<tr><td>&nbsp;&nbsp;обязательные</td><td class=\"r\">\(M(must))</td></tr><tr><td>&nbsp;&nbsp;необязательные</td><td class=\"r\">\(M(opt))</td></tr>"
        h += "<tr class=\"tot\"><td>Остаток</td><td class=\"r\">\(store.money(inc - exp, sign: true))</td></tr>"
        if case .month = range, store.budget > 0 {
            h += "<tr><td>Лимит месяца</td><td class=\"r\">\(M(store.budget)) (\(exp > store.budget ? "превышен" : "соблюдён"))</td></tr>"
        }
        h += "</table><h2>Траты по категориям</h2><table><tr><th>Категория</th><th>Тип</th><th>Сумма</th><th>Доля</th></tr>"
        for c in cats {
            let v = byCat[c, default: 0]
            h += "<tr><td>\(Category.byId(c).icon) \(Category.byId(c).name)</td><td>\(store.isMandatory(c) ? "обязательная" : "необязательная")</td><td class=\"r\">\(M(v))</td><td class=\"r\">\(Fmt.percent(exp > 0 ? v / exp : 0))</td></tr>"
        }
        h += "</table>"
        if case .month(let m) = range {
            h += "<h2>Выводы ассистента</h2><ul>"
            for i in Assistant.insights(m, store: store).prefix(6) { h += "<li><b>\(esc(i.title)).</b> \(esc(i.text))</li>" }
            h += "</ul>"
        }
        h += "<h2>Все операции (\(txs.count))</h2><table><tr><th>Дата</th><th>Название</th><th>Категория</th><th>Сумма</th></tr>"
        for t in txs {
            h += "<tr><td>\(ruDate(t.day))</td><td>\(esc(t.name))\(t.type == .expense && !t.isMandatory ? " <i>(необяз.)</i>" : "")</td><td>\(t.cat.name)</td><td class=\"r\(t.type == .income ? " g" : "")\">\(store.money(t.signedAmount, sign: true))</td></tr>"
        }
        h += "</table></body></html>"

        let formatter = UIMarkupTextPrintFormatter(markupText: h)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4
        renderer.setValue(NSValue(cgRect: page), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: page.insetBy(dx: 36, dy: 40)), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return write(data as Data, "Смета_\(range.fileTag).pdf")
    }

    static func backup(_ store: Store) -> URL {
        write(store.exportJSON(), "Финансы_бэкап_\(Day.today).json")
    }
}
