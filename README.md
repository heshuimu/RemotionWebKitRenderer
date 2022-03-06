# RemotionWebKitRenderer
Using WKWebView as a faster alternative for rendering [Remotion](https://github.com/remotion-dev/remotion) compositions on macOS

This is a hack project I put together. I found that using Remotion's own built-in rendering with Chromium instances, the rendering speed was not up to frame rate, and due to memory usage, I can only enable `--concurrency 2`.

With this tool displaying a WKWebView on screen, using 1 view alone significantly reduced rendering time. For example, on my MacBook Pro (Late 2019, Intel i9, Radeon 5500M), rendering using provided Chromium takes 83 seconds plus 4 seconds of encoding time. My tool took 20 seconds, doing both rendering and encoding at the same time. 

https://www.youtube.com/watch?v=luR654eyqJo

One bonus is that my tool skips writing rendered image to disk by encoding the capture directly with AVFoundation features, which should perform better for longer videos and have better capture quality before encoding (Remotion writes the capture as JPEG). 
