//
//  NewTabView.swift
//  BasketBuddy
//
//  Created by Rose Liu on 2025-09-27.
//

import SwiftUI
import AVFoundation
import CoreData
import CoreImage
import UIKit

struct BasketItem: Identifiable {
    let id: String
    let name: String
    let price: Double
    var quantity: Int
}

struct RootView: View {
    @State private var isConnected = false
    @State private var roleChosen = false
    @StateObject private var uwb = UWBManager()

    var body: some View {
        if isConnected && roleChosen{
            MainTabView()
                .environmentObject(uwb)
        }
        else if isConnected {
            FollowingRoleView(roleChosen: $roleChosen)
                .environmentObject(uwb)
        }
        else {
            WelcomeView(isConnected: $isConnected)
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var uwb: UWBManager

    var body: some View {
        TabView {
            // Home/Cart Control
            CartControlView()
                .tabItem {
                    Image(systemName: "house")
                    Text("Home")
                }
                .environmentObject(uwb)
            // Basket Contents
            BasketView()
                .tabItem {
                    Image(systemName: "cart")
                    Text("Cart")
                }
        }
    }
}

struct WelcomeView: View {
    @Binding var isConnected: Bool
    @State private var isConnecting = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "cart")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .padding(.bottom, 20)

            Text("Welcome to\nBasket Buddy")
                .font(.title)
                .multilineTextAlignment(.center)
                .bold()

            Text("the next generation’s\nshopping cart")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Spacer()

            Button("Connect") {
                isConnected = true
            }
            
            .font(.headline)
            .frame(width: 180, height: 50)
            .background(Color.accentColor)
            .cornerRadius(25)
            .foregroundColor(.black)
            .padding(.bottom, 40)
        }
        .padding()
    }
}

struct FollowingRoleView: View {
    @Binding var roleChosen: Bool
    @EnvironmentObject var uwb: UWBManager
        
