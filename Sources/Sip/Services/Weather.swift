import Foundation
import Observation
import SipCore

/// Today's forecast from Open-Meteo (free, no key, no account): the high, for
/// the goal bonus, and the hour-by-hour sky, for the weather on the glass.
/// Only the coordinates of the city you choose are sent, once a day; the
/// current hour is then read from the saved forecast, with no more requests.
@MainActor
@Observable
final class WeatherService {
    struct Place: Identifiable, Equatable {
        var id: String { "\(latitude),\(longitude)" }
        var name: String
        var region: String
        var latitude: Double
        var longitude: Double
    }

    struct Hour: Equatable {
        var time: Date
        var temperatureC: Double?
        var humidity: Double?
        var code: Int?
        var precipitation: Double?
    }

    private(set) var maxTemperatureC: Double?
    private(set) var hours: [Hour] = []
    private(set) var fetchedDay: DayKey?
    private(set) var error: String?
    private(set) var searchResults: [Place] = []

    var bonusML: Double { maxTemperatureC.map(HeatAdjustment.bonusML(maxTemperatureC:)) ?? 0 }

    @ObservationIgnored var onUpdate: (() -> Void)?

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    /// Fetches once per drinking day.
    func refreshIfNeeded(latitude: Double, longitude: Double, today: DayKey, force: Bool = false) {
        guard force || fetchedDay != today else { return }
        // Two days of hours, so the small hours after midnight (still "today"
        // until the day starts) have a forecast too.
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)"
                      + "&daily=temperature_2m_max&hourly=temperature_2m,relative_humidity_2m,weather_code,precipitation"
                      + "&timezone=auto&forecast_days=2&timeformat=unixtime")!
        Task {
            do {
                let (data, _) = try await session.data(from: url)
                struct Response: Decodable {
                    struct Daily: Decodable { let temperature_2m_max: [Double?] }
                    struct Hourly: Decodable {
                        let time: [Double]
                        let temperature_2m: [Double?]?
                        let relative_humidity_2m: [Double?]?
                        let weather_code: [Int?]?
                        let precipitation: [Double?]?
                    }
                    let daily: Daily
                    let hourly: Hourly?
                }
                let response = try JSONDecoder().decode(Response.self, from: data)
                self.maxTemperatureC = response.daily.temperature_2m_max.first ?? nil
                if let h = response.hourly {
                    self.hours = h.time.indices.map { i in
                        Hour(time: Date(timeIntervalSince1970: h.time[i]),
                             temperatureC: h.temperature_2m?[safe: i] ?? nil,
                             humidity: h.relative_humidity_2m?[safe: i] ?? nil,
                             code: h.weather_code?[safe: i] ?? nil,
                             precipitation: h.precipitation?[safe: i] ?? nil)
                    }
                }
                self.fetchedDay = today
                self.error = nil
            } catch {
                self.error = "Couldn't get the forecast (\(error.localizedDescription))."
            }
            self.onUpdate?()
        }
    }

    /// The forecast for the hour we're in, if there is one.
    func now(_ date: Date = Date()) -> Hour? {
        hours.last { $0.time <= date && date.timeIntervalSince($0.time) < 3600 }
    }

    func clear() {
        guard maxTemperatureC != nil || !hours.isEmpty || fetchedDay != nil else { return }
        maxTemperatureC = nil
        hours = []
        fetchedDay = nil
        error = nil
        onUpdate?()
    }

    func search(_ name: String) {
        let query = name.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://geocoding-api.open-meteo.com/v1/search?name=\(encoded)&count=6&language=en&format=json") else {
            searchResults = []
            return
        }
        Task {
            struct Response: Decodable {
                struct Result: Decodable {
                    let name: String
                    let latitude: Double
                    let longitude: Double
                    let admin1: String?
                    let country: String?
                }
                let results: [Result]?
            }
            do {
                let (data, _) = try await session.data(from: url)
                let response = try JSONDecoder().decode(Response.self, from: data)
                self.searchResults = (response.results ?? []).map {
                    Place(name: $0.name, region: [$0.admin1, $0.country].compactMap { $0 }.joined(separator: ", "),
                          latitude: $0.latitude, longitude: $0.longitude)
                }
            } catch {
                self.searchResults = []
            }
        }
    }
}
