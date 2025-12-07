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
            product1.name = "Rold Gold Pretzels, Original Sticks Flavored, 16 Oz"
            product1.barcode = "0028400047708"
            product1.price = 3.99
            
            let product2 = Product(context: context)
            product2.name = "Del Monte Kernel Corn, Whole, Fresh Cut - 15.25 Ounce"
            product2.barcode = "0024000163022"
            product2.price = 1.19
            
            let product3 = Product(context: context)
            product3.name = "Jif Extra Crunchy Peanut Butter, 16-Ounce Jar"
            product3.barcode = "0051500255377"
            product3.price = 4.49
            
            let product4 = Product(context: context)
            product4.name = "Garofalo Gemelli Dry Pasta 500g"
            product4.barcode = "0021511362142"
            product4.price = 2.99
            
            let product5 = Product(context: context)
            product5.name = "Nissin Top Ramen Noodle Soup Chicken Flavor 3 Ounce"
            product5.barcode = "0070662010037"
            product5.price = 0.99

            let product6 = Product(context: context)
            product6.name = "Campbell's Chunky Soup, Ready to Serve Creamy Chicken and Dumplings Soup, 18.8 oz Can"
            product6.barcode = "0051000142931"
            product6.price = 1.92
            
            let product7 = Product(context: context)
            product7.name = "Campbell's Condensed French Onion Soup, 10.5 oz Can"
            product7.barcode = "0051000011770"
            product7.price = 1.92
            
            let product8 = Product(context: context)
            product8.name = "Condensed Cream of Chicken Soup with Herbs, 10.5 oz Can"
            product8.barcode = "0051000123275"
            product8.price = 1.92
            
            let product9 = Product(context: context)
            product9.name = "Cadbury Dairy Milk Bubbly Mint Chocolate Block 160g"
            product9.barcode = "9300617063735"
            product9.price = 8.99
            
            // Save the product
            try context.save()
            print("Initial product saved.")
            
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
}
