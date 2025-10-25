//
//  NewTabView.swift
//  BasketBuddy
//
//  Created by Rose Liu on 2025-09-27.
//

import SwiftUI
import AVFoundation

struct RootView: View {
    @State private var isConnected = false

    var body: some View {
        if isConnected {
            MainTabView()
        } else {
            WelcomeView(isConnected: $isConnected)
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            // Home/Cart Control
            CartControlView()
                .tabItem {
                    Image(systemName: "house")
                    Text("Home")
                }
            // Basket Contents
            BasketView()
                .tabItem {
                    Image(systemName: "cart")
                    Text("Cart")
                }
            // Settings
            SettingView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
            
        }
    }
}

struct WelcomeView: View {
    @Binding var isConnected: Bool
    @StateObject private var uwb = UWBManager()
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

            Text("THE next generation’s\nshopping cart")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Spacer()

//            Button("Connect") {
//                uwb.start()
//                isConnected = true
//            }
            
            Button(isConnecting ? "Connecting…" : "Connect") {
                guard !isConnecting else { return }
                isConnecting = true
                uwb.start()
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

struct CartControlView: View {
    var body: some View {
        VStack(spacing: 40) {
            Text("Your cart is active")
                .font(.headline)
                .padding(.top, 20)
            
            // Start Cart Button
            Button(action: {
                startCart()
            }) {
                Text("Start Cart")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 200, height: 60)
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
            
            // Stop Cart Button
            Button(action: {
                stopCart()
            }) {
                Text("Stop Cart")
                    .font(.title3)
                    .foregroundColor(.white)
                    .frame(width: 200, height: 60)
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
            
            // Disconnect Button
            Button(action: {
                disconnectCart()
            }) {
                Text("Disconnect")
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

func startCart() {
}

func stopCart() {
}

func disconnectCart() {
}

func checkout() {
}

struct BasketView: View {
    @State private var showScanner = false
    @State private var scannedCode: String?
    @State private var scannedProductName: String?
    @State private var products: [(name: String, price: Double)] = []
    
//    let products = [
//        ("Product 1", 4.99),
//        ("Product 2", 6.99),
//        ("Product 3", 5.99),
//        ("Product 4", 6.99)
//    ]

    var total: Double {
        products.map { $0.1 }.reduce(0, +)
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
                Text("\(products.count) Items")
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
                    checkout()
                }) {
                    Text("Checkout")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerView(scannedCode: $scannedCode) 
            }
            
            if let code = scannedCode {
                Text("Scanned barcode: \(code)")
                    .font(.headline)
                    .padding()
            }
            if let name = scannedProductName {
                            Text("Product name: \(name)")
                                .font(.headline)
                                .padding()
            }
            

            Text("Your Items")
                .font(.subheadline)
                .bold()

            ForEach(products, id: \.0) { item in
                HStack {
                    Text(item.0)
                    Spacer()
                    Text("$\(item.1, specifier: "%.2f")")
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(12)
            }
            Spacer()
        }
        .padding()
        .onChange(of: scannedCode) { oldValue, newCode in
            guard let newCode else { return }
                fetchProductName(barcode: newCode)
            }
        }
        
    func fetchProductName(barcode: String) {
        let urlString = "https://world.openfoodfacts.org/api/v0/product/\(barcode).json"
        guard let url = URL(string: urlString) else { return }

        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }

            Task.detached {
                do {
                    let decoded = try JSONDecoder().decode(ProductResponse.self, from: data)
                    let name = decoded.product?.product_name ?? "Unknown product"
                            
                    await MainActor.run {
                        products.append((name: name, price: 0.0)) // price placeholder
                    }
                } catch {
                    print("Decoding error:", error)
                }
            }
        }.resume()
    }
}

struct SettingView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
    }
}

