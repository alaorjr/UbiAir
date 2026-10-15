#!/usr/bin/env swift
import AppKit
import CoreGraphics
import ImageIO
import Foundation

let scriptDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let projectDirectory = scriptDirectory.deletingLastPathComponent()
let outputDirectory = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    : projectDirectory.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let sourceURL = CommandLine.arguments.count > 2
    ? URL(fileURLWithPath: CommandLine.arguments[2])
    : projectDirectory.appendingPathComponent("Resources/AppIcon-source.png")

struct IconImage {
    let filename: String
    let pointSize: Int
    let scale: Int
    var pixels: Int { pointSize * scale }
}

let images: [IconImage] = [
    .init(filename: "icon_16x16.png", pointSize: 16, scale: 1),
    .init(filename: "icon_16x16@2x.png", pointSize: 16, scale: 2),
    .init(filename: "icon_32x32.png", pointSize: 32, scale: 1),
    .init(filename: "icon_32x32@2x.png", pointSize: 32, scale: 2),
    .init(filename: "icon_128x128.png", pointSize: 128, scale: 1),
    .init(filename: "icon_128x128@2x.png", pointSize: 128, scale: 2),
    .init(filename: "icon_256x256.png", pointSize: 256, scale: 1),
    .init(filename: "icon_256x256@2x.png", pointSize: 256, scale: 2),
    .init(filename: "icon_512x512.png", pointSize: 512, scale: 1),
    .init(filename: "icon_512x512@2x.png", pointSize: 512, scale: 2)
]

func fail(_ message: String) -> Never {
    fputs("Erro: \(message)\n", stderr)
    exit(EXIT_FAILURE)
}

guard FileManager.default.fileExists(atPath: sourceURL.path) else {
    fail("matriz de origem não encontrada em \(sourceURL.path)")
}
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let input = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("não foi possível decodificar a matriz \(sourceURL.path)")
}
guard input.width == input.height else {
    fail("a matriz deve ser quadrada; recebeu \(input.width)×\(input.height)")
}
guard input.width >= 1024 else {
    fail("a matriz deve ter ao menos 1024×1024 pixels; recebeu \(input.width)×\(input.height)")
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
guard let rgbaContext = CGContext(data: nil, width: input.width, height: input.height,
                                  bitsPerComponent: 8, bytesPerRow: input.width * 4,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                    CGBitmapInfo.byteOrder32Big.rawValue) else {
    fail("não foi possível criar superfície RGBA sRGB")
}
rgbaContext.interpolationQuality = .high
rgbaContext.draw(input, in: CGRect(x: 0, y: 0, width: input.width, height: input.height))
guard let normalizedSource = rgbaContext.makeImage() else {
    fail("não foi possível converter a matriz para RGBA sRGB")
}

do {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
} catch {
    fail("não foi possível criar \(outputDirectory.path): \(error.localizedDescription)")
}

for image in images {
    guard let bitmap = CGContext(data: nil, width: image.pixels, height: image.pixels,
                                 bitsPerComponent: 8, bytesPerRow: image.pixels * 4,
                                 space: colorSpace,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                    CGBitmapInfo.byteOrder32Big.rawValue) else {
        fail("não foi possível criar imagem de \(image.pixels)×\(image.pixels)")
    }
    bitmap.interpolationQuality = .high
    bitmap.draw(normalizedSource, in: CGRect(x: 0, y: 0, width: image.pixels, height: image.pixels))
    guard let rendered = bitmap.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            outputDirectory.appendingPathComponent(image.filename) as CFURL,
            "public.png" as CFString, 1, nil) else {
        fail("não foi possível iniciar a gravação de \(image.filename)")
    }
    CGImageDestinationAddImage(destination, rendered, nil)
    guard CGImageDestinationFinalize(destination) else {
        fail("falha ao gravar \(image.filename)")
    }
}

let catalogImages = images.map { image in
    "    { \"filename\" : \"\(image.filename)\", \"idiom\" : \"mac\", \"scale\" : \"\(image.scale)x\", \"size\" : \"\(image.pointSize)x\(image.pointSize)\" }"
}.joined(separator: ",\n")
let contents = """
{
  "images" : [
\(catalogImages)
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
do {
    try (contents + "\n").write(to: outputDirectory.appendingPathComponent("Contents.json"),
                       atomically: true, encoding: .utf8)
} catch {
    fail("não foi possível gravar Contents.json: \(error.localizedDescription)")
}

print("Exportados \(images.count) PNGs do catálogo a partir de \(sourceURL.path) para \(outputDirectory.path)")
