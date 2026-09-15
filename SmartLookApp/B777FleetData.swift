import Foundation

/// B777-200 and B777-300 location catalogs.
/// Galley Standard Practices is intentionally part of each galley selection,
/// not a separate selectable field.
enum B777LocationData {
    private static let b777300Noses: Set<String> = [
        "7LA", "7LB", "7LC", "7LD", "7LE", "7LF", "7LG", "7LH",
        "7LJ", "7LK", "7LL", "7LM", "7LN", "7LP", "7LR", "7LS",
        "7LT", "7LU", "7LV", "7LW"
    ]

    private static let b777200Group1Noses: Set<String> = [
        "7AA", "7AD", "7AE", "7AM", "AN", "AS", "AV", "7AN", "7AS", "7AV", "7BD", "7BG",
        "7BK", "7BL", "7BN", "7BR", "7BS", "7BU", "7BV", "7BW", "7BY", "7CC"
    ]

    private static let b777200Group2Noses: Set<String> = [
        "7AB", "7AC", "7AF", "7AG", "7AH", "7AJ", "7AK", "7AL", "7AP",
        "7AR", "7AT", "7AU", "7AW", "7AX", "7AY", "7BA", "7BB", "7BC",
        "7BE", "7BF", "7BH", "7BJ", "7BM", "7BP", "7BT", "BX", "7BX", "7CA", "7CB"
    ]

    static func catalog(model: String, nose: String) -> MVDLocationCatalog {
        let normalizedModel = normalize(model)
        if normalizedModel.hasPrefix("B777-200") {
            return b777200Catalog
        }
        if normalizedModel.hasPrefix("B777-300") {
            return b777300Catalog(nose: normalize(nose))
        }
        return .empty
    }

    private static let b777200Catalog = MVDLocationCatalog(
        galleys: [
            galley("F1/F3", pnr: "1008G11A00000", cmm: "25-02-42"),
            galley("F5", pnr: "1008G2A00000", cmm: "25-02-42"),
            galley("M1", pnr: "1008G21A00000", cmm: "25-02-42"),
            galley("M2", pnr: "1008G22A00000", cmm: "25-02-42"),
            galley("M3", pnr: "1008G31A00000", cmm: "25-02-42"),
            galley("MS1", pnr: "1008G23A00000", cmm: "25-02-42"),
            galley("MS2", pnr: "1008G24A00000", cmm: "25-02-42"),
            galley("A1", pnr: "1008G41A00000", cmm: "25-02-42"),
            galley("A2", pnr: "1008G41A00000", cmm: "25-02-42"),
            galley("A3", pnr: "1008G41A00000", cmm: "25-02-42"),
            galley("A4", pnr: "1008G42A00000", cmm: "25-02-42"),
            galley("G4", pnr: "1067G21A00000", cmm: "25-06-58"),
            galley("G5", pnr: "1067G22A00000", cmm: "25-06-58"),
            galley("CEILING G4/G5", pnr: "1067G29A00000", cmm: "25-06-58"),
            galley("G10", pnr: "1067G42A00000", cmm: "25-06-58")
        ].map { $0.withStandardGalleyPractice() },
        lavatories: [
            lavatory("1A-L", cmm: "25-45-80"),
            lavatory("2F-1L", cmm: "25-45-80"),
            lavatory("2F-1R", cmm: "25-45-80"),
            lavatory("3F-2R", cmm: "25-45-80"),
            lavatory("3F-1L", cmm: "25-45-81"),
            lavatory("3F-1R", cmm: "25-45-81"),
            lavatory("4F-L", cmm: "25-45-81"),
            lavatory("4F-R", cmm: "25-45-81")
        ],
        flightDeck: flightDeckOptions,
        crewStations: b777200CrewStations,
        stowageBins: sharedStowageBins
    )

