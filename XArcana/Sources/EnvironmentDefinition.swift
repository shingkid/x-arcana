import Foundation
import simd

/// Environment coordinates use metres, Y for height, and X/Z for the walkable floor.
struct EnvironmentDefinition: Codable, Equatable {
    struct Point: Codable, Equatable {
        var x: Float
        var y: Float
        var z: Float
        var vector: SIMD3<Float> { SIMD3(x, y, z) }
        var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    }

    struct Bounds: Codable, Equatable {
        var minX: Float
        var maxX: Float
        var minZ: Float
        var maxZ: Float
        var isValid: Bool {
            [minX, maxX, minZ, maxZ].allSatisfy(\.isFinite) && minX < maxX && minZ < maxZ
        }
        func contains(_ point: SIMD3<Float>) -> Bool {
            (minX...maxX).contains(point.x) && (minZ...maxZ).contains(point.z)
        }
        func clamped(_ point: SIMD3<Float>) -> SIMD3<Float> {
            SIMD3(min(maxX, max(minX, point.x)), point.y, min(maxZ, max(minZ, point.z)))
        }
    }

    struct Asset: Codable, Equatable {
        var name: String
        var fileExtension: String
        var subdirectory: String
    }

    struct Camera: Codable, Equatable {
        var position: Point
        var lookAt: Point
        var horizontalFieldOfView: Double
    }

    struct Color: Codable, Equatable {
        var red: Double
        var green: Double
        var blue: Double
        var isValid: Bool { [red, green, blue].allSatisfy { $0.isFinite && (0...1).contains($0) } }
    }

    struct Light: Codable, Equatable {
        enum Kind: String, Codable { case ambient, omni }
        var kind: Kind
        var color: Color
        var intensity: Double
        var position: Point
        var attenuationStart: Double
        var attenuationEnd: Double
        var falloffExponent: Double
    }

    var id: String
    var displayName: String
    var scene: Asset
    var floorY: Float
    var movementBounds: Bounds
    var projectileBounds: Bounds
    var enemySpawns: [Point]
    var camera: Camera
    var background: Color
    var lights: [Light]

    /// These values also support isolated combat tests without a resource bundle.
    /// The bundled fantasy.json is checked against this compatibility baseline.
    static let fantasy = EnvironmentDefinition(
        id: "fantasy", displayName: "Fantasy hall",
        scene: Asset(name: "FantasyRoom", fileExtension: "usdz", subdirectory: "Fantasy"), floorY: 0,
        movementBounds: Bounds(minX: -2.2, maxX: 2.2, minZ: -4.8, maxZ: 3.9),
        projectileBounds: Bounds(minX: -5, maxX: 5, minZ: -7, maxZ: 6),
        enemySpawns: [
            Point(x: -1.8, y: 0, z: -1.8), Point(x: 0.4, y: 0, z: -1.5),
            Point(x: 1.9, y: 0, z: -2.8), Point(x: -0.7, y: 0, z: -2.9),
            Point(x: -2, y: 0, z: -4.3), Point(x: 0.8, y: 0, z: -4.5),
            Point(x: -0.3, y: 0, z: -4.4), Point(x: 2.1, y: 0, z: -4.5),
        ],
        camera: Camera(
            position: Point(x: 0, y: 1.65, z: 4.8), lookAt: Point(x: 0, y: 1.65, z: -2.6),
            horizontalFieldOfView: 74),
        background: Color(red: 0.10, green: 0.12, blue: 0.15),
        lights: [
            Light(
                kind: .ambient, color: Color(red: 0.86, green: 0.89, blue: 1), intensity: 55,
                position: Point(x: 0, y: 0, z: 0), attenuationStart: 0.2, attenuationEnd: 12, falloffExponent: 2),
            Light(
                kind: .omni, color: Color(red: 1, green: 0.88, blue: 0.74), intensity: 120,
                position: Point(x: 0, y: 3, z: 3), attenuationStart: 0.2, attenuationEnd: 12, falloffExponent: 2),
            Light(
                kind: .omni, color: Color(red: 0.74, green: 0.84, blue: 1), intensity: 90,
                position: Point(x: 0, y: 3, z: -4), attenuationStart: 0.2, attenuationEnd: 12, falloffExponent: 2),
        ])

