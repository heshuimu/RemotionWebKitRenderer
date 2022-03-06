//
//  RemotionRendererApp.swift
//  RemotionRenderer
//
//  Created by heshuimu on 3/5/22.
//

import Foundation
import AppKit
import WebKit
import AVFoundation
import ArgumentParser

struct RemotionRenderer: ParsableCommand {
    enum Error : Swift.Error {
        case outputFileExist
        case inputFileNotExist
    }
    
    @Option
    var width: Int
    
    @Option
    var height: Int
    
    @Option
    var startFrame: Int
    
    @Option
    var endFrame: Int
    
    @Option
    var frameRate: Int
    
    @Option
    var compositionName: String
    
    @Option
    var outputFile: String
    
    @Argument
    var inputFile: String
    
    func validate() throws {
        if FileManager.default.fileExists(atPath: outputFile) {
            throw Error.outputFileExist
        }
        
        if !FileManager.default.fileExists(atPath: inputFile) {
            throw Error.inputFileNotExist
        }
    }
}

let rendererSettings = RemotionRenderer.parseOrExit()
let app = NSApplication.shared

class WebViewCaptureDelegate : NSObject, WKNavigationDelegate {
    private let operationQueue = DispatchQueue(label: "VideoWriter")
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task {
            await waitUntilWindowReady(webView)
            
            // Video Writer Configuration
            let movieURL = URL(fileURLWithPath: rendererSettings.outputFile)
            let outputSettings: [String : Any] = [
                AVVideoWidthKey : NSNumber(value: rendererSettings.width),
                AVVideoHeightKey : NSNumber(value: rendererSettings.height),
                AVVideoScalingModeKey : AVVideoScalingModeResizeAspect
            ]
            let assistant = AVOutputSettingsAssistant(preset: .preset1920x1080)!
            var recommendedOutputSettings = assistant.videoSettings ?? [:]
            recommendedOutputSettings.merge(outputSettings) { current, new in new }
            
            // Initialize video writer and then start
            let videoWriter = try! VideoWriter(movieURL: movieURL, outputSettings: recommendedOutputSettings, fileType: .mp4)
            videoWriter.startWriting()
            
            // Loop over frames and push them to render
            for i in rendererSettings.startFrame...rendererSettings.endFrame {
                // Render a frame
                await webView.evaluateJavaScript("remotion_setFrame(\(i))", completionHandler: nil)
                await waitUntilWindowReady(webView)
                
                // Capture the frame
                let image = try! await webView.takeSnapshot(configuration: nil)
                
                // Render it to the video and then adavance
                operationQueue.async {
                    videoWriter.writeFrame { cgContext in
                        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
                        cgContext.draw(cgImage, in: .init(x: 0, y: 0, width: rendererSettings.width, height: rendererSettings.height))
                        
                        return CMTime(value: CMTimeValue(i), timescale: 30)
                    }
                }
            }
            
            operationQueue.async {
                videoWriter.finish {
                    DispatchQueue.main.async {
                        app.terminate(nil)
                    }
                }
            }
        }
    }

    @MainActor
    private func waitUntilWindowReady(_ webView: WKWebView) async {
        while(true) {
            let result = try! await webView.evaluateJavaScript("window.ready === true")
            if let number = result as? NSNumber, number.boolValue == true {
                return
            }
            
            try! await Task.sleep(nanoseconds: 1_000_000)
        }
    }
}

//Create window
let window = NSWindow(
    contentRect: .init(x: 0, y: 0, width: 100, height: 100),
    styleMask: .borderless,
    backing: .buffered,
    defer: false
)

// Make window proper scale and visible
let scaleFactor = window.backingScaleFactor
window.setFrame(.init(x: 0, y: 0, width: CGFloat(rendererSettings.width) / scaleFactor, height: CGFloat(rendererSettings.height) / scaleFactor), display: true)
window.makeKeyAndOrderFront(app)

// Create web view
let webView = WKWebView(frame: window.contentView!.bounds)
window.contentView!.addSubview(webView)

// Register renderer delegate
let webDelegate = WebViewCaptureDelegate()
webView.navigationDelegate = webDelegate

let fileURL = URL(fileURLWithPath: rendererSettings.inputFile)
var components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false)!
components.queryItems = [.init(name: "composition", value: rendererSettings.compositionName)]

webView.load(URLRequest(url: components.url!))
webView.configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
webView.pageZoom = 1 / window.backingScaleFactor

app.run()
