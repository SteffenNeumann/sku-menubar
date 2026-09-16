import XCTest
@testable import myClaude

/// Unit-Tests für die Entwicklerkosten-Berechnung und den reparierten
/// Vergleichszeitraum der Trend-Pfeile.
final class DevCostTests: XCTestCase {

    // MARK: - Grundrechnung

    func testCostForOneHour() {
        XCTAssertEqual(DevCost.cost(seconds: 3600, rate: 85), 85, accuracy: 0.0001)
    }

    func testCostIsProportional() {
        // 19 Minuten bei 85 €/h
        XCTAssertEqual(DevCost.cost(seconds: 19 * 60, rate: 85), 26.916666, accuracy: 0.0001)
    }

    func testZeroAndNegativeInputsYieldZero() {
        XCTAssertEqual(DevCost.cost(seconds: 0,    rate: 85), 0)
        XCTAssertEqual(DevCost.cost(seconds: -100, rate: 85), 0)
        XCTAssertEqual(DevCost.cost(seconds: 3600, rate: 0),  0)
        XCTAssertEqual(DevCost.cost(seconds: 3600, rate: -5), 0)
        XCTAssertEqual(DevCost.cost(seconds: 3600, rate: .nan), 0)
    }

    func testEmptyProjectListTotalsZero() {
        XCTAssertEqual(DevCost.total(seconds: [], rate: 85), 0)
    }

    // MARK: - Rundungsreihenfolge
    //
    // Der eigentliche Grund für diese Datei: Summiert man die gerundeten
    // Einzelbeträge statt der Sekunden, zeigt die Kachel 8.957 € statt 8.956 €.
    // Echte Quartalszahlen aus der Zeiterfassung, 85 €/h.

    private let quarterSeconds = [
        (54 * 60 + 19) * 60,   // 54h 19m
        (34 * 60 + 54) * 60,   // 34h 54m
        ( 7 * 60 + 52) * 60,   //  7h 52m
        ( 5 * 60 + 24) * 60,   //  5h 24m
        ( 2 * 60 + 34) * 60,   //  2h 34m
        (          19) * 60    //      19m
    ]

    func testQuarterSecondsMatchDisplayedTotal() {
        XCTAssertEqual(quarterSeconds.reduce(0, +), (105 * 60 + 22) * 60)
    }

    func testTotalIsComputedFromSecondsNotFromRoundedRows() {
        let rate = 85.0
        let total = DevCost.total(seconds: quarterSeconds, rate: rate)
        XCTAssertEqual(total, 8956.1666, accuracy: 0.001)
        XCTAssertEqual(DevCost.formatCompact(total), "8.956 €")

        // Gegenprobe: zeilenweise gerundet und aufaddiert wäre es ein Euro mehr.
        let summedRows = quarterSeconds
            .map { (DevCost.cost(seconds: $0, rate: rate)).rounded() }
            .reduce(0, +)
        XCTAssertEqual(summedRows, 8957)
        XCTAssertNotEqual(summedRows, total.rounded())
    }

    // MARK: - Formatierung

    func testFormatCompactUsesGermanThousandsSeparator() {
        XCTAssertEqual(DevCost.formatCompact(4616.9167), "4.617 €")
        XCTAssertEqual(DevCost.formatCompact(27), "27 €")
    }

    func testFormatExactUsesGermanDecimalComma() {
        XCTAssertEqual(DevCost.formatExact(4616.9167), "4.616,92 €")
    }

    func testFormatRate() {
        XCTAssertEqual(DevCost.formatRate(85), "85,00 €/h")
    }

    func testFormatHandlesNonFiniteValues() {
        XCTAssertEqual(DevCost.formatCompact(.nan), "–")
        XCTAssertEqual(DevCost.formatExact(.infinity), "–")
    }

    // MARK: - Stundensatz-Modell

