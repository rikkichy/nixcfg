#!/usr/bin/env python3

import math
import sys

ROLES = (
    ('body', 0.33, 0.055),
    ('outline', 0.83, 0.095),
    ('watch', 0.24, 0.045),
)


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def linear_to_srgb(c: float) -> float:
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def hex_to_oklch(value: str) -> tuple[float, float, float]:
    h = value.lstrip('#')
    if len(h) == 3:
        h = ''.join(c * 2 for c in h)
    if len(h) != 6:
        raise ValueError(f'not a hex colour: {value!r}')

    r, g, b = (srgb_to_linear(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4))

    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)

    lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s

    return lightness, math.hypot(a, bb), math.atan2(bb, a)


def oklch_to_rgb(lightness: float, chroma: float, hue: float) -> tuple[float, float, float]:
    a = chroma * math.cos(hue)
    b = chroma * math.sin(hue)

    l = (lightness + 0.3963377774 * a + 0.2158037573 * b) ** 3
    m = (lightness - 0.1055613458 * a - 0.0638541728 * b) ** 3
    s = (lightness - 0.0894841775 * a - 1.2914855480 * b) ** 3

    return (
        +4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    )


def in_gamut(rgb: tuple[float, float, float]) -> bool:
    return all(-1e-6 <= c <= 1 + 1e-6 for c in rgb)


def to_hex(lightness: float, chroma: float, hue: float) -> str:
    if not in_gamut(oklch_to_rgb(lightness, chroma, hue)):
        low, high = 0.0, chroma
        for _ in range(16):
            mid = (low + high) / 2
            if in_gamut(oklch_to_rgb(lightness, mid, hue)):
                low = mid
            else:
                high = mid
        chroma = low

    rgb = oklch_to_rgb(lightness, chroma, hue)
    return '#' + ''.join(
        f'{round(min(1.0, max(0.0, linear_to_srgb(c))) * 255):02x}' for c in rgb
    )


def main() -> None:
    if len(sys.argv) != 2:
        print('usage: bibata-tonal.py <accent-hex>', file=sys.stderr)
        raise SystemExit(1)

    _, chroma, hue = hex_to_oklch(sys.argv[1])

    for name, lightness, cap in ROLES:
        print(f'{name}={to_hex(lightness, min(chroma, cap), hue)}')


if __name__ == '__main__':
    main()
