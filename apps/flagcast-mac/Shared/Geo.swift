import Foundation

// Distances on the course (shared with the iPhone and iPad Manager).

func yards(_ a: GeoPoint, _ b: GeoPoint) -> Int {
    let R = 6371008.8, t = Double.pi / 180, dla = (b.lat - a.lat) * t, dlo = (b.lng - a.lng) * t
    let h = pow(sin(dla / 2), 2) + cos(a.lat * t) * cos(b.lat * t) * pow(sin(dlo / 2), 2)
    return Int((2 * R * asin(min(1, sqrt(h))) * 1.0936133).rounded())
}
func bearing(_ a: GeoPoint, _ b: GeoPoint) -> Double {
    let t = Double.pi / 180, la1 = a.lat * t, la2 = b.lat * t, dlo = (b.lng - a.lng) * t
    return (atan2(sin(dlo) * cos(la2), cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dlo)) / t + 360).truncatingRemainder(dividingBy: 360)
}
