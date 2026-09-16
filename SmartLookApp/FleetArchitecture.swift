import Foundation

/// Fleet-level routing shared by the iOS location overlay and training flow.
/// Only B777 currently has operational catalog data; the other families are
/// explicit placeholders so they can be populated independently later.
enum MVDAircraftFamily: String, Codable, CaseIterable {
    case b777
    case b787
    case b737
    case a320
    case a330
    case unknown

    static func resolve(model: String) -> MVDAircraftFamily {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "_", with: "-")

        if normalized.hasPrefix("B777") { return .b777 }
        if normalized.hasPrefix("B787") { return .b787 }
        if normalized.hasPrefix("B737") { return .b737 }
        if normalized.hasPrefix("A319") || normalized.hasPrefix("A320") || normalized.hasPrefix("A321") {
            return .a320
        }
        if normalized.hasPrefix("A330") { return .a330 }
        return .unknown
    }
}

enum MVDLocationDomain: String, Codable, CaseIterable {
    case none
    case seat
    case galley
    case lavatory
    case flightDeck
    case crewStation
    case stowageBin
}

struct MVDLocationOption: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let pnr: String
    let cmmNumbers: [String]
    let noseApplicability: String?

    init(
        id: String,
        name: String,
        pnr: String = "",
        cmmNumbers: [String] = [],
        noseApplicability: String? = nil
    ) {
        self.id = id
        self.name = name
        self.pnr = pnr
        self.cmmNumbers = cmmNumbers
        self.noseApplicability = noseApplicability
    }

    /// The technician sees the physical name first; CMMs remain visible to
    /// disambiguate duplicate crew-seat variants.
    var pickerTitle: String {
        guard !cmmNumbers.isEmpty else { return name }
        return "\(name) • CMM \(cmmNumbers.joined(separator: " + "))"
    }

    var detail: String {
        var values: [String] = []
        if !pnr.isEmpty { values.append("PNR \(pnr)") }
        if !cmmNumbers.isEmpty { values.append("CMM \(cmmNumbers.joined(separator: " + "))") }
        if let noseApplicability, !noseApplicability.isEmpty { values.append("NOSE \(noseApplicability)") }
        return values.joined(separator: " • ")
    }
}

struct MVDLocationCatalog: Codable {
    let galleys: [MVDLocationOption]
    let lavatories: [MVDLocationOption]
    let flightDeck: [MVDLocationOption]
    let crewStations: [MVDLocationOption]
    let stowageBins: [MVDLocationOption]

    static let empty = MVDLocationCatalog(
        galleys: [],
        lavatories: [],
        flightDeck: [],
        crewStations: [],
        stowageBins: []
    )
}

struct MVDSeatResolution: Codable, Hashable {
    let seatNumber: String
    let cabinClass: String
    let cmmNumber: String
}

struct MVDLocationSelection: Codable, Hashable, Identifiable {
    let domain: MVDLocationDomain
    let location: String
    let label: String
    let cmmNumbers: [String]

    var id: String {
        "\(domain.rawValue)-\(location)-\(cmmNumbers.joined(separator: ","))"
    }

    var cmmDisplay: String {
        cmmNumbers.isEmpty ? "CMM pendiente de applicability" : cmmNumbers.joined(separator: " + ")
    }

    var trainingFolderNames: [String] {
        cmmNumbers.map { "cmm\($0)" }
    }
}

enum MVDTrainingPaths {
    static var applicationSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var newTrainingsRoot: URL {
        applicationSupport.appendingPathComponent("New Trainings", isDirectory: true)
    }

    static func aircraftFolder(model: String, customer: String, nose: String) -> URL {
        applicationSupport
            .appendingPathComponent("TrainingData", isDirectory: true)
            .appendingPathComponent(model, isDirectory: true)
            .appendingPathComponent(customer, isDirectory: true)
            .appendingPathComponent(nose, isDirectory: true)
    }

    static func pendingAircraftFolder(model: String, customer: String, manufacturer: String = "Boeing") -> URL {
        newTrainingsRoot
            .appendingPathComponent(customer, isDirectory: true)
            .appendingPathComponent(manufacturer, isDirectory: true)
            .appendingPathComponent(model, isDirectory: true)
    }

    static func cmmFolder(model: String, customer: String, nose: String, cmm: String) -> URL {
        aircraftFolder(model: model, customer: customer, nose: nose)
            .appendingPathComponent("CMM", isDirectory: true)
            .appendingPathComponent("cmm\(cmm)", isDirectory: true)
    }
}

enum MVDFleetRegistry {
    static func family(for model: String) -> MVDAircraftFamily {
        MVDAircraftFamily.resolve(model: model)
    }

    static func catalog(model: String, nose: String) -> MVDLocationCatalog {
        switch family(for: model) {
        case .b777:
            return B777LocationData.catalog(model: model, nose: nose)
        case .b787, .b737, .a320, .a330, .unknown:
            return .empty
        }
    }

    static func select(
        domain: MVDLocationDomain,
        model: String,
        nose: String,
        option: MVDLocationOption? = nil,
        seatNumber: String? = nil
    ) -> MVDLocationSelection? {
        switch family(for: model) {
        case .b777:
            return B777CmmApplicability.selection(
                domain: domain,
                model: model,
                nose: nose,
                option: option,
                seatNumber: seatNumber
            )
        case .b787, .b737, .a320, .a330, .unknown:
            return nil
        }
    }
}