    private static func b777300Catalog(nose: String) -> MVDLocationCatalog {
        let filteredCrew = b777300CrewStations.filter { option in
            guard let applicability = option.noseApplicability else { return true }
            if applicability == "7LA-7LB" { return nose.isEmpty || nose == "7LA" || nose == "7LB" }
            if applicability == "7LC-7LW" { return nose.isEmpty || (b777300Noses.contains(nose) && nose != "7LA" && nose != "7LB") }
            return true
        }

        return MVDLocationCatalog(
            galleys: [
                galley("F1", pnr: "1064GXXA00000", cmm: "25-06-39"),
                galley("F3", pnr: "1064GXXA00000", cmm: "25-06-39"),
                galley("M1", pnr: "1064GXXA00000", cmm: "25-06-39"),
                galley("M2", pnr: "1064GXXA00000", cmm: "25-06-39"),
                galley("M7", pnr: "1064GXXA00000", cmm: "25-06-39"),
                galley("A1", pnr: "1064GXXA00000", cmm: "25-06-39"),
                galley("A2", pnr: "1064GXXA00000", cmm: "25-06-39"),
                galley("A3", pnr: "1064GXXA00000", cmm: "25-06-39"),
                galley("A4", pnr: "1064GXXA00000", cmm: "25-06-39")
            ].map { $0.withStandardGalleyPractice() },
            lavatories: [
                lavatory("L1 FWD-L"), lavatory("L1 FWD-R"),
                lavatory("L2 FWD-L"), lavatory("L2 FWD-R"),
                lavatory("L3 MID-L"), lavatory("L3 MID-R"),
                lavatory("L4 AFT-L"), lavatory("L4 AFT-R"),
                lavatory("L5 AFT-L"), lavatory("L5 AFT-R")
            ],
            flightDeck: flightDeckOptions,
            crewStations: filteredCrew,
            stowageBins: sharedStowageBins
        )
    }

    private static let flightDeckOptions = [
        MVDLocationOption(id: "flight-deck-25-11-38", name: "FLIGHT DECK — CAPTAIN / FIRST OFFICER", cmmNumbers: ["25-11-38"]),
        MVDLocationOption(id: "flight-deck-25-10-87", name: "FLIGHT DECK — ALTERNATE CAPTAIN / FIRST OFFICER", cmmNumbers: ["25-10-87"])
    ]

    private static let b777200CrewStations: [MVDLocationOption] = [
        crew("CAPTAIN SEAT", pnr: "3A258-0041-01-1", cmm: "25-11-38"),
        crew("FIRST OFFICER SEAT", pnr: "3A258-0042-01-1", cmm: "25-11-38"),
        crew("CAPTAIN SEAT", pnr: "3A201-0007-01-1", cmm: "25-10-87"),
        crew("FIRST OFFICER SEAT", pnr: "3A201-0008-01-1", cmm: "25-10-87"),
        crew("FIRST OBSERVER SEAT", pnr: "16800-1", cmm: "25-10-02"),
        crew("SECOND OBSERVER SEAT", pnr: "16810-1", cmm: "25-10-02"),
        crew("F/A SEAT 1L", pnr: "2112-739GJ", cmm: "25-24-59"),
        crew("F/A SEAT 1R", pnr: "2112-739GJ", cmm: "25-24-59"),
        crew("F/A SEAT 2L", pnr: "2112-701EQK", cmm: "25-73-67"),
        crew("F/A SEAT 2R", pnr: "2112-701EQK", cmm: "25-73-67"),
        crew("F/A SEAT 3L", pnr: "2112-702EQK", cmm: "25-73-67"),
        crew("F/A SEAT 3R", pnr: "2112-702EQK", cmm: "25-73-67"),
        crew("F/A SEAT 4L", pnr: "2112-701GJ", cmm: "25-24-59"),
        crew("F/A SEAT 4R", pnr: "2112-701GJ", cmm: "25-24-59")
    ]

    private static let b777300CrewStations: [MVDLocationOption] = [
        crew("CAPTAIN SEAT", pnr: "3A258-0041-01-1, 3A258-0042-01-1, 3A258-0041-01-2, 3A258-0042-01-2", cmm: "25-11-38", nose: "7LA-7LW"),
        crew("FIRST OFFICER SEAT", pnr: "3A258-0041-01-1, 3A258-0042-01-1, 3A258-0041-01-2, 3A258-0042-01-2", cmm: "25-11-38", nose: "7LA-7LW"),
        crew("CAPTAIN SEAT", pnr: "3A201-0007-01-1, 3A201-0008-01-1", cmm: "25-10-87", nose: "7LA-7LW"),
        crew("FIRST OFFICER SEAT", pnr: "3A201-0007-01-1, 3A201-0008-01-1", cmm: "25-10-87", nose: "7LA-7LW"),
        crew("FIRST OBSERVER SEAT", pnr: "16800-1, 16810-1, 16810-3", cmm: "25-10-02", nose: "7LA-7LB"),
        crew("SECOND OBSERVER SEAT", pnr: "16800-1, 16810-1, 16810-3", cmm: "25-10-02", nose: "7LA-7LB"),
        crew("SECOND OBSERVER SEAT", pnr: "3A444-0007-001-1", cmm: "25-11-75", nose: "7LC-7LW"),
        crew("FIRST OBSERVER SEAT", pnr: "3A444-0007-001-1", cmm: "25-11-77", nose: "7LC-7LW"),
        crew("OFCR SEAT", pnr: "3A334-0007-02-1, 3A334-0008-02-1", cmm: "25-21-04", nose: "7LA-7LW"),
        crew("F/A SEAT 1L", pnr: "2112-801NH, 2112-802NH", cmm: "25-71-50", nose: "7LA-7LW"),
        crew("F/A SEAT 1R", pnr: "2112-801NH, 2112-802NH", cmm: "25-71-50", nose: "7LA-7LW"),
        crew("F/A SEAT 2L", pnr: "2112-801NH, 2112-802NH", cmm: "25-71-50", nose: "7LA-7LW"),
        crew("F/A SEAT 2R", pnr: "2112-801NH, 2112-802NH", cmm: "25-71-50", nose: "7LA-7LW"),
        crew("F/A SEAT 3L", pnr: "2112-801NH, 2112-802NH", cmm: "25-71-50", nose: "7LA-7LW"),
        crew("F/A SEAT 3R", pnr: "2112-801NH, 2112-802NH", cmm: "25-71-50", nose: "7LA-7LW"),
        crew("F/A SEAT 4L", pnr: "2112-801NH, 2112-802NH", cmm: "25-71-50", nose: "7LA-7LW"),
        crew("F/A SEAT 4R", pnr: "2112-801NH, 2112-802NH", cmm: "25-71-50", nose: "7LA-7LW"),
        crew("F/A SEAT 5L", pnr: "2112-801NH, 2112-802NH", cmm: "25-71-50", nose: "7LA-7LW"),
        crew("F/A SEAT 5R", pnr: "2112-801NH, 2112-802NH", cmm: "25-71-50", nose: "7LA-7LW")
    ]

