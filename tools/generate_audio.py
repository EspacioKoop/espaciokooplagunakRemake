"""Reproducible original interface, sensor and weapon effects; no external samples."""
from pathlib import Path
import math
import random
import struct
import wave

ROOT = Path(__file__).resolve().parents[1]
RATE = 22050
random.seed(710)

def write(name, duration, synthesizer):
    count = int(duration * RATE)
    with wave.open(str(ROOT / "game/assets/audio" / (name + ".wav")), "wb") as target:
        target.setparams((1, 2, RATE, count, "NONE", "not compressed"))
        samples = bytearray()
        for index in range(count):
            t = index / RATE
            envelope = min(1, t / 0.012) * max(0, 1 - t / duration) ** 2
            value = max(-1, min(1, synthesizer(t) * envelope))
            samples.extend(struct.pack("<h", int(value * 22000)))
        target.writeframes(samples)

write("pulse", .38, lambda t: .6 * math.sin(math.tau * (900 * t - 780 * t * t)) + .15 * random.uniform(-1, 1))
write("torpedo", 1.2, lambda t: .48 * math.sin(math.tau * (110 * t - 20 * t * t)) + .3 * random.uniform(-1, 1))
write("scan", .8, lambda t: .45 * math.sin(math.tau * (380 * t + 420 * t * t)) * (.5 + .5 * math.sin(math.tau * 8 * t)))
print("Generated pulse, torpedo and scan.")
