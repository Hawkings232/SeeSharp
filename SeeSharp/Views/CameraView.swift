//
//  CameraView.swift
//  SeeSharp
//
//  Created by Eddie Zhou on 5/11/25.
//
import SwiftUI

struct OptionButton<Label: View> : View
{
    let action: () -> Void
    let disabled : () -> Bool = { false }
    
    @ViewBuilder let content : () -> Label
    
    @State private var isPressed : Bool = false
    @State private var showRipple : Bool = false
    @State private var scale : CGSize = .zero
    
    private func onTapped()
    {
        isPressed = true
        showRipple = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showRipple = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            action()
            isPressed = false
        }
    }
    

    var body : some View
    {
        Button(action: onTapped)
        {
            content()
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { scale = geo.size }
                    }
                )
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .overlay(
                    Circle()
                        .fill(showRipple ? Color.white.opacity(0.5): Color.white.opacity(0))
                        .frame(width: max(scale.width, scale.height),
                               height: max(scale.width, scale.height))
                        .scaleEffect(showRipple ? 2 : 0)
                        .opacity(showRipple ? 0 : 1)
                        .animation(.easeOut(duration: 0.6), value: showRipple)
                )
        }
    }
}

struct CameraCaptureButton: View
{
    @EnvironmentObject var manager : StateManager
    @State var isCapturing = false
    var body : some View
    {
        Button(action: {
            withAnimation(.easeIn(duration: 0.2))
            {
                isCapturing = true
            }
            
            manager.frameHandler.takePhoto
            {
                capturedImage in
                if let image = capturedImage {
                    UIImageWriteToSavedPhotosAlbum(UIImage(cgImage: image, scale: 1.0, orientation: .right), nil, nil, nil)
                }
                else
                {
                    print("Failed to save photo!")
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeOut(duration: 0.1)) {
                        isCapturing = false
                    }
                }
            }
        })
        {
            ZStack {
                Circle()
                    .stroke(Color.white, lineWidth: 5)
                    .frame(width: 70, height: 70)
                Circle()
                    .frame(width: isCapturing ? 30 : 50, height: isCapturing ? 30 : 50)
                    .opacity(isCapturing ? 0.5 : 1)
            }
        }
    }
}

struct PhotoLibraryButton : View
{
    @State var photoLibraryHandler = PhotoLibraryHandler()
    @State private var showingAlbum = false
    var body : some View
    {
        Button(action: {
            showingAlbum = true
        })
        {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.white, lineWidth: 3)
                .background(Color.clear)
                .overlay(
                    Group {
                        if let image = photoLibraryHandler.latestImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Text("📷")
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                )
                .frame(width: 40, height: 40)
        }
        .photosPicker(isPresented: $showingAlbum, selection: .constant(nil))
    }
}

struct TopToolbarView: View {
    @EnvironmentObject var manager : StateManager
    
    var body: some View {
        HStack(spacing: 50) {
            
            OptionButton(action: {
                manager.toggleTorch()
            })
            {
                switch manager.torchMode {
                case .off:
                    Image(systemName: "flashlight.slash")
                case .on:
                    Image(systemName: "flashlight.on.fill")
                case .notSupported:
                    Image(systemName: "flashlight.slash")
                        .opacity(0.5)
                        .foregroundColor(Color.red)
                }
            }
            OptionButton(action: {
                manager.useLidar = !manager.useLidar
            })
            {
                Image(systemName: "dots.and.line.vertical.and.cursorarrow.rectangle")
            }
            OptionButton(action: {
                manager.useObjectSegmentation = !manager.useObjectSegmentation
                if !manager.useObjectSegmentation
                {
                    manager.frameHandler.detections = []
                }
            })
            {
                Image(systemName: "squareshape.controlhandles.on.squareshape.controlhandles")
            }
            OptionButton(action: {})
            {
                Image(systemName: "slider.horizontal.3")
            }
        }
        .font(.system(size: 24, weight: .heavy))
        .safeAreaPadding(.top)
        .frame(maxWidth: .infinity, minHeight: 60)
        .padding(.bottom, 20)
        .foregroundColor(.white)
        .background(.greyOne)
    
    }
}