    private static let sharedStowageBins = [
        MVDLocationOption(id: "stowage-outboard-boeing", name: "OUTBOARD STOWAGE BIN MODULE ASSY (GROUP 2) — BOEING", pnr: "421W1001-XSP, 421W1002-XSP, 421W1003-XSP, 421W1004-XSP", cmmNumbers: ["25-28-53"]),
        MVDLocationOption(id: "stowage-center-boeing", name: "CENTER STOWAGE BIN MODULE ASSY (GROUP 2) — BOEING", pnr: "422W1001-XXSP, 422W1002-XXSP, 422W1003-XXSP, 422W1010-XX, 422W1011-XX, 422W2101-XX", cmmNumbers: ["25-28-04"]),
        MVDLocationOption(id: "stowage-center-heath-tecna", name: "CENTER STOWAGE BIN MODULE ASSY (GROUP 2) — HEATH TECNA", pnr: "H49075-001", cmmNumbers: ["25-28-80"])
    ]

    private static func galley(_ name: String, pnr: String, cmm: String) -> MVDLocationOption {
        MVDLocationOption(id: "galley-\(name)-\(pnr)", name: name, pnr: pnr, cmmNumbers: [cmm])
    }

    private static func lavatory(_ name: String, cmm: String? = nil) -> MVDLocationOption {
        MVDLocationOption(id: "lavatory-\(name)", name: name, cmmNumbers: cmm.map { [$0] } ?? [])
    }

    private static func crew(_ name: String, pnr: String, cmm: String, nose: String? = nil) -> MVDLocationOption {
        let suffix = nose.map { "-\($0)" } ?? ""
        return MVDLocationOption(id: "crew-\(name)-\(pnr)-\(cmm)\(suffix)", name: name, pnr: pnr, cmmNumbers: [cmm], noseApplicability: nose)
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().replacingOccurrences(of: "_", with: "-")
    }
}

private extension MVDLocationOption {
    func withStandardGalleyPractice() -> MVDLocationOption {
        MVDLocationOption(
            id: id,
            name: name,
            pnr: pnr,
            cmmNumbers: cmmNumbers + ["25-32-03"],
            noseApplicability: noseApplicability
        )
    }
}

enum B777CmmApplicability {
    static func selection(
        domain: MVDLocationDomain,
        model: String,
        nose: String,
        option: MVDLocationOption?,
        seatNumber: String?
    ) -> MVDLocationSelection? {
        if domain == .seat {
            guard let seatNumber,
                  let resolution = resolveSeat(model: model, nose: nose, seatNumber: seatNumber) else { return nil }
            return MVDLocationSelection(
                domain: .seat,
                location: resolution.seatNumber,
                label: "\(resolution.seatNumber) — \(resolution.cabinClass)",
                cmmNumbers: [resolution.cmmNumber]
            )
        }

        guard let option else { return nil }
        return MVDLocationSelection(
            domain: domain,
            location: option.name,
            label: option.name,
            cmmNumbers: option.cmmNumbers
        )
    }

