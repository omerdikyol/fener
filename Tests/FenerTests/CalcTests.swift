import XCTest
@testable import fener

final class CalcTests: XCTestCase {
    func v(_ s: String) -> String? { Calc.answer(s)?.value }

    func testArithmeticAndPrecedence() {
        XCTAssertEqual(v("1 + 2 * 3"), "7")
        XCTAssertEqual(v("(1 + 2) * 3"), "9")
        XCTAssertEqual(v("2^3^2"), "512")          // right associative
        XCTAssertEqual(v("-2^2"), "-4")
        XCTAssertEqual(v("10 / 4"), "2.5")
        XCTAssertEqual(v("0.1 + 0.2"), "0.3")
        XCTAssertEqual(v("7 × 6"), "42")
        XCTAssertEqual(v("9 ÷ 3"), "3")
    }

    func testPercentFunctionsConstants() {
        XCTAssertEqual(v("20% * 150"), "30")
        XCTAssertEqual(v("sqrt 16 + 1"), "5")
        XCTAssertEqual(v("sqrt(2)^2"), "2")
        XCTAssertEqual(v("2pi"), Calc.format(2 * .pi))
        XCTAssertEqual(v("2(3+1)"), "8")
        XCTAssertEqual(v("log 1000 + ln(e)"), "4")
        XCTAssertEqual(v("√9"), "3")
    }

    func testDecimalCommaAndUnderscores() {
        XCTAssertEqual(v("3,5 + 1,25"), "4.75")
        XCTAssertEqual(v("1_000 * 2"), "2000")
    }

    func testNotACalculation() {
        XCTAssertNil(Calc.answer("2024"))         // a bare number
        XCTAssertNil(Calc.answer("1Password"))
        XCTAssertNil(Calc.answer("safari"))
        XCTAssertNil(Calc.answer("e"))
        XCTAssertNil(Calc.answer("1 +"))
        XCTAssertNil(Calc.answer("(1 + 2"))
        XCTAssertNil(Calc.answer("1 / 0"))        // infinite
        XCTAssertEqual(Calc.answer("2024", forced: true)?.value, "2024")  // with the = prefix
    }

    func testConversions() {
        XCTAssertEqual(v("10 km to mi"), "6.213711922")
        XCTAssertEqual(v("10km in mi"), "6.213711922")
        XCTAssertEqual(v("212 f to c"), "100")
        XCTAssertEqual(v("0 c -> k"), "273.15")
        XCTAssertEqual(v("1 gib to mb"), "1073.741824")
        XCTAssertEqual(v("90 min to h"), "1.5")
        XCTAssertEqual(v("2 * 5 kg as lb"), "22.04622622")
        XCTAssertNil(Calc.answer("10 km to kg"))   // different kinds
        XCTAssertNil(Calc.answer("10 parsecs to m"))
    }

    func testFormat() {
        XCTAssertEqual(Calc.format(1e20), "1e+20")
        XCTAssertEqual(Calc.format(-3), "-3")
        XCTAssertEqual(Calc.format(1.0 / 3), "0.3333333333")
    }
}
