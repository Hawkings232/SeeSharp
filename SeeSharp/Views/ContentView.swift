//
//  ContentView.swift
//  SeeSharp
//
//  Created by Eddie Zhou on 5/11/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var manager = StateManager()
    
    @Environment(\.scenePhase) private var scenePhase
    @State private var showTitleView: Bool = false
    var body: some View {
        ZStack
        {
            if showTitleView
            {
                TitleView()
                    .zIndex(2)
                    .transition(.opacity)
            }
            MainCameraView()
                .environmentObject(manager)
        }
        .animation(.easeInOut(duration: 0.6), value:showTitleView)
        .onChange(of: scenePhase)
        { _, newPhase in
            switch newPhase
            {
            case .active:
                withAnimation(.easeOut)
                {
                    self.showTitleView = false
                }
                
            case .background:
                withAnimation(.easeIn)
                {
                    self.showTitleView = true
                }
            case .inactive:
                withAnimation(.easeIn)
                {
                    self.showTitleView = true
                }
            @unknown default:
                fatalError("Unknown phase \(newPhase)")
            }
        }
    }
}

#Preview {
    ContentView()
}