    var body: some View {
        VStack(spacing: 40) {
            Text("Select Device Role")
                .font(.headline)
                .padding(.top, 20)
            
            Button(action: {
                uwb.role = .shopper
                uwb.startForCurrentRole()
                uwb.sendMyRoleToPeers()
                roleChosen = true
            }) {
                Text("Shopper")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 200, height: 60)
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
            
            Button(action: {
                uwb.role = .cartLeft
                uwb.startForCurrentRole()
                uwb.sendMyRoleToPeers()
                roleChosen = true
            }) {
                Text("Cart Left")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 200, height: 60)
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
            
            Button(action: {
                uwb.role = .cartRight
                uwb.startForCurrentRole()
                uwb.sendMyRoleToPeers()
                roleChosen = true
            }) {
                Text("Cart Right")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 200, height: 60)
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

enum CartConnectionState: String {
    case disconnected = "Disconnected"
    case searching    = "Searching"
    case ready        = "Ready to Begin"
    case following    = "Following You"
    case error        = "Error"
}

struct CartControlView: View {
    @EnvironmentObject var uwb: UWBManager
    
    @State private var obstacleAvoidanceOn: Bool = false
    @State private var lastStatusMessage: String = "Cart is idle."
    
    private var bothCartsLocked: Bool {
        if uwb.role == .shopper {
            return uwb.isLeftRangingLive && uwb.isRightRangingLive
        } else {
            return uwb.isRangingLive
        }
    }

    private var connectionState: CartConnectionState {
        if !uwb.isReady {
            return .disconnected
        }

        if uwb.role == .shopper {
            if bothCartsLocked {
                return uwb.isFollowing ? .following : .ready
            } else {
                return .searching
            }
        } else {
            if bothCartsLocked {
                return uwb.isFollowing ? .following : .ready
            } else {
                return .searching
            }
        }
    }
    
    private var stateColor: Color {
        switch connectionState {
        case .disconnected: return .gray
        case .searching:    return .yellow
        case .ready:        return .blue
        case .following:    return .green
        case .error:        return .red
        }
    }
    
    private var primaryActionTitle: String {
        switch connectionState {
        case .disconnected, .error:
            return "Connect to Cart"
        case .searching:
            return "Cancel Search"
        case .ready:
            return "Start Follow Mode"
        case .following:
            return "Pause/Stop Follow"
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                statusCard
                connectionControls
                followSettings
                emergencySection
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }
}

private extension CartControlView {
    
    var headerSection: some View {
        VStack(spacing: 8) {
            Text("Cart Control")
                .font(.title2)
                .bold()
            
            Text("Role: \(uwb.role.rawValue)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }
    
    var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 14, height: 14)
                
                Text(connectionState.rawValue)
                    .font(.headline)
                
                Spacer()
            }
            
            Text(uwb.isFollowing
                 ? "Cart is actively following you."
                 : statusSubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Left Cart")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(distanceString(uwb.leftCartDistance))
                        .font(.body)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Right Cart")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(distanceString(uwb.rightCartDistance))
                        .font(.body)
                }
            }
            
            Text(uwb.status)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .frame(height: 150)   // fixed so the box doesn't jump
        .background(Color(.secondarySystemBackground))
        .cornerRadius(16)
    }

    private func distanceString(_ value: Double?) -> String {
        guard let v = value else { return "--" }
        return String(format: "%.2f m", v)
    }
    
    var connectionControls: some View {
        VStack(spacing: 12) {
            Text("Connection & Follow")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button(action: primaryActionTapped) {
                Text(primaryActionTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            
            Button(action: disconnectTapped) {
                Text("Disconnect Cart")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color(.tertiarySystemBackground))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
            }
        }
    }
    
    var followSettings: some View {
        VStack(spacing: 16) {
            Text("Developer Options")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle(isOn: $obstacleAvoidanceOn.onChange { newValue in
                uwb.sendObstacleAvoidanceState(newValue)
            }) {
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Obstacle Avoidance (Dev)")
                    Text("Use LIDAR to slow or stop the cart near obstacles.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
                
                
        }
    }
    
    var emergencySection: some View {
        VStack(spacing: 12) {
            Text("Safety")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button(action: emergencyStopTapped) {
                Text("EMERGENCY STOP")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }
        }
        .padding(.bottom, 24)
    }
}

extension Binding {
    func onChange(_ handler: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { newValue in
                self.wrappedValue = newValue
                handler(newValue)
            }
        )
    }
}

private extension CartControlView {
    var statusSubtitle: String {
        switch connectionState {
        case .disconnected:
            return "Press Connect to search for the shopper’s iPhone."
        case .searching:
            return "Searching for shopper and distance updates…"
        case .ready:
            return "Cart is tracking you. You can start following."
        case .following:
            return "Cart is moving using UWB data."
        case .error:
            return "Something went wrong. Try disconnecting and reconnecting."
        }
    }
}

private extension CartControlView {
    
    func primaryActionTapped() {
        switch connectionState {
        case .disconnected, .error:
            uwb.beginDiscovery()
            lastStatusMessage = "Starting discovery for peers…"
            
        case .searching:
            uwb.disconnect()
            lastStatusMessage = "Search cancelled."
            
        case .ready:
            uwb.startFollowMode()
            lastStatusMessage = "Requested cart to start following."
            
        case .following:
            uwb.stopFollowMode()
            lastStatusMessage = "Requested cart to stop / pause following."
        }
    }
    
    func disconnectTapped() {
        uwb.sendEmergencyStop()
        lastStatusMessage = "Cart disconnected."
    }
    
    func emergencyStopTapped() {
        uwb.sendEmergencyStop()
        lastStatusMessage = "Emergency stop sent. Cart should halt immediately."
    }
}

// https://www.hackingwithswift.com/example-code/media/how-to-create-a-barcode
func checkout(from string: String) -> UIImage? {
    guard !string.isEmpty else {
        print("Checkout Error: Input string is empty")
        return nil
    }
    
    print("Generating barcode for \(string)")
    let data = string.data(using: String.Encoding.ascii)
    
    if let filter = CIFilter(name: "CICode128BarcodeGenerator") {
        filter.setValue(data, forKey: "inputMessage")
        let transform = CGAffineTransform(scaleX: 3, y: 3)
        
        if let output = filter.outputImage?.transformed(by: transform) {
            print("Returned image")
            return UIImage(ciImage: output)
        }
    }
    print("No image generated")
    return nil
}

struct BasketView: View {
    @State private var showScanner = false
    @State private var scannedCode: String?
    @State private var products: [BasketItem] = []
    @State private var checkoutImage: Image?
    @State private var showCheckoutImage = false
    @Environment(\.managedObjectContext) private var viewContext

    var total: Double {
        products.map { $0.price * Double($0.quantity) }.reduce(0, +)
    }
    
    var totalItemCount: Int {
        products.map { $0.quantity }.reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Your Basket")
                    .font(.title2)
                    .bold()
                Spacer()
            }
            
            HStack {
                Text("\(totalItemCount) Items")
                Spacer()
                Text("$\(total, specifier: "%.2f")")
            }
            .font(.headline)
            
            HStack(spacing: 20) {
                Button(action: {
                    showScanner = true
                }) {
                    Text("Scan Items")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }
                
                Button(action: {
                    Task {
                        if let image = checkout(from: String(total)) {
                            print("Checkout image made")
                            self.checkoutImage = Image(uiImage: image)
                            self.showCheckoutImage = true
                        }
                    }
                }) {
                    Text("Checkout")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }
            }
            .sheet(isPresented: $showScanner, onDismiss: {
                processBarcode()
            }) {
                BarcodeScannerView(scannedCode: $scannedCode)
            }
            
            Text("Your Items")
                .font(.subheadline)
                .bold()
            
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(products) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            HStack(spacing: 16) {
                                Button(action: {
                                    decreaseQuantity(for: item)
                                }) {
                                    Image(systemName: "minus.circle")
                                        .font(.title3)
                                        .foregroundColor(Color.accentColor)
                                }
                                
                                Text("x\(item.quantity)")
                                    .font(.headline)
                                
                                Button(action: {
                                    increaseQuantity(for: item)
                                }) {
                                    Image(systemName: "plus.circle")
                                        .font(.title3)
                                        .foregroundColor(Color.accentColor)
                                }
                            }
                            
                            Text("$\(item.price * Double(item.quantity), specifier: "%.2f")")
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                    }
                }
            }
        }
        .padding()
        .sheet(isPresented: $showCheckoutImage) {
            VStack(spacing: 20) {
                Text("Please scan to checkout")
                    .font(.title2)
                
                if let checkoutImage {
                    checkoutImage
                        .resizable()
                        .scaledToFit()
                        .frame(height: 100)
                } else {
                    Text("Error: Could not generate barcode.")
                }
                
                Button("Done") {
                    showCheckoutImage = false
                    checkoutImage = nil
                }
                .font(.headline)
                .padding()
            }
        }
    }
    
