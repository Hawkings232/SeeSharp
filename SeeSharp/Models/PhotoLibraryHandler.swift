//
//  PhotoLibraryHandler.swift
//  SeeSharp
//
//  Created by Eddie Zhou on 6/15/25.
//

import SwiftUI
import Photos
import PhotosUI

class PhotoLibraryHandler : NSObject, ObservableObject, PHPhotoLibraryChangeObserver
{
    @Published var latestImage : UIImage?
    
    override init()
    {
        super.init()
        PHPhotoLibrary.shared().register(self)
        self.requestPermission()
    }
    
    deinit
    {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    func requestPermission()
    {
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else { return }
            self.fetchLatestPhoto()
        }
    }
    
    func fetchLatestPhoto()
    {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 1
        
        let fetchResult = PHAsset.fetchAssets(with: options)
        guard let asset = fetchResult.firstObject else { return }
        
        let manager = PHImageManager.default()
        let size = CGSize(width: 80, height: 80)
        let imageOptions = PHImageRequestOptions()
        imageOptions.deliveryMode = .highQualityFormat
        imageOptions.isSynchronous = false
        
        manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: imageOptions)
        {
            img, _ in
            DispatchQueue.main.async
            {
                self.latestImage = img
            }
        }
    }
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async
        {
            self.fetchLatestPhoto()
        }
    }
}
