//
//  WebViewRendererDelegate.swift
//  RemotionRenderer
//
//  Created by heshuimu on 3/5/22.
//

import Foundation
import AVFoundation

class VideoWriter {
    enum Failure: Error {
        case initError(reason: String)
    }
    
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let pixelBufferAdapter: AVAssetWriterInputPixelBufferAdaptor
    
    private let videoWidth: Int
    private let videoHeight: Int
    
    init(movieURL: URL, outputSettings: [String : Any], fileType: AVFileType) throws {
        assetWriter = try .init(url: movieURL, fileType: fileType)
        
        guard let width = outputSettings[AVVideoWidthKey] as? NSNumber, let height = outputSettings[AVVideoHeightKey] as? NSNumber else {
            throw Failure.initError(reason: "Width or height is not specified in the output settings")
        }
        
        videoWidth = width.intValue
        videoHeight = height.intValue
        
        videoInput = .init(mediaType: .video, outputSettings: outputSettings)
        
        guard assetWriter.canAdd(videoInput) else {
            throw Failure.initError(reason: "Unable to add video input to asset writer. It could be that the configuration does not support the file type")
        }
        
        assetWriter.add(videoInput)
        
        let pixelBufferAttributes: [String : Any] = [
            kCVPixelBufferPixelFormatTypeKey as String : NSNumber(value: kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String : width,
            kCVPixelBufferHeightKey as String : height,
            kCVPixelBufferCGImageCompatibilityKey as String : kCFBooleanTrue!,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String : kCFBooleanTrue!
        ]

        pixelBufferAdapter = .init(assetWriterInput: videoInput, sourcePixelBufferAttributes: pixelBufferAttributes)
    }
    
    
    func startWriting() {
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: CMTime.zero)
    }
    
    func writeFrame(renderOperation: (CGContext) -> CMTime) {
        guard let pixelBufferPool = pixelBufferAdapter.pixelBufferPool else {
            fatalError("Should call start first before writing videoFrame")
        }
        
        var pixelBuffer: CVPixelBuffer? = nil
        CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBuffer)
        
        guard let pixelBuffer = pixelBuffer else {
            fatalError("Failed to get pixel buffer for rendering")
        }
        
        guard kCVReturnSuccess == CVPixelBufferLockBaseAddress(pixelBuffer, []) else {
            fatalError("Failed to lock pixel buffer address for rendering")
        }
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }
        
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let alphaInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer),
                                      width: videoWidth,
                                      height: videoHeight,
                                      bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                                      space: colorSpace,
                                      bitmapInfo: alphaInfo)
        else {
            fatalError("Failed to create context")
        }
        
        let time = renderOperation(context)
        
        pixelBufferAdapter.append(pixelBuffer, withPresentationTime: time)
    }
    
    func finish(completionHandler: (() -> ())? = nil) {
        videoInput.markAsFinished()
        assetWriter.finishWriting(completionHandler: completionHandler ?? {})
    }
}
