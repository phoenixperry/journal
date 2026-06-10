import Foundation
import ImageIO

enum LocationExtractor {
    static func extract(from imageURL: URL) -> EntryLocation? {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        else {
            return nil
        }

        guard let latRaw = gps[kCGImagePropertyGPSLatitude] as? Double,
              let lonRaw = gps[kCGImagePropertyGPSLongitude] as? Double else {
            return nil
        }

        let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String) ?? "N"
        let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String) ?? "E"

        let lat = latRef.uppercased() == "S" ? -latRaw : latRaw
        let lon = lonRef.uppercased() == "W" ? -lonRaw : lonRaw

        return EntryLocation(latitude: lat, longitude: lon, label: nil)
    }
}
