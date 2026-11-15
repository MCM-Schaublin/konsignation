import Foundation

struct CatalogEntry: Decodable {
    let ref: String
    let name: String
    let src: String?
}

/// Artikelkatalog (GTIN → Artikel), aus dem Web-Tool übernommen.
enum Catalog {
    static let entries: [String: CatalogEntry] = {
        guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: CatalogEntry].self, from: data) else {
            return [:]
        }
        return dict
    }()
}