    func processBarcode() {
        guard let barcode = scannedCode else { return }
                    
        // Check if product is already in the database
        if let existingProduct = fetchProduct(with: barcode) {
                
            // Check if product is already in the BASKET
            if let index = products.firstIndex(where: { $0.id == barcode }) {
                products[index].quantity += 1
                print("Incremented quantity for \(products[index].name)")
                    
            } else {
                let name = existingProduct.name ?? "Unknown Item"
                let price = existingProduct.price
                let newItem = BasketItem(id: barcode, name: name, price: price, quantity: 1)
                products.append(newItem)
                print("Product found and added to basket: \(name)")
            }
        } else {
            print("Product with barcode \(barcode) not in database")
        }
        scannedCode = nil
    }
        
    func fetchProduct(with barcode: String) -> Product? {
        // Create the fetch request for the Product entity
        let fetchRequest: NSFetchRequest<Product> = Product.fetchRequest()
                
        // Find items based on barcode
        fetchRequest.predicate = NSPredicate(format: "barcode == %@", barcode)
                
        // Only fetch 1 item
        fetchRequest.fetchLimit = 1
                
        // Attempt fetch
        do {
            let getProducts = try viewContext.fetch(fetchRequest)
            return getProducts.first
        } catch {
            print("Failed to fetch product with barcode \(barcode): \(error)")
            return nil
        }
    }
    
    func decreaseQuantity(for item: BasketItem) {
        if let index = products.firstIndex(where: { $0.id == item.id }) {
            if products[index].quantity > 1 {
                products[index].quantity -= 1
                print("Decreased quantity for \(products[index].name)")
            } else {
                let removedItem = products.remove(at: index)
                print("Removed \(removedItem.name)")
            }
        }
    }
    
    func increaseQuantity(for item: BasketItem) {
        if let index = products.firstIndex(where: { $0.id == item.id }) {
            products[index].quantity += 1
            print("Increased quantity for \(products[index].name)")
        }
    }
}