    func validated() throws -> Self {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw EnvironmentError.invalidConfiguration(message) }
        }
        try require(
            !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            "An environment needs an ID and display name.")
        let components = [scene.name, scene.fileExtension] + scene.subdirectory.components(separatedBy: "/")
        try require(
            components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") && !$0.contains("\\") },
            "The scene asset path is invalid.")
        try require(floorY.isFinite, "The floor height must be finite.")
        try require(
            movementBounds.isValid && projectileBounds.isValid, "Environment bounds must be finite and ordered.")
        try require(
            projectileBounds.contains(SIMD3(movementBounds.minX, 0, movementBounds.minZ))
                && projectileBounds.contains(SIMD3(movementBounds.maxX, 0, movementBounds.maxZ)),
            "Projectile bounds must contain the walkable floor.")
        try require(
            !enemySpawns.isEmpty
                && enemySpawns.allSatisfy {
                    $0.isFinite && $0.y == floorY && movementBounds.contains($0.vector)
                }, "Enemy spawns must be on the floor and inside movement bounds.")
        try require(
            camera.position.isFinite && camera.lookAt.isFinite && camera.position.y > floorY
                && simd_distance_squared(camera.position.vector, camera.lookAt.vector) > 0.0001
                && camera.horizontalFieldOfView.isFinite && (1..<180).contains(camera.horizontalFieldOfView),
            "The camera needs a valid position, look target, and field of view.")
        try require(background.isValid, "Background color channels must be between zero and one.")
        try require(
            !lights.isEmpty
                && lights.allSatisfy {
                    $0.color.isValid && $0.position.isFinite && $0.intensity.isFinite && $0.intensity >= 0
                        && $0.attenuationStart.isFinite && $0.attenuationStart >= 0 && $0.attenuationEnd.isFinite
                        && $0.attenuationEnd > $0.attenuationStart && $0.falloffExponent.isFinite
                        && $0.falloffExponent >= 0
                }, "Environment lighting parameters are invalid.")
        return self
    }

    static func configuredName(bundle: Bundle = .main) throws -> String {
        guard let value = bundle.object(forInfoDictionaryKey: "XArcanaEnvironment") else { return "fantasy" }
        guard let name = value as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EnvironmentError.invalidConfiguration("XArcanaEnvironment must name a bundled environment JSON file.")
        }
        return name
    }

    static func load(named name: String = "fantasy", bundle: Bundle = .main) throws -> Self {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\") else {
            throw EnvironmentError.invalidConfiguration(
                "The environment name must be a filename without its extension.")
        }
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Environments") else {
            throw EnvironmentError.missingConfiguration(name)
        }
        return try load(from: url)
    }

    static func load(from url: URL) throws -> Self {
        do { return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)).validated() } catch let error
            as EnvironmentError
        { throw error } catch {
            throw EnvironmentError.invalidConfiguration("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func sceneURL(bundle: Bundle = .main) throws -> URL {
        guard
            let url = bundle.url(
                forResource: scene.name, withExtension: scene.fileExtension, subdirectory: scene.subdirectory)
        else {
            throw EnvironmentError.missingAsset("\(scene.subdirectory)/\(scene.name).\(scene.fileExtension)")
        }
        return url
    }
}

enum EnvironmentError: LocalizedError {
    case missingConfiguration(String)
    case invalidConfiguration(String)
    case missingAsset(String)
    case invalidAsset(String, String)

    var errorDescription: String? {
        switch self {
        case .missingConfiguration(let name): return "Environment configuration is missing: Environments/\(name).json."
        case .invalidConfiguration(let reason): return "Environment configuration is invalid: \(reason)"
        case .missingAsset(let path): return "Environment scene asset is missing: \(path)."
        case .invalidAsset(let path, let reason): return "Environment scene asset could not load: \(path). \(reason)"
        }
    }
}
