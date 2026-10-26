import SwiftUI

struct Category: Identifiable, Hashable {
    let id: String
    let type: TxType
    let name: String
    let icon: String
    let hex: String
    let mandatory: Bool
    let keywords: [String]

    var color: Color { Color(hex: hex) }

    static func byId(_ id: String) -> Category {
        all.first { $0.id == id } ?? all.first { $0.id == "other" }!
    }
    static var expenses: [Category] { all.filter { $0.type == .expense } }
    static var incomes: [Category] { all.filter { $0.type == .income } }

    static let all: [Category] = [
        Category(id: "food", type: .expense, name: "Продукты", icon: "🛒", hex: "34C759", mandatory: true,
                 keywords: ["продукт", "магазин", "супермаркет", "пятерочк", "магнит", "перекрест", "ашан", "лента", "хлеб", "молок", "мяс", "овощ", "фрукт", "вкусвилл", "азбука", "дикси", "спар", "сыр", "яйц", "крупа", "вода", "атб", "сильпо", "бакале"]),
        Category(id: "cafe", type: .expense, name: "Кафе и рестораны", icon: "☕", hex: "FF9500", mandatory: false,
                 keywords: ["кафе", "кофе", "кофейн", "ресторан", "обед", "ужин", "завтрак", "бар", "пицц", "суши", "роллы", "бургер", "макдон", "шаурм", "шаверм", "kfc", "кфс", "вкусно и точка", "старбакс", "перекус", "латте", "капучино", "пиво", "коктейл", "чай"]),
        Category(id: "delivery", type: .expense, name: "Доставка еды", icon: "🛵", hex: "FF6B35", mandatory: false,
                 keywords: ["доставк", "яндекс еда", "деливери", "delivery", "самокат", "глово", "glovo"]),
        Category(id: "transport", type: .expense, name: "Транспорт", icon: "🚇", hex: "007AFF", mandatory: true,
                 keywords: ["метро", "автобус", "проезд", "транспорт", "электричк", "троллейб", "трамва", "бензин", "топлив", "заправк", "парковк", "маршрутк", "проездн", "каршеринг"]),
        Category(id: "taxi", type: .expense, name: "Такси", icon: "🚕", hex: "FFCC00", mandatory: false,
                 keywords: ["такси", "uber", "убер", "яндекс го", "болт", "bolt", "ситимобил"]),
        Category(id: "home", type: .expense, name: "Жильё и ЖКХ", icon: "🏠", hex: "5856D6", mandatory: true,
                 keywords: ["аренд", "квартир", "ипотек", "жкх", "коммунал", "свет", "электричеств", "газ", "отоплен", "квартплат", "съем"]),
        Category(id: "phone", type: .expense, name: "Связь и интернет", icon: "📱", hex: "30B0C7", mandatory: true,
                 keywords: ["связь", "телефон", "интернет", "мобильн", "симк", "мтс", "билайн", "мегафон", "теле2", "киевстар"]),
        Category(id: "health", type: .expense, name: "Здоровье", icon: "💊", hex: "FF3B30", mandatory: true,
                 keywords: ["аптек", "лекарств", "врач", "стоматолог", "зубн", "анализ", "клиник", "витамин", "таблетк", "больниц", "медиц", "страховк"]),
        Category(id: "subs", type: .expense, name: "Подписки", icon: "🔁", hex: "AF52DE", mandatory: false,
                 keywords: ["подписк", "netflix", "нетфликс", "spotify", "спотифай", "яндекс плюс", "кинопоиск", "icloud", "айклауд", "youtube", "ютуб", "apple music", "chatgpt", "claude", "клод", "okko", "иви", "ivi"]),
        Category(id: "fun", type: .expense, name: "Развлечения", icon: "🎬", hex: "FF2D55", mandatory: false,
                 keywords: ["кино", "концерт", "игр", "театр", "клуб", "боулинг", "развлеч", "steam", "стим", "playstation", "плейстейшн", "квест", "музей", "выставк", "кальян"]),
        Category(id: "clothes", type: .expense, name: "Одежда и обувь", icon: "👕", hex: "00C7BE", mandatory: false,
                 keywords: ["одежд", "обув", "кроссовк", "футболк", "джинс", "куртк", "кофт", "платье", "штаны", "носки", "ботинк", "худи", "zara"]),
        Category(id: "shopping", type: .expense, name: "Покупки", icon: "🛍️", hex: "FF9F0A", mandatory: false,
                 keywords: ["покупк", "техник", "гаджет", "наушник", "wildberries", "вайлдберриз", "вб", "озон", "ozon", "алиэкспресс", "aliexpress", "маркетплейс", "розетк", "айфон", "iphone", "чехол", "зарядк", "ноутбук"]),
        Category(id: "beauty", type: .expense, name: "Красота и уход", icon: "💅", hex: "FF375F", mandatory: false,
                 keywords: ["стрижк", "парикмах", "барбер", "маникюр", "косметик", "салон", "шампунь", "крем", "духи", "парфюм"]),
        Category(id: "edu", type: .expense, name: "Образование", icon: "📚", hex: "0A84FF", mandatory: true,
                 keywords: ["курс", "книг", "обучен", "учеб", "школ", "репетитор", "универ", "урок", "тренинг"]),
        Category(id: "sport", type: .expense, name: "Спорт", icon: "🏋️", hex: "32D74B", mandatory: false,
                 keywords: ["спортзал", "фитнес", "тренировк", "абонемент", "бассейн", "йога", "тренер", "качалк"]),
        Category(id: "gifts", type: .expense, name: "Подарки", icon: "🎁", hex: "BF5AF2", mandatory: false,
                 keywords: ["подар", "цветы", "букет", "день рождени"]),
        Category(id: "debt", type: .expense, name: "Кредиты и долги", icon: "🏦", hex: "8E8E93", mandatory: true,
                 keywords: ["кредит", "долг", "займ", "рассрочк", "платеж по", "кредитк"]),
        Category(id: "family", type: .expense, name: "Дети и питомцы", icon: "🐾", hex: "A2845E", mandatory: true,
                 keywords: ["корм", "ветеринар", "детск", "игрушк", "садик", "подгузник", "кот", "собак"]),
        Category(id: "travel", type: .expense, name: "Путешествия", icon: "✈️", hex: "64D2FF", mandatory: false,
                 keywords: ["билет", "отел", "гостиниц", "авиа", "поездк", "отпуск", "хостел", "airbnb", "тур"]),
        Category(id: "other", type: .expense, name: "Прочее", icon: "📦", hex: "AEAEB2", mandatory: false, keywords: []),

        Category(id: "salary", type: .income, name: "Зарплата", icon: "💼", hex: "34C759", mandatory: false,
                 keywords: ["зарплат", "зп", "аванс", "оклад", "получк", "премия", "премию", "бонус"]),
        Category(id: "freelance", type: .income, name: "Подработка", icon: "💻", hex: "30D158", mandatory: false,
                 keywords: ["фриланс", "подработк", "заказ", "проект", "клиент", "заработал", "халтур"]),
        Category(id: "cashback", type: .income, name: "Кэшбэк и проценты", icon: "💳", hex: "00C7BE", mandatory: false,
                 keywords: ["кешбэк", "кэшбэк", "кешбек", "кэшбек", "cashback", "процент", "вклад", "дивиденд", "купон"]),
        Category(id: "sale", type: .income, name: "Продажа вещей", icon: "🏷️", hex: "FF9500", mandatory: false,
                 keywords: ["продал", "продажа", "авито", "olx"]),
        Category(id: "refund", type: .income, name: "Возвраты", icon: "↩️", hex: "5AC8FA", mandatory: false,
                 keywords: ["вернули", "возврат", "вернул долг"]),
        Category(id: "gift_in", type: .income, name: "Подарки", icon: "🎉", hex: "FF2D55", mandatory: false,
                 keywords: ["подарили", "подарок мне"]),
        Category(id: "other_in", type: .income, name: "Другие доходы", icon: "💰", hex: "FFD60A", mandatory: false, keywords: [])
    ]
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
