import AVFoundation
import UIKit

/// Short, locally synthesized racket transients and score tones.
@MainActor
final class CourtSound {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let impact = UIImpactFeedbackGenerator(style: .light)
    private let scoreFeedback = UINotificationFeedbackGenerator()
    private let rate: Double = 44_100
    private var clips: [AVAudioPCMBuffer] = []
    private var enabled = false

    init() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        for index in 0..<4 {
            let duration = [0.085, 0.14, 0.23, 0.21][index]
            let frames = AVAudioFrameCount(duration * rate)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                  let samples = buffer.floatChannelData?[0] else { return }
            buffer.frameLength = frames
            var previous = 0.0
            for n in 0..<Int(frames) {
                let t = Double(n) / rate
                let signal: Double
                if index < 2 {
                    let noise = Double.random(in: -1...1)
                    let snap = (noise - previous) * exp(-t * (index == 1 ? 76 : 106))
                    let string = sin(2 * .pi * (index == 1 ? 610 : 860) * t) * exp(-t * 68)
                    signal = 0.26 * snap + 0.18 * string
                    previous = noise
                } else {
                    let second = t >= 0.085
                    let local = second ? t - 0.085 : t
                    let freq = index == 2 ? (second ? 880.0 : 659.25) : (second ? 392.0 : 493.88)
                    signal = 0.16 * sin(2 * .pi * freq * local) * exp(-local * 34) * min(1, local * 400)
                }
                samples[n] = Float(signal)
            }
            clips.append(buffer)
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try engine.start()
            enabled = true
        } catch { enabled = false }
        impact.prepare()
    }

    private func play(_ index: Int) {
        guard enabled, clips.indices.contains(index) else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        player.scheduleBuffer(clips[index], at: nil, options: [.interrupts])
        if !player.isPlaying { player.play() }
    }

    func hit(power: Bool, haptic: Bool) {
        play(power ? 1 : 0)
        if haptic { impact.impactOccurred(intensity: power ? 0.9 : 0.42); impact.prepare() }
    }

    func point(won: Bool) {
        play(won ? 2 : 3)
        if won { scoreFeedback.notificationOccurred(.success) }
    }

    func stop() {
        player.stop()
        engine.stop()
    }
}
