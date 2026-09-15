import SwiftUI

/// Shared iOS equivalent of the Android CMM Location overlay.
/// It only selects the work location; fleet modules resolve the CMM.
struct CmmLocationSheet: View {
    let aircraftModel: String
    let nose: String
    let onSelect: (MVDLocationSelection) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var activeDomain: MVDLocationDomain = .none
    @State private var seatNumber = ""
    @State private var selectedGalleyID = ""
    @State private var selectedLavatoryID = ""
    @State private var selectedFlightDeckID = ""
    @State private var selectedCrewStationID = ""
    @State private var selectedStowageBinID = ""

    private var catalog: MVDLocationCatalog {
        MVDFleetRegistry.catalog(model: aircraftModel, nose: nose)
    }

    private var currentSelection: MVDLocationSelection? {
        switch activeDomain {
        case .seat:
            return MVDFleetRegistry.select(
                domain: .seat,
                model: aircraftModel,
                nose: nose,
                seatNumber: seatNumber
            )
        case .galley:
            return selectOption(id: selectedGalleyID, from: catalog.galleys, domain: .galley)
        case .lavatory:
            return selectOption(id: selectedLavatoryID, from: catalog.lavatories, domain: .lavatory)
        case .flightDeck:
            return selectOption(id: selectedFlightDeckID, from: catalog.flightDeck, domain: .flightDeck)
        case .crewStation:
            return selectOption(id: selectedCrewStationID, from: catalog.crewStations, domain: .crewStation)
        case .stowageBin:
            return selectOption(id: selectedStowageBinID, from: catalog.stowageBins, domain: .stowageBin)
        case .none:
            return nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("AIRCRAFT") {
                    LabeledContent("Model", value: aircraftModel)
                    LabeledContent("Nose", value: nose)
                    LabeledContent("Family", value: MVDFleetRegistry.family(for: aircraftModel).rawValue.uppercased())
                }

                Section("SEAT") {
                    TextField("Seat (ej.: 2H)", text: $seatNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onTapGesture { activeDomain = .seat }

                    Button("SELECT SEAT") { activeDomain = .seat }
                        .disabled(seatNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("COMPONENT LOCATION") {
                    locationPicker("Galley", selection: $selectedGalleyID, options: catalog.galleys)
                        .onChange(of: selectedGalleyID) { value in
                            activeDomain = value.isEmpty ? .none : .galley
                        }

                    locationPicker("Lavatory", selection: $selectedLavatoryID, options: catalog.lavatories)
                        .onChange(of: selectedLavatoryID) { value in
                            activeDomain = value.isEmpty ? .none : .lavatory
                        }

                    locationPicker("Flight Deck", selection: $selectedFlightDeckID, options: catalog.flightDeck)
                        .onChange(of: selectedFlightDeckID) { value in
                            activeDomain = value.isEmpty ? .none : .flightDeck
                        }

                    locationPicker("CREW STATION", selection: $selectedCrewStationID, options: catalog.crewStations)
                        .onChange(of: selectedCrewStationID) { value in
                            activeDomain = value.isEmpty ? .none : .crewStation
                        }

                    locationPicker("STOWAGE BIN", selection: $selectedStowageBinID, options: catalog.stowageBins)
                        .onChange(of: selectedStowageBinID) { value in
                            activeDomain = value.isEmpty ? .none : .stowageBin
                        }
                }

                Section("CMM RESULT") {
                    if let currentSelection {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(currentSelection.label)
                                .font(.headline)
                                .foregroundStyle(.blue)
                            Text("CMM: \(currentSelection.cmmDisplay)")
                                .font(.subheadline.weight(.semibold))
                            if !currentSelection.trainingFolderNames.isEmpty {
                                Text("Training folders: \(currentSelection.trainingFolderNames.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Select a seat or component location to resolve its CMM.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    guard let currentSelection else { return }
                    onSelect(currentSelection)
                    dismiss()
                } label: {
                    Label("USE LOCATION", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(currentSelection == nil)
            }
            .navigationTitle("CMM LOCATION")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func locationPicker(
        _ label: String,
        selection: Binding<String>,
        options: [MVDLocationOption]
    ) -> some View {
        Picker(label, selection: selection) {
            Text("—").tag("")
            ForEach(options) { option in
                Text(option.pickerTitle).tag(option.id)
            }
        }
        .pickerStyle(.menu)
    }

    private func selectOption(
        id: String,
        from options: [MVDLocationOption],
        domain: MVDLocationDomain
    ) -> MVDLocationSelection? {
        guard let option = options.first(where: { $0.id == id }) else { return nil }
        return MVDFleetRegistry.select(domain: domain, model: aircraftModel, nose: nose, option: option)
    }
}

struct CmmSelectionSummary: View {
    let selection: MVDLocationSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("SELECTED LOCATION", systemImage: "mappin.and.ellipse")
                .font(.caption.weight(.bold))
                .foregroundStyle(.blue)
            Text(selection.label).font(.headline)
            Text("CMM: \(selection.cmmDisplay)")
                .font(.subheadline.weight(.semibold))
            if !selection.trainingFolderNames.isEmpty {
                Text("Folders: \(selection.trainingFolderNames.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}