struct NotificationView: View {
    let content : String
    
    var body: some View {
        HStack {
            Image(systemName: "moon.stars")
            Text(content)
                .font(.system(.body, design: .monospaced))
                .bold()
            Spacer()
            Image(systemName: "chevron.right")
        }
        .padding()
        .background(Color.greyOne)
        .border(Color.white, width: 3)
        .font(.system(size: 18, weight: .medium))
        .foregroundColor(.white)
        .cornerRadius(10)
        .padding(.horizontal)
    }
}

struct ErrorView<ButtonContent : View> : View
{
    let title : String
    let message : String
    let action: () -> Void
    
    @ViewBuilder let actionBuilder: () -> ButtonContent
    
    var body: some View
    {
        ZStack
        {
            Rectangle()
                .fill(.black)
                .opacity(0.7)
                .blur(radius: 1)
                .ignoresSafeArea()
            
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48, weight: .heavy))

                Text(title)
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)
                OptionButton(action: self.action)
                {
                    actionBuilder()
                }
            }
            .foregroundColor(.white)
            .padding(24)
            .frame(maxWidth: 320)
            .background(Color.greyOne)
            .cornerRadius(20)
            .shadow(radius: 10, y: 4)
            .padding(.horizontal, 20)
            .ignoresSafeArea()
        }
    }
}

struct BottomToolbarView: View {
    @EnvironmentObject var manager: StateManager
    @Binding var settingsVisible : Bool
    var body: some View {
        ZStack
        {
            HStack(spacing: 30) {
                PhotoLibraryButton()
                
                OptionButton(action: {
                    settingsVisible = !settingsVisible
                })
                {
                    Image(systemName: "gearshape")
                }
                
                Spacer()
                
                OptionButton(action: {manager.frameHandler.flipCamera()})
                {
                    Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90.camera.fill")
                }
            }
            .padding(.horizontal, 30)
            CameraCaptureButton()
        }
        .font(.system(size: 24, weight: .heavy))
        .padding(.vertical, 25)
        .foregroundColor(.white)
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(Color.greyOne)
    }
}

struct MainCameraView: View {
    @EnvironmentObject var manager : StateManager
    @State var settingsVisible : Bool = false
    
    var body: some View {
        ZStack
        {
            SettingsView(isVisible: $settingsVisible)
                .zIndex(10)
            
            Color.greyOne
                .ignoresSafeArea()
                .zIndex(-1)
            
            if (manager.error != nil)
            {
            
                ErrorView(title: "Application Error", message: manager.error?.localizedDescription ?? "Unexpected Error Occured", action: {
                    fatalError(manager.error?.localizedDescription ?? "Unexpected Error Occured")
                })
                {
                    Image(systemName: "arrow.trianglehead.2.clockwise")
                }.zIndex(3)
            }
            
            
            VStack(spacing: 0) {
                TopToolbarView()
                    .padding(.top, 50)
                ZStack(alignment: .top)
                {
                    VStack
                    {
                        ForEach(Array(manager.notifications.enumerated()), id: \.offset) {
                            index, notification in
                            NotificationView(content: notification.content)
                                .padding(.top, 10)
                                .frame(maxWidth: .infinity)
                                .onTapGesture {
                                    _ = manager.popNotification(id: notification.id)
                                }
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                    .zIndex(3)
                        
                    if manager.useLidar
                    {
                        DepthDotView()
                    }
                    else
                    {
                        CameraFrameView()
                    }
                  
                }
                Spacer()
                BottomToolbarView(settingsVisible: $settingsVisible)
                    .padding(.bottom, 20)
            }
            .ignoresSafeArea()
        }
    }
}

#Preview
{
    ContentView()
}