    func testSanitizeClampsInvalidAmounts() {
        XCTAssertEqual(HourlyRate.sanitize(65), 65)
        XCTAssertEqual(HourlyRate.sanitize(-5), 0)
        XCTAssertEqual(HourlyRate.sanitize(.nan), 0)
        XCTAssertEqual(HourlyRate.sanitize(1e9), 10_000)
    }

    func testSettingsFallBackToDefaultRatesWhenKeyMissing() throws {
        // Altes Settings-JSON ohne hourlyRates → Defaults, nicht leere Liste.
        let json = Data(#"{"token":"","budget":10.0}"#.utf8)
        let decoded = try JSONDecoder().decode(GitHubSettings.self, from: json)
        XCTAssertEqual(decoded.hourlyRates.count, HourlyRate.defaults.count)
    }

    func testSettingsKeepEmptyRateListWhenUserClearedIt() throws {
        // Leere Liste ist eine Nutzerentscheidung — Defaults dürfen nicht zurückkehren.
        let json = Data(#"{"token":"","hourlyRates":[]}"#.utf8)
        let decoded = try JSONDecoder().decode(GitHubSettings.self, from: json)
        XCTAssertTrue(decoded.hourlyRates.isEmpty)
    }

    func testSettingsRoundTripKeepsRates() throws {
        var s = GitHubSettings()
        s.hourlyRates = [HourlyRate(label: "Test", amount: 123)]
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(GitHubSettings.self, from: data)
        XCTAssertEqual(back.hourlyRates.first?.label, "Test")
        XCTAssertEqual(back.hourlyRates.first?.amount, 123)
    }

    // MARK: - Vergleichszeitraum (Trend-Pfeile)
    //
    // Vorher lief eine angefangene Periode gegen eine volle Vorperiode — der Pfeil
    // zeigte am Monatsersten fast immer −99 %. Jetzt ist der Vergleichszeitraum
    // gleich lang, nur `.lastMonth` vergleicht als abgeschlossene Periode weiter
    // gegen den vollen Vormonat.

    private func lengths(_ p: TMetricPeriod) -> (cur: TimeInterval, prev: TimeInterval) {
        let (cf, ct) = p.dateRange()
        let (pf, pt) = p.previousPeriodRange()
        return (ct.timeIntervalSince(cf), pt.timeIntervalSince(pf))
    }

    func testRunningPeriodsCompareAgainstEqualLengthWindow() {
        for p in [TMetricPeriod.today, .thisWeek, .thisMonth, .thisQuarter, .thisYear] {
            let (cur, prev) = lengths(p)
            XCTAssertEqual(prev, cur, accuracy: 1,
                           "Vergleichszeitraum für \(p.rawValue) muss gleich lang sein")
        }
    }

    func testPreviousRangeEndsBeforeCurrentRangeStarts() {
        for p in TMetricPeriod.allCases {
            let (cf, _)  = p.dateRange()
            let (pf, pt) = p.previousPeriodRange()
            XCTAssertLessThan(pf, cf, "Vorperiode für \(p.rawValue) muss vor der aktuellen beginnen")
            // 2h Toleranz: an Zeitumstellungs-Tagen ist die laufende Periode um eine
            // Stunde länger als der Kalenderabstand zur Vorperiode.
            XCTAssertLessThanOrEqual(pt, cf.addingTimeInterval(7200),
                                     "Vorperiode für \(p.rawValue) darf nicht in die aktuelle ragen")
        }
    }

    func testLastMonthStillComparesAgainstFullPreviousMonth() {
        let (pf, pt) = TMetricPeriod.lastMonth.previousPeriodRange()
        let (cf, _)  = TMetricPeriod.lastMonth.dateRange()
        // Vorperiode endet exakt am Beginn des Vormonats und umfasst einen ganzen Monat.
        XCTAssertEqual(pt, cf)
        let days = pt.timeIntervalSince(pf) / 86_400
        XCTAssertGreaterThanOrEqual(days, 28)
        XCTAssertLessThanOrEqual(days, 31)
    }
}
