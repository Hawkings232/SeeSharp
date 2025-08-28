//
//  TitleView.swift
//  SeeSharp
//
//  Created by Eddie Zhou on 5/11/25.
//

import SwiftUI
import ActivityIndicatorView

struct TitleView: View {
    @State var showLoadingIndicator = true
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 40) {
                Image("MoonImage")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(.bottom, 40)
                
                HStack
                {
                    Image(systemName: "moon.fill")
                        .foregroundColor(.white)
                    Text("SeeSharp")
                        .font(.system(size: 28, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                }
                
                
                ActivityIndicatorView(isVisible: $showLoadingIndicator, type: .scalingDots(count: 3))
                    .frame(width: 50 , height: 40)
                    .foregroundColor(.white)
            }
        }
    }
}

#Preview
{
    TitleView();
}
