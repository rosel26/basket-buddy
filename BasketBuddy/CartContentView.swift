//
//  CartContentView.swift
//  BasketBuddy
//
//  Created by Rose Liu on 2025-09-27.
//

import SwiftUI

struct CartControlView: View {
    var body: some View {
        VStack(spacing: 40) {
            Text("Your cart is active")
                .font(.headline)
                .padding(.top, 20)
            
            // Start Cart Button
            Button(action: {
            }) {
                Text("Start Cart")
                    .font(.title3)
                    .foregroundColor(.black)
                    .frame(width: 200, height: 60)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            }
            
            // Stop Cart Button
            Button(action: {
            }) {
                Text("Stop Cart")
                    .font(.title3)
                    .foregroundColor(.black)
                    .frame(width: 200, height: 60)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            }
            
            // Disconnect Button
            Button(action: {
                // TODO: Disconnect logic
            }) {
                Text("Disconnect")
                    .font(.title3)
                    .foregroundColor(.black)
                    .frame(width: 200, height: 60)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
            }
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

struct CartControlView_Previews: PreviewProvider {
    static var previews: some View {
        CartControlView()
    }
}