    static func resolveSeat(model: String, nose: String, seatNumber: String) -> MVDSeatResolution? {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().replacingOccurrences(of: "_", with: "-")
        let normalizedNose = nose.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

        if normalizedModel.hasPrefix("B777-200") {
            guard B777LocationData.b777200NoseIsKnown(normalizedNose) else { return nil }
            let bcCmm = B777LocationData.b777200Group1Nose(normalizedNose) ? "25-29-64" : "25-25-71"
            return firstMatch(seatNumber, rules: b777200Rules(bcCmm: bcCmm))
        }

        if normalizedModel.hasPrefix("B777-300") {
            guard B777LocationData.b777300NoseIsKnown(normalizedNose) else { return nil }
            if normalizedNose == "7LB" {
                return firstMatch(seatNumber, rules: b777300PostRules)
            }
            return firstMatch(seatNumber, rules: b777300PreRules)
        }
        return nil
    }

    private struct SeatRule {
        let fromRow: Int
        let toRow: Int
        let positions: Set<Character>
        let cabinClass: String
        let cmm: String

        func matches(_ value: String) -> Bool {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let digits = String(normalized.prefix { $0.isNumber })
            let letters = normalized.drop { $0.isNumber }
            guard let row = Int(digits), let position = letters.first else { return false }
            return row >= fromRow && row <= toRow && positions.contains(position)
        }
    }

    private static func rule(_ from: Int, _ to: Int, _ positions: String, _ cabinClass: String, _ cmm: String) -> SeatRule {
        SeatRule(fromRow: from, toRow: to, positions: Set(positions), cabinClass: cabinClass, cmm: cmm)
    }

    private static func firstMatch(_ seatNumber: String, rules: [SeatRule]) -> MVDSeatResolution? {
        guard let rule = rules.first(where: { $0.matches(seatNumber) }) else { return nil }
        let normalized = seatNumber.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return MVDSeatResolution(seatNumber: normalized, cabinClass: rule.cabinClass, cmmNumber: rule.cmm)
    }

    private static func b777200Rules(bcCmm: String) -> [SeatRule] {
        [
            rule(1, 10, "ADHL", "BC", bcCmm),
            rule(13, 13, "ACDEGHJL", "PE FR", "25-20-82"),
            rule(14, 15, "ACDEGHJL", "PE ST", "25-20-82"),
            rule(17, 17, "ACDEGHJL", "TC FR", "25-29-63"),
            rule(18, 24, "ABCDEFGHJKL", "TC ST", "25-29-63"),
            rule(25, 25, "AC", "TC ST", "25-29-63"),
            rule(26, 26, "ABCDEFGHJKL", "TC FR", "25-29-63"),
            rule(27, 35, "ABCDEFGHJKL", "TC ST", "25-29-63"),
            rule(36, 38, "ACDEGHJL", "MAIN CABIN", "25-29-63"),
            rule(39, 40, "DEGH", "MAIN CABIN", "25-29-63")
        ]
    }

    private static let b777300PreRules: [SeatRule] = [
        rule(1, 2, "ADGJ", "FC", "25-25-20"),
        rule(3, 15, "ADGJ", "BC", "25-02-48"),
        rule(16, 16, "ACDEGHJL", "PE FR", "25-20-82"),
        rule(17, 19, "ACDEGHJL", "PE ST", "25-20-82"),
        rule(20, 20, "ACDEGHJL", "TC FR", "25-29-33"),
        rule(22, 22, "CJ", "TC FR", "25-29-33"),
        rule(31, 31, "ACJL", "TC FR", "25-29-33"),
        rule(33, 33, "CJ", "TC FR", "25-29-33"),
        rule(21, 44, "ACDEGHJL", "TC ST", "25-29-33")
    ]

    private static let b777300PostRules: [SeatRule] = [
        rule(1, 19, "ADHL", "BC", "25-21-17"),
        rule(20, 20, "DEGH", "PE FR", "25-20-82"),
        rule(21, 25, "ACDEGHJL", "PE ST", "25-26-83"),
        rule(26, 26, "ACDEGHJL", "TC FR", "25-21-41"),
        rule(35, 35, "ABCDEGHJKL", "TC FR", "25-21-41"),
        rule(27, 48, "ACDEGHJL", "TC ST", "25-29-33")
    ]
}

extension B777LocationData {
    fileprivate static func b777200NoseIsKnown(_ nose: String) -> Bool {
        b777200Group1Noses.contains(nose) || b777200Group2Noses.contains(nose)
    }

    fileprivate static func b777200Group1Nose(_ nose: String) -> Bool {
        b777200Group1Noses.contains(nose)
    }

    fileprivate static func b777300NoseIsKnown(_ nose: String) -> Bool {
        b777300Noses.contains(nose)
    }
}
