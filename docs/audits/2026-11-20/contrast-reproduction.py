"""Solid sRGB neutral-token checks for the 2026-11-20 audit.

WCAG 2 relative luminance; APCA 0.0.98G-family reverse polarity equations.
This independent equation check is not a substitute for verifying the pinned
official apca-w3 implementation and its font lookup against rendered UI.
Reference: https://apcaw3.myndex.com/
"""


def wcag_y(level):
    component = level / 255.0
    return (component / 12.92 if component <= 0.04045
            else ((component + 0.055) / 1.055) ** 2.4)


def apca_y(level):
    # Neutral RGB weights sum to one, so a single component suffices.
    luminance = (level / 255.0) ** 2.4
    if luminance < 0.022:
        luminance += (0.022 - luminance) ** 1.414
    return luminance


def reverse_lc(text, background):
    text_y, background_y = apca_y(text), apca_y(background)
    if abs(background_y - text_y) < 0.0005:
        return 0.0
    sapc = (background_y ** 0.65 - text_y ** 0.62) * 1.14
    return 0.0 if sapc > -0.1 else (sapc + 0.027) * 100


if __name__ == "__main__":
    for ink in (0x83, 0xA4, 0xD4):
        for surface in (0x09, 0x18, 0x26):
            ratio = (wcag_y(ink) + 0.05) / (wcag_y(surface) + 0.05)
            lc = reverse_lc(ink, surface)
            print(f"#{ink:02X}{ink:02X}{ink:02X} on "
                  f"#{surface:02X}{surface:02X}{surface:02X}: "
                  f"WCAG {ratio:.2f}:1; APCA reverse Lc {lc:.1f}")
