//
//  BasketBuddyApp.swift
//  BasketBuddy
//
//  Created by Rose Liu on 2025-09-26.
//

import SwiftUI
import CoreData

@main
struct BasketBuddyApp: App {
    @StateObject private var coreDataStack = CoreDataStack.shared
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, coreDataStack.persistentContainer.viewContext)
                .onAppear {
                    // Call the function to generate data when the app appears
                    populateDatabase(context: coreDataStack.persistentContainer.viewContext)
                }
        }
    }
    
    private func populateDatabase(context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<Product> = Product.fetchRequest()
        
        do {
            let productCount = try context.count(for: fetchRequest)
            // Only add data if the count is 0
            guard productCount == 0 else {
                print("Database already populated.")
                return
            }
            
            print("Adding one initial product...")
            
            // Create product
            let product1 = Product(context: context)
            product1.name = "Ben & Jerry's Half Baked Chocolate & Vanilla Ice Cream Pint Non-GMO 16 oz"
            product1.barcode = "0076840101320"
            product1.price = 5.69
            
            let product2 = Product(context: context)
            product2.name = "Good Culture Organic Classic Cottage Cheese, 16 oz"
            product2.barcode = "0859977005064"
            product2.price = 6.29
            
            let product3 = Product(context: context)
            product3.name = "365 By Whole Foods Market, Potato Chips Rippled Sea Salt - Party Size, 13 Ounce"
            product3.barcode = "0099482535223"
            product3.price = 3.99
            
            let product4 = Product(context: context)
            product4.name = "365 by Whole Foods Market, Organic Whole Milk, 64 oz"
            product4.barcode = "0099482165413"
            product4.price = 4.59
            
            let product5 = Product(context: context)
            product5.name = "Chobani® Whole Milk Plain Greek Yogurt 32oz"
            product5.barcode = "0894700010434"
            product5.price = 6.49
            
            // Save the product
            try context.save()
            print("Initial product saved.")
            
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
}
