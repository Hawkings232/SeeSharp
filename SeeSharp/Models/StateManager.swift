//
//  StateManager.swift
//  SeeSharp
//
//  Created by Eddie Zhou on 5/17/25.

import Foundation
import SwiftUI
import Combine

struct Notification : Identifiable
{
    let id = UUID()
    
    var content : String
    var duration : TimeInterval
}

enum TorchMode
{
    case off
    case on
    case notSupported
}

class StateManager: ObservableObject {
    
    // Viewmodels:
    lazy var depthHandler : DepthMapHandler = DepthMapHandler(state: self)
    lazy var frameHandler : FrameHandler = FrameHandler(state: self)
    lazy var ciContext : CIContext = CIContext()
    
    // Settings:
    @Published var useLidar: Bool {
        didSet
        {
            if self.useLidar
            {
                frameHandler.stopSession()
                depthHandler.startSession()
                self.torchMode = depthHandler.checkTorchStatus() == .notSupported ? .notSupported : .off
            }
            else
            {
                depthHandler.stopSession()
                frameHandler.startSession()
                self.torchMode = frameHandler.checkTorchStatus() == .notSupported ? .notSupported : .off
            }
            UserDefaults.standard.set(useLidar, forKey: "useLidar")
        }
    }
    
    @Published var useObjectSegmentation : Bool = false
    @Published var lidarActivationUponLimitedFeatures : Bool = false
    @Published var enabledDiagnostics : Bool = false
    
    @Published var torchMode : TorchMode = .notSupported
    
    // Application Utilities:
    
    @Published var error : ApplicationError?
    @Published var notifications : [Notification] = []
    
    

    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Set Properties
        self.useLidar = UserDefaults.standard.bool(forKey: "useLidar")
        self.useObjectSegmentation = UserDefaults.standard.bool(forKey: "useObjectSegmentation")
        self.lidarActivationUponLimitedFeatures = UserDefaults.standard.bool(forKey: "lidarActivationUponLimitedFeatures")
        self.enabledDiagnostics = UserDefaults.standard.bool(forKey: "enabledDiagnostics")
        //        self.useTorch = UserDefaults.standard.bool(forKey: "useTorch")
        
        frameHandler.$frame
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        depthHandler.$depthBuffer
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    func pushNotification(content: String, duration: TimeInterval = 4) {
        let notification = Notification(content: content, duration: duration)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7))
        {
            DispatchQueue.main.async
            {
                self.notifications.append(notification)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            _ = self.popNotification(id: notification.id)
        }
    }

//    func popNotification() -> Notification? {
//        if self.notifications.isEmpty
//        {
//            return nil
//        }
//        else
//        {
//            return withAnimation(.easeInOut(duration: 0.3))
//            {
//                self.notifications.removeLast()
//            }
//        }
//    }
    
    func popNotification(id: UUID) -> Notification?
    {
        if self.notifications.isEmpty
        {
            return nil
        }
        else
        {
            guard let idx = self.notifications.firstIndex(where: { $0.id == id }) else { return nil }
            return withAnimation(.easeInOut(duration: 0.3))
            {
                self.notifications.remove(at: idx)
            }
        }
    }
    
    func toggleTorch()
    {
        if self.useLidar && self.depthHandler.checkTorchStatus() != .notSupported
        {
            self.torchMode = self.depthHandler.toggleTorch(on: self.torchMode == .on ? .off : .on)
        }
        else if !self.useLidar && self.frameHandler.checkTorchStatus() != .notSupported
        {
            self.torchMode = self.frameHandler.toggleTorch(on: self.torchMode == .on ? .off : .on)
        }
    }
}

