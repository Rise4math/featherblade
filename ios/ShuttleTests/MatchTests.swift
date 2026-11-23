import XCTest
@testable import Shuttle

final class MatchTests: XCTestCase {
    @MainActor
    func testUnreturnedServesCompleteDefaultMatchAndReplay() async {
        let game = MatchScene(seed: 12)
        game.start()
        game.serve()
        let beforePause = game.status
        XCTAssertEqual(beforePause.phase, .rally)
        game.setPaused(true)
        for _ in 0..<180 { game.tick(1.0 / 60) }
        game.strike(.smash)
        XCTAssertEqual(game.status, beforePause)
        game.setPaused(false)

        var points = [Bool]()
        game.onEvent = {
            if case .point(let player) = $0 { points.append(player) }
        }
        for _ in 0..<9_000 {
            if game.status.phase == .finished { break }
            game.tick(1.0 / 60)
        }
        XCTAssertEqual(game.status.phase, .finished)
        XCTAssertEqual(game.status.opponentScore, 11)
        XCTAssertEqual(game.status.playerScore, 0)
        XCTAssertEqual(game.status.playerWon, false)
        XCTAssertEqual(points, Array(repeating: false, count: 11))
        game.start()
        XCTAssertEqual(game.status.phase, .ready)
        XCTAssertEqual(game.status.playerScore + game.status.opponentScore, 0)
        XCTAssertEqual(game.status.rally, 0)
        XCTAssertNil(game.status.playerWon)
        XCTAssertTrue(game.status.playerServing)
        game.serve()
        XCTAssertEqual(game.status.phase, .rally)
    }

    @MainActor
    func testTimedReturnsReachDeuceAndSuddenDeath() async {
        let game = MatchScene(targetScore: 3, scoreCap: 5, seed: 4)
        let strokes: [MatchScene.Stroke] = [.drop, .smash, .clear]
        var highScoreTies = Set<Int>()
        var longestRally = 0
        game.start()
        for _ in 0..<30_000 {
            let state = game.status
            if state.phase == .finished { break }
            if state.playerScore == state.opponentScore, state.playerScore >= 2 {
                highScoreTies.insert(state.playerScore)
            }
            longestRally = max(longestRally, state.rally)
            if state.phase == .ready { game.serve() }
            // Yield the point when ahead. While receiving, alternate corners and mix the strokes.
            if state.playerScore <= state.opponentScore, state.canHit {
                game.strike(strokes[(state.rally / 2) % strokes.count], aim: state.rally % 4 <= 1 ? 1 : -1)
            }
            game.tick(1.0 / 60)
        }
        XCTAssertEqual(highScoreTies, [2, 3, 4])
        XCTAssertGreaterThan(longestRally, 4)
        XCTAssertEqual(game.status.phase, .finished)
        XCTAssertEqual(max(game.status.playerScore, game.status.opponentScore), 5)
        XCTAssertEqual(min(game.status.playerScore, game.status.opponentScore), 4)
    }
}
