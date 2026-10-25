import AppKit

/// Water sounds, synthesised at launch rather than shipped as files.
///
/// - A bubble "bloop" is a sine whose pitch rises as it decays — the
///   resonance of a bubble shrinking as it reaches the surface.
/// - A pour is band-passed noise whose centre frequency climbs, the way a
///   filling bottle's air column gets shorter and higher, with bloops mixed in.
/// - The goal chime is a soft major arpeggio.
///
/// Each sound is rendered once into a small in-memory WAV and played with
/// `NSSound`. An earlier version built an `AVAudioEngine` graph for every
/// burst of sound and tore it down afterwards: about 80 ms of CPU and tens of
/// megabytes of audio-unit buffers per drink. A finished clip costs neither.
final class Sounds {
    private struct Clip {
        var samples: [Float]
    }

    private let sampleRate = 44_100.0
    /// Playing sounds, held until they finish.
    private var playing: [NSSound] = []

    private lazy var bloops: [Data] = [520, 680, 820, 980, 1150].map { wav(bloop(f0: $0, duration: 0.12)) }
    private lazy var pours: [Data] = [0.55, 0.85, 1.2].map { wav(pour(duration: $0)) }
    private lazy var chimeData: Data = wav(chime())

    var volume: Float = 0.6

    // MARK: Playback

    func playPour(fraction: Double) {
        let index = fraction < 0.08 ? 0 : (fraction < 0.16 ? 1 : 2)
        play(pours[index], gain: 0.9)
    }

    func playBloop() {
        play(bloops.randomElement()!, gain: 0.7)
    }

    func playChime() {
        play(chimeData, gain: 0.8)
    }

    private func play(_ data: Data, gain: Float) {
        guard volume > 0, let sound = NSSound(data: data) else { return }
        sound.volume = min(max(volume * gain, 0), 1)
        playing.removeAll { !$0.isPlaying }
        playing.append(sound)
        sound.play()
        let duration = sound.duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.3) { [weak self] in
            self?.playing.removeAll { !$0.isPlaying }
        }
    }

    /// 16-bit mono PCM in a WAV container.
    private func wav(_ clip: Clip) -> Data {
        let rate = UInt32(sampleRate)
        var pcm = Data(capacity: clip.samples.count * 2)
        for sample in clip.samples {
            var value = Int16(max(-1, min(1, sample)) * 32_000).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + pcm.count))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(rate); append(rate * 2); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(pcm.count))
        data.append(pcm)
        return data
    }

    // MARK: Synthesis

    /// Adds a bubble at `start` seconds into `data`.
    private func addBloop(_ data: inout [Float], frames: Int, start: Double, f0: Double, gain: Double) {
        let sr = sampleRate
        // Decay and pitch rise scale with the bubble's resonant frequency.
        let decay = 0.043 * f0 + 0.0014 * pow(f0, 1.5)
        let rise = 0.1 * decay
        let length = min(Int(6.0 / decay * sr), frames)
        let first = Int(start * sr)
        var phase = 0.0
        for i in 0..<length {
            let index = first + i
            guard index < frames else { break }
            let t = Double(i) / sr
            let f = f0 * (1 + rise * t)
            phase += 2 * .pi * f / sr
            let attack = min(t / 0.002, 1)
            data[index] += Float(sin(phase) * exp(-decay * t) * attack * gain)
        }
    }

    private func bloop(f0: Double, duration: Double) -> Clip {
        let frames = Int(duration * sampleRate)
        var data = [Float](repeating: 0, count: frames)
        addBloop(&data, frames: frames, start: 0, f0: f0, gain: 0.5)
        return Clip(samples: data)
    }

    private func pour(duration: Double) -> Clip {
        let total = duration + 0.35
        let frames = Int(total * sampleRate)
        var data = [Float](repeating: 0, count: frames)
        let sr = sampleRate
        // Two-pole resonant band-pass (RBJ) with a rising centre frequency.
        var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
        var rng = SystemRandomNumberGenerator()
        for i in 0..<frames {
            let t = Double(i) / sr
            let progress = min(t / duration, 1)
            let centre = 420 + 1100 * pow(progress, 0.8)
            let q = 3.2
            let w = 2 * .pi * centre / sr
            let alpha = sin(w) / (2 * q)
            let b0 = alpha, b2 = -alpha
            let a0 = 1 + alpha, a1 = -2 * cos(w), a2 = 1 - alpha
            let noise = Double(UInt32.random(in: 0...UInt32.max, using: &rng)) / Double(UInt32.max) * 2 - 1
            let y = (b0 * noise + b2 * x2 - a1 * y1 - a2 * y2) / a0
            x2 = x1; x1 = noise; y2 = y1; y1 = y
            let attack = min(t / 0.05, 1)
            let release = t > duration ? exp(-(t - duration) * 14) : 1
            let flutter = 0.8 + 0.2 * sin(t * 2 * .pi * 11)
            data[i] = Float(y * 0.5 * attack * release * flutter)
        }
        // Bubbles, getting higher as the bottle fills.
        var t = 0.04
        while t < duration {
            let f0 = Double.random(in: 520...760) * (1 + t / duration * 0.7)
            addBloop(&data, frames: frames, start: t, f0: f0, gain: Double.random(in: 0.12...0.3))
            t += Double.random(in: 0.03...0.09)
        }
        return Clip(samples: data)
    }

    private func chime() -> Clip {
        let frames = Int(1.8 * sampleRate)
        var data = [Float](repeating: 0, count: frames)
        let sr = sampleRate
        // E5, G#5, B5, then a high E as a sparkle.
        let notes: [(f: Double, start: Double, gain: Double)] = [
            (659.25, 0.0, 0.32), (830.61, 0.09, 0.28), (987.77, 0.18, 0.26), (1318.5, 0.3, 0.16),
        ]
        for note in notes {
            let first = Int(note.start * sr)
            for i in 0..<(frames - first) {
                let t = Double(i) / sr
                let env = min(t / 0.006, 1) * exp(-t * 3.2)
                let s = sin(2 * .pi * note.f * t) + 0.18 * sin(2 * .pi * note.f * 2 * t) + 0.06 * sin(2 * .pi * note.f * 3 * t)
                data[first + i] += Float(s * env * note.gain)
            }
        }
        return Clip(samples: data)
    }
}
