//
//  TicketmasterRegion.swift
//  Bluefin
//
//  Created by Jacob Marcuson on 8/23/26.
//

import Foundation

enum TicketmasterRegionKind: String, Codable {
    case usState
    case canadaProvince
    case country
}

/// A US state, Canadian province/territory, or country the user can restrict Upcoming Concerts to.
struct TicketmasterRegion: Identifiable, Hashable, Codable {
    let kind: TicketmasterRegionKind
    let code: String
    let name: String

    var id: String { "\(kind.rawValue):\(code)" }
}

extension TicketmasterRegion {
    static let usStates: [TicketmasterRegion] = [
        ("AL", "Alabama"), ("AK", "Alaska"), ("AZ", "Arizona"), ("AR", "Arkansas"), ("CA", "California"),
        ("CO", "Colorado"), ("CT", "Connecticut"), ("DE", "Delaware"), ("DC", "District of Columbia"),
        ("FL", "Florida"), ("GA", "Georgia"), ("HI", "Hawaii"), ("ID", "Idaho"), ("IL", "Illinois"),
        ("IN", "Indiana"), ("IA", "Iowa"), ("KS", "Kansas"), ("KY", "Kentucky"), ("LA", "Louisiana"),
        ("ME", "Maine"), ("MD", "Maryland"), ("MA", "Massachusetts"), ("MI", "Michigan"), ("MN", "Minnesota"),
        ("MS", "Mississippi"), ("MO", "Missouri"), ("MT", "Montana"), ("NE", "Nebraska"), ("NV", "Nevada"),
        ("NH", "New Hampshire"), ("NJ", "New Jersey"), ("NM", "New Mexico"), ("NY", "New York"),
        ("NC", "North Carolina"), ("ND", "North Dakota"), ("OH", "Ohio"), ("OK", "Oklahoma"), ("OR", "Oregon"),
        ("PA", "Pennsylvania"), ("RI", "Rhode Island"), ("SC", "South Carolina"), ("SD", "South Dakota"),
        ("TN", "Tennessee"), ("TX", "Texas"), ("UT", "Utah"), ("VT", "Vermont"), ("VA", "Virginia"),
        ("WA", "Washington"), ("WV", "West Virginia"), ("WI", "Wisconsin"), ("WY", "Wyoming")
    ].map { TicketmasterRegion(kind: .usState, code: $0.0, name: $0.1) }

    static let canadaProvinces: [TicketmasterRegion] = [
        ("AB", "Alberta"), ("BC", "British Columbia"), ("MB", "Manitoba"), ("NB", "New Brunswick"),
        ("NL", "Newfoundland and Labrador"), ("NS", "Nova Scotia"), ("NT", "Northwest Territories"),
        ("NU", "Nunavut"), ("ON", "Ontario"), ("PE", "Prince Edward Island"), ("QC", "Quebec"),
        ("SK", "Saskatchewan"), ("YT", "Yukon")
    ].map { TicketmasterRegion(kind: .canadaProvince, code: $0.0, name: $0.1) }

    /// Every other ISO country a venue might be in — US and Canada are covered by the more specific
    /// state/province lists above instead, so they're excluded here to avoid a redundant entry.
    static let otherCountries: [TicketmasterRegion] = Locale.Region.isoRegions
        .map(\.identifier)
        .filter { $0 != "US" && $0 != "CA" }
        .compactMap { code -> TicketmasterRegion? in
            guard let name = Locale.current.localizedString(forRegionCode: code) else { return nil }
            return TicketmasterRegion(kind: .country, code: code, name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
}
