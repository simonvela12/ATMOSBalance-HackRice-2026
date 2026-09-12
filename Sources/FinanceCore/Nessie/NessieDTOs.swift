import Foundation

struct NessieAccount: Decodable, Sendable {
    let id: String
    let type: String?
    let nickname: String?
    let balance: Decimal
    let customerID: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id", type, nickname, balance
        case customerID = "customer_id"
    }
}

struct NessiePurchase: Decodable, Sendable {
    let id: String?
    let merchantID: String?
    let payerID: String?
    let purchaseDate: String?
    let amount: Decimal?
    let status: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id", amount, status, description
        case merchantID = "merchant_id", payerID = "payer_id", purchaseDate = "purchase_date"
    }
}

struct NessieDeposit: Decodable, Sendable {
    let id: String?
    let payeeID: String?
    let transactionDate: String?
    let amount: Decimal?
    let status: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id", amount, status, description
        case payeeID = "payee_id", transactionDate = "transaction_date"
    }
}

struct NessieWithdrawal: Decodable, Sendable {
    let id: String?
    let payerID: String?
    let transactionDate: String?
    let amount: Decimal?
    let status: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case id = "_id", amount, status, description
        case payerID = "payer_id", transactionDate = "transaction_date"
    }
}

struct NessieTransfer: Decodable, Sendable {
    let id: String?
    let payerID: String?
    let payeeID: String?
    let transactionDate: String?
    let amount: Decimal?
    let status: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case legacyID = "_id", id, amount, status, description
        case payerID = "payer_id", payeeID = "payee_id", transactionDate = "transaction_date"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .legacyID)
            ?? container.decodeIfPresent(String.self, forKey: .id)
        payerID = try container.decodeIfPresent(String.self, forKey: .payerID)
        payeeID = try container.decodeIfPresent(String.self, forKey: .payeeID)
        transactionDate = try container.decodeIfPresent(String.self, forKey: .transactionDate)
        amount = try container.decodeIfPresent(Decimal.self, forKey: .amount)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        description = try container.decodeIfPresent(String.self, forKey: .description)
    }
}

struct NessieMerchant: Decodable, Sendable {
    let id: String
    let name: String?
    let category: [String]?

    enum CodingKeys: String, CodingKey { case id = "_id", name, category }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        if let categories = try? container.decodeIfPresent([String].self, forKey: .category) {
            category = categories
        } else if let singleCategory = try container.decodeIfPresent(String.self, forKey: .category) {
            category = [singleCategory]
        } else {
            category = nil
        }
    }
}
