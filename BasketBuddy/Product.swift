//
//  Product.swift
//  BasketBuddy
//
//  Created by Elly Zheng on 10/1/25.
//

import Foundation
import Combine

struct ProductResponse: Codable {
    let product: Product?
    let status: Int
    let status_verbose: String?
}

struct Product: Codable {
    let product_name: String?
}
