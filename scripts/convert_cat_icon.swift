import Foundation
import AppKit

let srcPath = "/Users/yu./.gemini/antigravity/brain/d7245b36-d24e-4576-9b4a-c9c2486467a7/mecha_cat_app_icon_1785645531032.jpg"
guard let image = NSImage(contentsOfFile: srcPath) else {
    print("Failed to load \(srcPath)")
    exit(1)
}

func saveExactPNG(image: NSImage, pixelSize: Int, targetPath: String) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return }
    
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize), from: NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height), operation: .copy, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
    
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: targetPath))
        print("Generated Exact PNG (\(pixelSize)x\(pixelSize)): \(targetPath)")
    }
}

let iosDir = "/Users/yu./Desktop/program/claude-watch/ios/WatchApprove/Assets.xcassets/AppIcon.appiconset"
let watchDir = "/Users/yu./Desktop/program/claude-watch/ios/WatchApproveWatch/Assets.xcassets/AppIcon.appiconset"

try? FileManager.default.removeItem(atPath: iosDir)
try? FileManager.default.removeItem(atPath: watchDir)

try? FileManager.default.createDirectory(atPath: iosDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(atPath: watchDir, withIntermediateDirectories: true)

// Save iOS icons
saveExactPNG(image: image, pixelSize: 1024, targetPath: iosDir + "/icon-1024.png")
saveExactPNG(image: image, pixelSize: 180, targetPath: iosDir + "/icon-180.png")
saveExactPNG(image: image, pixelSize: 120, targetPath: iosDir + "/icon-120.png")

// Save watchOS icons
saveExactPNG(image: image, pixelSize: 1024, targetPath: watchDir + "/icon-1024.png")
saveExactPNG(image: image, pixelSize: 100, targetPath: watchDir + "/icon-100.png")
saveExactPNG(image: image, pixelSize: 92, targetPath: watchDir + "/icon-92.png")
saveExactPNG(image: image, pixelSize: 88, targetPath: watchDir + "/icon-88.png")
saveExactPNG(image: image, pixelSize: 80, targetPath: watchDir + "/icon-80.png")
saveExactPNG(image: image, pixelSize: 66, targetPath: watchDir + "/icon-66.png")
saveExactPNG(image: image, pixelSize: 58, targetPath: watchDir + "/icon-58.png")
saveExactPNG(image: image, pixelSize: 55, targetPath: watchDir + "/icon-55.png")
saveExactPNG(image: image, pixelSize: 48, targetPath: watchDir + "/icon-48.png")

// Write iOS Contents.json
let iosContentsJson = """
{
  "images": [
    {
      "filename": "icon-120.png",
      "idiom": "iphone",
      "scale": "2x",
      "size": "60x60"
    },
    {
      "filename": "icon-180.png",
      "idiom": "iphone",
      "scale": "3x",
      "size": "60x60"
    },
    {
      "filename": "icon-1024.png",
      "idiom": "ios-marketing",
      "scale": "1x",
      "size": "1024x1024"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
"""

// Write watchOS Contents.json using standard idiom: "watch"
let watchContentsJson = """
{
  "images": [
    {
      "filename": "icon-48.png",
      "idiom": "watch",
      "role": "notificationCenter",
      "scale": "2x",
      "size": "24x24",
      "subtype": "38mm"
    },
    {
      "filename": "icon-55.png",
      "idiom": "watch",
      "role": "notificationCenter",
      "scale": "2x",
      "size": "27.5x27.5",
      "subtype": "42mm"
    },
    {
      "filename": "icon-58.png",
      "idiom": "watch",
      "role": "companionSettings",
      "scale": "2x",
      "size": "29x29"
    },
    {
      "filename": "icon-66.png",
      "idiom": "watch",
      "role": "notificationCenter",
      "scale": "2x",
      "size": "33x33",
      "subtype": "45mm"
    },
    {
      "filename": "icon-80.png",
      "idiom": "watch",
      "role": "appLauncher",
      "scale": "2x",
      "size": "40x40",
      "subtype": "38mm"
    },
    {
      "filename": "icon-88.png",
      "idiom": "watch",
      "role": "appLauncher",
      "scale": "2x",
      "size": "44x44",
      "subtype": "40mm"
    },
    {
      "filename": "icon-92.png",
      "idiom": "watch",
      "role": "appLauncher",
      "scale": "2x",
      "size": "46x46",
      "subtype": "41mm"
    },
    {
      "filename": "icon-100.png",
      "idiom": "watch",
      "role": "appLauncher",
      "scale": "2x",
      "size": "50x50",
      "subtype": "44mm"
    },
    {
      "filename": "icon-1024.png",
      "idiom": "watch-marketing",
      "scale": "1x",
      "size": "1024x1024"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
"""

try? iosContentsJson.write(toFile: iosDir + "/Contents.json", atomically: true, encoding: .utf8)
try? watchContentsJson.write(toFile: watchDir + "/Contents.json", atomically: true, encoding: .utf8)

print("Standard watchOS App Icons and Contents.json generated cleanly!")
