"""Chops the Royal UR piece-move recording into round-robin samples.

A ONE-OFF. Unlike every other tool here it is NOT zero-dependency and is NOT
part of the verifier sweep: there is no ffmpeg, numpy or MP3 decoder in a
bare container, so this needs

    pip install numpy miniaudio

It runs once, its output is committed, and after that nothing depends on it.
Kept in the repo anyway because the alternative — a folder of sliced WAVs
with no record of where the cuts came from or why — is the thing that makes
audio assets unmaintainable.

The source is `Ur pieces moving on board sounds, chop needed.mp3`, 23.0s of
a piece being set down on a board over and over with silence between. The
cuts are found rather than typed: an RMS envelope at 10ms, a threshold
relative to the recording's own noise floor, and a minimum gap so one
sound's decay cannot register as the next one's attack.

    python3 tools_sfx_slice.py --report    # onsets and measurements only
    python3 tools_sfx_slice.py --write     # write Resources/sfx_ur_move_*
"""
import os
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "Resources")
SRC = ("/tmp/claude-0/-home-user-Rolls/00f63c33-a200-5537-8c48-d7af637c530d"
       "/scratchpad/sfx/SFX/UR/Ur pieces moving on board sounds, chop needed.mp3")

PREFIX = "sfx_ur_move"

# 10ms analysis frames — short enough to put an onset within a frame of where
# it really is, long enough that one noisy sample cannot trip the threshold.
FRAME_MS = 0.010

# How far above the recording's own noise floor counts as a hit.
#
# Measured rather than guessed: at 6x this finds 17 onsets, at 10x it finds
# 13, at 16x it finds 10 that are evenly spread across the whole recording.
# The extra ones at the lower thresholds all cluster between 10s and 12s,
# which is one rapid sequence of moves being split into fragments rather than
# genuine separate hits.
THRESHOLD = 16.0

# No two onsets closer than this. A piece being set down rings for a while,
# and without this the tail re-triggers.
MIN_GAP = 0.25

# How much to keep around each hit. The lead-in matters: starting exactly at
# the detected onset clips the attack transient, which is the part that makes
# it sound like a piece landing rather than a thud.
LEAD_IN = 0.030
TAIL = 0.45

# Fade applied to each end of a slice, so a cut never lands mid-waveform and
# clicks. Short enough not to soften the attack.
FADE_IN = 0.002
FADE_OUT = 0.060

# Slices quieter than this are thrown away rather than shipped.
#
# The raw chop found one hit at 0.03 peak against a median of 0.26 — about
# 20dB down, which in a round-robin is every Nth piece move making no sound
# at all. A silent entry in a rotation does not read as variety, it reads as
# a bug, and it is the kind that is almost impossible to catch on device
# because it only surfaces one move in ten.
MIN_PEAK = 0.08

# Level-match what survives. A rotation whose members differ by 10dB sounds
# broken in a way a single sample never does.
TARGET_PEAK = 0.50

# ...but never amplify beyond this. The recording's noise floor rides up with
# the signal, so a big boost on a quiet hit buys loudness at the cost of
# audible hiss. Capping the gain means the quietest survivors stay a little
# quieter rather than becoming loud and dirty.
MAX_GAIN = 3.0

RATE = 44100


def load():
    import miniaudio
    decoded = miniaudio.decode_file(SRC)
    channels = decoded.nchannels
    samples = list(decoded.samples)
    mono = [sum(samples[i:i + channels]) / channels
            for i in range(0, len(samples) - channels + 1, channels)]
    return mono, decoded.sample_rate


def envelope(mono, rate):
    width = int(rate * FRAME_MS)
    count = len(mono) // width
    out = []
    for i in range(count):
        chunk = mono[i * width:(i + 1) * width]
        out.append((sum(v * v for v in chunk) / width) ** 0.5 / 32768.0)
    return out, width


def onsets(mono, rate):
    env, width = envelope(mono, rate)
    ordered = sorted(env)
    floor = ordered[len(ordered) // 5]          # 20th percentile
    peak = max(env)
    limit = max(floor * THRESHOLD, peak * 0.04)

    found, armed, last = [], True, -99.0
    for i, value in enumerate(env):
        at = i * width / rate
        if value > limit and armed and at - last > MIN_GAP:
            found.append(at)
            last = at
            armed = False
        if value < limit * 0.5:
            armed = True
    return found, floor, peak, limit


def slice_at(mono, rate, start):
    first = max(0, int((start - LEAD_IN) * rate))
    last = min(len(mono), int((start + TAIL) * rate))
    cut = mono[first:last]

    fade_in = int(FADE_IN * rate)
    fade_out = int(FADE_OUT * rate)
    for i in range(min(fade_in, len(cut))):
        cut[i] *= i / fade_in
    for i in range(min(fade_out, len(cut))):
        cut[len(cut) - 1 - i] *= i / fade_out
    return cut


def write_wav(path, samples, rate):
    """Mono 16-bit. Mono on purpose: these are point events on a board, and
    `DiceAudioEngine` positions them with its own `pan`, so a stereo source
    would fight the placement it is given."""
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        frames = bytearray()
        for value in samples:
            clipped = max(-32768, min(32767, int(value)))
            frames += int(clipped).to_bytes(2, "little", signed=True)
        out.writeframes(bytes(frames))


def main():
    write = "--write" in sys.argv
    mono, rate = load()
    found, floor, peak, limit = onsets(mono, rate)

    print("source      %.2fs at %d Hz" % (len(mono) / rate, rate))
    print("noise floor %.5f   peak %.3f   threshold %.5f" % (floor, peak, limit))
    print("onsets      %d\n" % len(found))
    print("  %-22s %7s %7s %7s" % ("file", "at", "secs", "peak"))

    kept, dropped = [], []
    for start in found:
        cut = slice_at(mono, rate, start)
        loudest = max(abs(v) for v in cut) / 32768.0
        (dropped if loudest < MIN_PEAK else kept).append((start, cut, loudest))

    index = 0
    for start, cut, loudest in kept:
        index += 1
        gain = min(TARGET_PEAK / loudest, MAX_GAIN)
        cut = [v * gain for v in cut]
        final = max(abs(v) for v in cut) / 32768.0
        name = "%s_%02d.wav" % (PREFIX, index)
        print("  %-22s %6.2fs %6.2fs %7.2f  x%.1f -> %.2f"
              % (name, start, len(cut) / rate, loudest, gain, final))
        if write:
            write_wav(os.path.join(RES, name), cut, rate)

    for start, _cut, loudest in dropped:
        print("  %-22s %6.2fs %6s %7.2f  DROPPED, under %.2f"
              % ("(none)", start, "-", loudest, MIN_PEAK))

    if write:
        print("\nwrote %d slices to Resources/ (%d dropped)"
              % (len(kept), len(dropped)))
    else:
        print("\n(report only — pass --write to emit the files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
