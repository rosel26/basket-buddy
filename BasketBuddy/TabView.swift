//
//  NewTabView.swift
//  BasketBuddy
//
//  Created by Rose Liu on 2025-09-27.
//

import SwiftUI

struct RootView: View {
    @State private var isConnected = false   // controls when to show tabs

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
            CartControlView()
                .tabItem {
                    Image(systemName: "house")
                    Text("Home")
                }

            // 3. Basket Screen
            BasketView()
                .tabItem {
                    Image(systemName: "cart")
                    Text("Cart")
                }
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
                // UWB HERE
                isConnected = true
            }
            .font(.headline)
            .frame(width: 180, height: 50)
            .background(Color(.systemGray6))
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
            Spacer()
            Text("You are connected")
                .font(.headline)

            ForEach(["Start Cart", "Stop Cart", "Disconnect"], id: \.self) { label in
                Button(label) {
                }
                .font(.title3)
                .frame(width: 200, height: 60)
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .foregroundColor(.black)
            }
            Spacer()
        }
    }
}

struct BasketView: View {
    let products = [
        ("Product 1", 4.99),
        ("Product 2", 2.99),
        ("Product 3", 6.99),
        ("Product 4", 6.99)
    ]

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
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }

            Spacer()
        }
        .padding()
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

