import AppKit
import Foundation
struct Job: Decodable {
    let name: String
    let frames: [String]
    let width: Int
    let height: Int
    let output: String
}
let jobs = try JSONDecoder().decode([Job].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
func powerOfTwo(_ value: Int) -> Int { var n = 1; while n < value { n *= 2 }; return n }
for job in jobs {
    let padding = 2, cellWidth = job.width + 4, cellHeight = job.height + 4
    let columns = min(job.frames.count, 1024 / cellWidth)
    let rows = (job.frames.count + columns - 1) / columns
    let width = powerOfTwo(columns * cellWidth), height = powerOfTwo(rows * cellHeight)
    guard width <= 1024, height <= 1024,
          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Invalid atlas budget") }
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .none
    for (index, path) in job.frames.enumerated() {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width == job.width, image.height == job.height else {
            fatalError("Invalid frame: \(path)")
        }
        // Frame zero is in the bottom row in the UV coordinate system.
        let rect = CGRect(x: (index % columns) * cellWidth + padding,
                          y: (index / columns) * cellHeight + padding, width: job.width, height: job.height)
        context.draw(image, in: rect)
    }
    guard let result = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: job.output) as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("Cannot create atlas")
    }
    CGImageDestinationAddImage(destination, result, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save atlas") }
    print("\(job.name): \(job.frames.count) frames, \(width)x\(height)")
}
