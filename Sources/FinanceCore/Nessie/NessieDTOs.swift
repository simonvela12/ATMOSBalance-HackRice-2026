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
        case id = "_id", amount, status, description
        case payerID = "payer_id", payeeID = "payee_id", transactionDate = "transaction_date"
    }
}

struct NessieMerchant: Decodable, Sendable {
    let id: String
    let name: String?
    let category: [String]?

    enum CodingKeys: String, CodingKey { case id = "_id", name, category }
}
