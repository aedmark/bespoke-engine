// Built-in 5x7 ASCII bitmap font (ASCII 32 to 126).
// 5 bytes per character, 1 byte per column (bit 0 = top, bit 6 = bottom).

pub const FONT_WIDTH = 5;
pub const FONT_HEIGHT = 7;

pub const FONT5X7 = [95][5]u8{
    .{ 0x00, 0x00, 0x00, 0x00, 0x00 }, // ' ' (32)
    .{ 0x00, 0x00, 0x5F, 0x00, 0x00 }, // '!' (33)
    .{ 0x00, 0x07, 0x00, 0x07, 0x00 }, // '"' (34)
    .{ 0x14, 0x7F, 0x14, 0x7F, 0x14 }, // '#' (35)
    .{ 0x24, 0x2A, 0x7F, 0x2A, 0x12 }, // '$' (36)
    .{ 0x23, 0x13, 0x08, 0x64, 0x62 }, // '%' (37)
    .{ 0x36, 0x49, 0x55, 0x22, 0x50 }, // '&' (38)
    .{ 0x00, 0x05, 0x03, 0x00, 0x00 }, // ''' (39)
    .{ 0x00, 0x1C, 0x22, 0x41, 0x00 }, // '(' (40)
    .{ 0x00, 0x41, 0x22, 0x1C, 0x00 }, // ')' (41)
    .{ 0x14, 0x08, 0x3E, 0x08, 0x14 }, // '*' (42)
    .{ 0x08, 0x08, 0x3E, 0x08, 0x08 }, // '+' (43)
    .{ 0x00, 0x50, 0x30, 0x00, 0x00 }, // ',' (44)
    .{ 0x08, 0x08, 0x08, 0x08, 0x08 }, // '-' (45)
    .{ 0x00, 0x60, 0x60, 0x00, 0x00 }, // '.' (46)
    .{ 0x20, 0x10, 0x08, 0x04, 0x02 }, // '/' (47)
    .{ 0x3E, 0x51, 0x49, 0x45, 0x3E }, // '0' (48)
    .{ 0x00, 0x42, 0x7F, 0x40, 0x00 }, // '1' (49)
    .{ 0x42, 0x61, 0x51, 0x49, 0x46 }, // '2' (50)
    .{ 0x21, 0x41, 0x45, 0x4B, 0x31 }, // '3' (51)
    .{ 0x18, 0x14, 0x12, 0x7F, 0x10 }, // '4' (52)
    .{ 0x27, 0x45, 0x45, 0x45, 0x39 }, // '5' (53)
    .{ 0x3C, 0x4A, 0x49, 0x49, 0x30 }, // '6' (54)
    .{ 0x01, 0x71, 0x09, 0x05, 0x03 }, // '7' (55)
    .{ 0x36, 0x49, 0x49, 0x49, 0x36 }, // '8' (56)
    .{ 0x06, 0x49, 0x49, 0x29, 0x1E }, // '9' (57)
    .{ 0x00, 0x36, 0x36, 0x00, 0x00 }, // ':' (58)
    .{ 0x00, 0x56, 0x36, 0x00, 0x00 }, // ';' (59)
    .{ 0x08, 0x14, 0x22, 0x41, 0x00 }, // '<' (60)
    .{ 0x14, 0x14, 0x14, 0x14, 0x14 }, // '=' (61)
    .{ 0x00, 0x41, 0x22, 0x14, 0x08 }, // '>' (62)
    .{ 0x02, 0x01, 0x51, 0x09, 0x06 }, // '?' (63)
    .{ 0x32, 0x49, 0x79, 0x41, 0x3E }, // '@' (64)
    .{ 0x7E, 0x11, 0x11, 0x11, 0x7E }, // 'A' (65)
    .{ 0x7F, 0x49, 0x49, 0x49, 0x36 }, // 'B' (66)
    .{ 0x3E, 0x41, 0x41, 0x41, 0x22 }, // 'C' (67)
    .{ 0x7F, 0x41, 0x41, 0x22, 0x1C }, // 'D' (68)
    .{ 0x7F, 0x49, 0x49, 0x49, 0x41 }, // 'E' (69)
    .{ 0x7F, 0x09, 0x09, 0x09, 0x01 }, // 'F' (70)
    .{ 0x3E, 0x41, 0x49, 0x49, 0x7A }, // 'G' (71)
    .{ 0x7F, 0x08, 0x08, 0x08, 0x7F }, // 'H' (72)
    .{ 0x00, 0x41, 0x7F, 0x41, 0x00 }, // 'I' (73)
    .{ 0x20, 0x40, 0x41, 0x3F, 0x01 }, // 'J' (74)
    .{ 0x7F, 0x08, 0x14, 0x22, 0x41 }, // 'K' (75)
    .{ 0x7F, 0x40, 0x40, 0x40, 0x40 }, // 'L' (76)
    .{ 0x7F, 0x02, 0x0C, 0x02, 0x7F }, // 'M' (77)
    .{ 0x7F, 0x04, 0x08, 0x10, 0x7F }, // 'N' (78)
    .{ 0x3E, 0x41, 0x41, 0x41, 0x3E }, // 'O' (79)
    .{ 0x7F, 0x09, 0x09, 0x09, 0x06 }, // 'P' (80)
    .{ 0x3E, 0x41, 0x51, 0x21, 0x5E }, // 'Q' (81)
    .{ 0x7F, 0x09, 0x19, 0x29, 0x46 }, // 'R' (82)
    .{ 0x46, 0x49, 0x49, 0x49, 0x31 }, // 'S' (83)
    .{ 0x01, 0x01, 0x7F, 0x01, 0x01 }, // 'T' (84)
    .{ 0x3F, 0x40, 0x40, 0x40, 0x3F }, // 'U' (85)
    .{ 0x1F, 0x20, 0x40, 0x20, 0x1F }, // 'V' (86)
    .{ 0x7F, 0x20, 0x18, 0x20, 0x7F }, // 'W' (87)
    .{ 0x63, 0x14, 0x08, 0x14, 0x63 }, // 'X' (88)
    .{ 0x07, 0x08, 0x70, 0x08, 0x07 }, // 'Y' (89)
    .{ 0x61, 0x51, 0x49, 0x45, 0x43 }, // 'Z' (90)
    .{ 0x00, 0x7F, 0x41, 0x41, 0x00 }, // '[' (91)
    .{ 0x02, 0x04, 0x08, 0x10, 0x20 }, // '\' (92)
    .{ 0x00, 0x41, 0x41, 0x7F, 0x00 }, // ']' (93)
    .{ 0x04, 0x02, 0x01, 0x02, 0x04 }, // '^' (94)
    .{ 0x40, 0x40, 0x40, 0x40, 0x40 }, // '_' (95)
    .{ 0x00, 0x01, 0x02, 0x04, 0x00 }, // '`' (96)
    .{ 0x20, 0x54, 0x54, 0x54, 0x78 }, // 'a' (97)
    .{ 0x7F, 0x48, 0x44, 0x44, 0x38 }, // 'b' (98)
    .{ 0x38, 0x44, 0x44, 0x44, 0x20 }, // 'c' (99)
    .{ 0x38, 0x44, 0x44, 0x48, 0x7F }, // 'd' (100)
    .{ 0x38, 0x54, 0x54, 0x54, 0x18 }, // 'e' (101)
    .{ 0x08, 0x7E, 0x09, 0x01, 0x02 }, // 'f' (102)
    .{ 0x0C, 0x52, 0x52, 0x52, 0x3E }, // 'g' (103)
    .{ 0x7F, 0x08, 0x04, 0x04, 0x78 }, // 'h' (104)
    .{ 0x00, 0x44, 0x7D, 0x40, 0x00 }, // 'i' (105)
    .{ 0x20, 0x40, 0x44, 0x3D, 0x00 }, // 'j' (106)
    .{ 0x7F, 0x10, 0x28, 0x44, 0x00 }, // 'k' (107)
    .{ 0x00, 0x41, 0x7F, 0x40, 0x00 }, // 'l' (108)
    .{ 0x7C, 0x04, 0x18, 0x04, 0x78 }, // 'm' (109)
    .{ 0x7C, 0x08, 0x04, 0x04, 0x78 }, // 'n' (110)
    .{ 0x38, 0x44, 0x44, 0x44, 0x38 }, // 'o' (111)
    .{ 0x7C, 0x14, 0x14, 0x14, 0x08 }, // 'p' (112)
    .{ 0x08, 0x14, 0x14, 0x18, 0x7C }, // 'q' (113)
    .{ 0x7C, 0x08, 0x04, 0x04, 0x08 }, // 'r' (114)
    .{ 0x48, 0x54, 0x54, 0x54, 0x20 }, // 's' (115)
    .{ 0x04, 0x3F, 0x44, 0x40, 0x20 }, // 't' (116)
    .{ 0x3C, 0x40, 0x40, 0x20, 0x7C }, // 'u' (117)
    .{ 0x1C, 0x20, 0x40, 0x20, 0x1C }, // 'v' (118)
    .{ 0x3C, 0x40, 0x30, 0x40, 0x3C }, // 'w' (119)
    .{ 0x44, 0x28, 0x10, 0x28, 0x44 }, // 'x' (120)
    .{ 0x0C, 0x50, 0x50, 0x50, 0x3C }, // 'y' (121)
    .{ 0x44, 0x64, 0x54, 0x4C, 0x44 }, // 'z' (122)
    .{ 0x00, 0x08, 0x36, 0x41, 0x00 }, // '{' (123)
    .{ 0x00, 0x00, 0x7F, 0x00, 0x00 }, // '|' (124)
    .{ 0x00, 0x41, 0x36, 0x08, 0x00 }, // '}' (125)
    .{ 0x08, 0x08, 0x2A, 0x1C, 0x08 }, // '~' (126)
};

pub const CHAR_SPACING = 1;

pub fn char_width(scale: i32) i32 {
    return (FONT_WIDTH + CHAR_SPACING) * scale;
}

const std = @import("std");

/// What an unsupported code point or invalid UTF-8 byte draws as (D-179, P48-21).
pub const PLACEHOLDER: u8 = '?';

pub const Glyph = [FONT_WIDTH]u8;

fn combine(base: Glyph, diacritic: Glyph) Glyph {
    var out = base;
    for (0..FONT_WIDTH) |i| out[i] |= diacritic[i];
    return out;
}

// Compact uppercase bases sitting in rows 2..6 (bits 2..6), leaving rows 0..1 for accents.
const CAP_A: Glyph = .{ 0x78, 0x14, 0x14, 0x14, 0x78 };
const CAP_C: Glyph = .{ 0x38, 0x44, 0x44, 0x44, 0x28 };
const CAP_E: Glyph = .{ 0x7C, 0x54, 0x54, 0x54, 0x44 };
const CAP_G: Glyph = .{ 0x38, 0x44, 0x54, 0x54, 0x34 };
const CAP_I: Glyph = .{ 0x00, 0x44, 0x7C, 0x44, 0x00 };
const CAP_N: Glyph = .{ 0x7C, 0x08, 0x10, 0x20, 0x7C };
const CAP_O: Glyph = .{ 0x38, 0x44, 0x44, 0x44, 0x38 };
const CAP_R: Glyph = .{ 0x7C, 0x14, 0x14, 0x34, 0x48 };
const CAP_S: Glyph = .{ 0x48, 0x54, 0x54, 0x54, 0x24 };
const CAP_U: Glyph = .{ 0x3C, 0x40, 0x40, 0x40, 0x3C };
const CAP_Y: Glyph = .{ 0x04, 0x08, 0x70, 0x08, 0x04 };
const CAP_Z: Glyph = .{ 0x44, 0x64, 0x54, 0x4C, 0x44 };

// Lowercase bases sitting in rows 2..6 (bits 2..6).
const LOW_A: Glyph = FONT5X7['a' - 32];
const LOW_C: Glyph = FONT5X7['c' - 32];
const LOW_E: Glyph = FONT5X7['e' - 32];
const LOW_G: Glyph = .{ 0x18, 0x54, 0x54, 0x54, 0x3C };
const LOW_I: Glyph = .{ 0x00, 0x44, 0x7C, 0x40, 0x00 };
const LOW_N: Glyph = FONT5X7['n' - 32];
const LOW_O: Glyph = FONT5X7['o' - 32];
const LOW_R: Glyph = FONT5X7['r' - 32];
const LOW_S: Glyph = FONT5X7['s' - 32];
const LOW_U: Glyph = FONT5X7['u' - 32];
const LOW_Y: Glyph = FONT5X7['y' - 32];
const LOW_Z: Glyph = FONT5X7['z' - 32];

// Diacritics occupying rows 0..1 (bits 0..1).
const ACC_GRAVE: Glyph = .{ 0x00, 0x01, 0x02, 0x00, 0x00 };
const ACC_ACUTE: Glyph = .{ 0x00, 0x00, 0x02, 0x01, 0x00 };
const ACC_CIRC: Glyph = .{ 0x00, 0x02, 0x01, 0x02, 0x00 };
const ACC_TILDE: Glyph = .{ 0x02, 0x01, 0x02, 0x01, 0x00 };
const ACC_DIAER: Glyph = .{ 0x00, 0x01, 0x00, 0x01, 0x00 };
const ACC_RING: Glyph = .{ 0x00, 0x03, 0x01, 0x03, 0x00 };
const ACC_CARON: Glyph = .{ 0x00, 0x01, 0x02, 0x01, 0x00 };
const ACC_BREVE: Glyph = .{ 0x01, 0x02, 0x02, 0x01, 0x00 };
const ACC_DOT: Glyph = .{ 0x00, 0x00, 0x01, 0x00, 0x00 };

/// Latin-1 Supplement (U+00A0 to U+00FF) in the same 5x7 column format as `FONT5X7`.
pub const LATIN1 = [96]Glyph{
    .{ 0x00, 0x00, 0x00, 0x00, 0x00 }, // U+00A0 NO-BREAK SPACE
    .{ 0x00, 0x00, 0x7D, 0x00, 0x00 }, // U+00A1 '¡'
    .{ 0x1C, 0x22, 0x7F, 0x22, 0x14 }, // U+00A2 '¢'
    .{ 0x48, 0x7E, 0x49, 0x49, 0x42 }, // U+00A3 '£'
    .{ 0x22, 0x1C, 0x14, 0x1C, 0x22 }, // U+00A4 '¤'
    .{ 0x2B, 0x2C, 0x78, 0x2C, 0x2B }, // U+00A5 '¥'
    .{ 0x00, 0x00, 0x67, 0x00, 0x00 }, // U+00A6 '¦'
    .{ 0x26, 0x49, 0x55, 0x49, 0x32 }, // U+00A7 '§'
    .{ 0x00, 0x03, 0x00, 0x03, 0x00 }, // U+00A8 '¨'
    .{ 0x3E, 0x41, 0x5D, 0x55, 0x3E }, // U+00A9 '©'
    .{ 0x28, 0x36, 0x36, 0x2E, 0x00 }, // U+00AA 'ª'
    .{ 0x08, 0x14, 0x2A, 0x14, 0x22 }, // U+00AB '«'
    .{ 0x08, 0x08, 0x08, 0x08, 0x18 }, // U+00AC '¬'
    .{ 0x00, 0x00, 0x00, 0x00, 0x00 }, // U+00AD SOFT HYPHEN
    .{ 0x3E, 0x7F, 0x59, 0x69, 0x3E }, // U+00AE '®'
    .{ 0x01, 0x01, 0x01, 0x01, 0x01 }, // U+00AF '¯'
    .{ 0x00, 0x07, 0x05, 0x07, 0x00 }, // U+00B0 '°'
    .{ 0x24, 0x24, 0x2F, 0x24, 0x24 }, // U+00B1 '±'
    .{ 0x12, 0x19, 0x15, 0x12, 0x00 }, // U+00B2 '²'
    .{ 0x11, 0x15, 0x1B, 0x00, 0x00 }, // U+00B3 '³'
    .{ 0x00, 0x00, 0x02, 0x01, 0x00 }, // U+00B4 '´'
    .{ 0x7C, 0x20, 0x20, 0x1C, 0x20 }, // U+00B5 'µ'
    .{ 0x06, 0x0F, 0x7F, 0x01, 0x7F }, // U+00B6 '¶'
    .{ 0x00, 0x00, 0x08, 0x00, 0x00 }, // U+00B7 '·'
    .{ 0x00, 0x40, 0x60, 0x00, 0x00 }, // U+00B8 '¸'
    .{ 0x00, 0x12, 0x1F, 0x10, 0x00 }, // U+00B9 '¹'
    .{ 0x00, 0x0E, 0x2A, 0x2E, 0x00 }, // U+00BA 'º'
    .{ 0x22, 0x14, 0x2A, 0x14, 0x08 }, // U+00BB '»'
    .{ 0x17, 0x08, 0x64, 0x52, 0x70 }, // U+00BC '¼'
    .{ 0x17, 0x08, 0x44, 0x6A, 0x50 }, // U+00BD '½'
    .{ 0x15, 0x0F, 0x64, 0x52, 0x70 }, // U+00BE '¾'
    .{ 0x30, 0x48, 0x45, 0x40, 0x20 }, // U+00BF '¿'
    combine(CAP_A, ACC_GRAVE), // U+00C0 'À'
    combine(CAP_A, ACC_ACUTE), // U+00C1 'Á'
    combine(CAP_A, ACC_CIRC), // U+00C2 'Â'
    combine(CAP_A, ACC_TILDE), // U+00C3 'Ã'
    combine(CAP_A, ACC_DIAER), // U+00C4 'Ä'
    combine(CAP_A, ACC_RING), // U+00C5 'Å'
    .{ 0x7E, 0x09, 0x7F, 0x49, 0x41 }, // U+00C6 'Æ'
    .{ 0x1E, 0x21, 0x61, 0x61, 0x12 }, // U+00C7 'Ç'
    combine(CAP_E, ACC_GRAVE), // U+00C8 'È'
    combine(CAP_E, ACC_ACUTE), // U+00C9 'É'
    combine(CAP_E, ACC_CIRC), // U+00CA 'Ê'
    combine(CAP_E, ACC_DIAER), // U+00CB 'Ë'
    combine(CAP_I, ACC_GRAVE), // U+00CC 'Ì'
    combine(CAP_I, ACC_ACUTE), // U+00CD 'Í'
    combine(CAP_I, ACC_CIRC), // U+00CE 'Î'
    combine(CAP_I, ACC_DIAER), // U+00CF 'Ï'
    .{ 0x08, 0x7F, 0x49, 0x41, 0x3E }, // U+00D0 'Ð'
    combine(CAP_N, ACC_TILDE), // U+00D1 'Ñ'
    combine(CAP_O, ACC_GRAVE), // U+00D2 'Ò'
    combine(CAP_O, ACC_ACUTE), // U+00D3 'Ó'
    combine(CAP_O, ACC_CIRC), // U+00D4 'Ô'
    combine(CAP_O, ACC_TILDE), // U+00D5 'Õ'
    combine(CAP_O, ACC_DIAER), // U+00D6 'Ö'
    .{ 0x22, 0x14, 0x08, 0x14, 0x22 }, // U+00D7 '×'
    .{ 0x7E, 0x61, 0x59, 0x47, 0x3F }, // U+00D8 'Ø'
    combine(CAP_U, ACC_GRAVE), // U+00D9 'Ù'
    combine(CAP_U, ACC_ACUTE), // U+00DA 'Ú'
    combine(CAP_U, ACC_CIRC), // U+00DB 'Û'
    combine(CAP_U, ACC_DIAER), // U+00DC 'Ü'
    combine(CAP_Y, ACC_ACUTE), // U+00DD 'Ý'
    .{ 0x7F, 0x12, 0x12, 0x12, 0x0C }, // U+00DE 'Þ'
    .{ 0x7E, 0x41, 0x49, 0x4A, 0x34 }, // U+00DF 'ß'
    combine(LOW_A, ACC_GRAVE), // U+00E0 'à'
    combine(LOW_A, ACC_ACUTE), // U+00E1 'á'
    combine(LOW_A, ACC_CIRC), // U+00E2 'â'
    combine(LOW_A, ACC_TILDE), // U+00E3 'ã'
    combine(LOW_A, ACC_DIAER), // U+00E4 'ä'
    combine(LOW_A, ACC_RING), // U+00E5 'å'
    .{ 0x30, 0x48, 0x38, 0x54, 0x58 }, // U+00E6 'æ'
    .{ 0x1C, 0x22, 0x62, 0x62, 0x14 }, // U+00E7 'ç'
    combine(LOW_E, ACC_GRAVE), // U+00E8 'è'
    combine(LOW_E, ACC_ACUTE), // U+00E9 'é'
    combine(LOW_E, ACC_CIRC), // U+00EA 'ê'
    combine(LOW_E, ACC_DIAER), // U+00EB 'ë'
    combine(LOW_I, ACC_GRAVE), // U+00EC 'ì'
    combine(LOW_I, ACC_ACUTE), // U+00ED 'í'
    combine(LOW_I, ACC_CIRC), // U+00EE 'î'
    combine(LOW_I, ACC_DIAER), // U+00EF 'ï'
    .{ 0x30, 0x4A, 0x4D, 0x4A, 0x30 }, // U+00F0 'ð'
    combine(LOW_N, ACC_TILDE), // U+00F1 'ñ'
    combine(LOW_O, ACC_GRAVE), // U+00F2 'ò'
    combine(LOW_O, ACC_ACUTE), // U+00F3 'ó'
    combine(LOW_O, ACC_CIRC), // U+00F4 'ô'
    combine(LOW_O, ACC_TILDE), // U+00F5 'õ'
    combine(LOW_O, ACC_DIAER), // U+00F6 'ö'
    .{ 0x08, 0x08, 0x2A, 0x08, 0x08 }, // U+00F7 '÷'
    .{ 0x78, 0x64, 0x54, 0x4C, 0x3C }, // U+00F8 'ø'
    combine(LOW_U, ACC_GRAVE), // U+00F9 'ù'
    combine(LOW_U, ACC_ACUTE), // U+00FA 'ú'
    combine(LOW_U, ACC_CIRC), // U+00FB 'û'
    combine(LOW_U, ACC_DIAER), // U+00FC 'ü'
    combine(LOW_Y, ACC_ACUTE), // U+00FD 'ý'
    .{ 0x7F, 0x24, 0x24, 0x24, 0x18 }, // U+00FE 'þ'
    combine(LOW_Y, ACC_DIAER), // U+00FF 'ÿ'
};

const ExtraGlyph = struct {
    cp: u21,
    glyph: Glyph,
};

/// Sorted Latin Extended-A letters and common typographic punctuation outside Latin-1.
pub const EXTRA_GLYPHS = [_]ExtraGlyph{
    .{ .cp = 0x0104, .glyph = .{ 0x3E, 0x09, 0x09, 0x29, 0x7E } }, // 'Ą'
    .{ .cp = 0x0105, .glyph = .{ 0x10, 0x2A, 0x2A, 0x6A, 0x3E } }, // 'ą'
    .{ .cp = 0x0106, .glyph = combine(CAP_C, ACC_ACUTE) }, // 'Ć'
    .{ .cp = 0x0107, .glyph = combine(LOW_C, ACC_ACUTE) }, // 'ć'
    .{ .cp = 0x010C, .glyph = combine(CAP_C, ACC_CARON) }, // 'Č'
    .{ .cp = 0x010D, .glyph = combine(LOW_C, ACC_CARON) }, // 'č'
    .{ .cp = 0x0118, .glyph = .{ 0x3F, 0x25, 0x25, 0x65, 0x21 } }, // 'Ę'
    .{ .cp = 0x0119, .glyph = .{ 0x1C, 0x2A, 0x2A, 0x6A, 0x0C } }, // 'ę'
    .{ .cp = 0x011A, .glyph = combine(CAP_E, ACC_CARON) }, // 'Ě'
    .{ .cp = 0x011B, .glyph = combine(LOW_E, ACC_CARON) }, // 'ě'
    .{ .cp = 0x011E, .glyph = combine(CAP_G, ACC_BREVE) }, // 'Ğ'
    .{ .cp = 0x011F, .glyph = combine(LOW_G, ACC_BREVE) }, // 'ğ'
    .{ .cp = 0x0130, .glyph = combine(CAP_I, ACC_DOT) }, // 'İ'
    .{ .cp = 0x0131, .glyph = LOW_I }, // 'ı'
    .{ .cp = 0x0141, .glyph = .{ 0x7F, 0x48, 0x44, 0x40, 0x40 } }, // 'Ł'
    .{ .cp = 0x0142, .glyph = .{ 0x00, 0x49, 0x7F, 0x44, 0x00 } }, // 'ł'
    .{ .cp = 0x0143, .glyph = combine(CAP_N, ACC_ACUTE) }, // 'Ń'
    .{ .cp = 0x0144, .glyph = combine(LOW_N, ACC_ACUTE) }, // 'ń'
    .{ .cp = 0x0152, .glyph = .{ 0x3E, 0x41, 0x7F, 0x49, 0x41 } }, // 'Œ'
    .{ .cp = 0x0153, .glyph = .{ 0x38, 0x44, 0x38, 0x54, 0x58 } }, // 'œ'
    .{ .cp = 0x0158, .glyph = combine(CAP_R, ACC_CARON) }, // 'Ř'
    .{ .cp = 0x0159, .glyph = combine(LOW_R, ACC_CARON) }, // 'ř'
    .{ .cp = 0x015A, .glyph = combine(CAP_S, ACC_ACUTE) }, // 'Ś'
    .{ .cp = 0x015B, .glyph = combine(LOW_S, ACC_ACUTE) }, // 'ś'
    .{ .cp = 0x015E, .glyph = .{ 0x22, 0x25, 0x65, 0x65, 0x18 } }, // 'Ş'
    .{ .cp = 0x015F, .glyph = .{ 0x14, 0x2A, 0x6A, 0x6A, 0x08 } }, // 'ş'
    .{ .cp = 0x0160, .glyph = combine(CAP_S, ACC_CARON) }, // 'Š'
    .{ .cp = 0x0161, .glyph = combine(LOW_S, ACC_CARON) }, // 'š'
    .{ .cp = 0x016E, .glyph = combine(CAP_U, ACC_RING) }, // 'Ů'
    .{ .cp = 0x016F, .glyph = combine(LOW_U, ACC_RING) }, // 'ů'
    .{ .cp = 0x0178, .glyph = combine(CAP_Y, ACC_DIAER) }, // 'Ÿ'
    .{ .cp = 0x0179, .glyph = combine(CAP_Z, ACC_ACUTE) }, // 'Ź'
    .{ .cp = 0x017A, .glyph = combine(LOW_Z, ACC_ACUTE) }, // 'ź'
    .{ .cp = 0x017B, .glyph = combine(CAP_Z, ACC_DOT) }, // 'Ż'
    .{ .cp = 0x017C, .glyph = combine(LOW_Z, ACC_DOT) }, // 'ż'
    .{ .cp = 0x017D, .glyph = combine(CAP_Z, ACC_CARON) }, // 'Ž'
    .{ .cp = 0x017E, .glyph = combine(LOW_Z, ACC_CARON) }, // 'ž'
    .{ .cp = 0x2013, .glyph = .{ 0x00, 0x08, 0x08, 0x08, 0x00 } }, // U+2013 EN DASH
    .{ .cp = 0x2014, .glyph = .{ 0x08, 0x08, 0x08, 0x08, 0x08 } }, // U+2014 EM DASH
    .{ .cp = 0x2018, .glyph = .{ 0x00, 0x06, 0x05, 0x00, 0x00 } }, // '‘'
    .{ .cp = 0x2019, .glyph = .{ 0x00, 0x00, 0x05, 0x03, 0x00 } }, // '’'
    .{ .cp = 0x201C, .glyph = .{ 0x06, 0x05, 0x00, 0x06, 0x05 } }, // '“'
    .{ .cp = 0x201D, .glyph = .{ 0x05, 0x03, 0x00, 0x05, 0x03 } }, // '”'
    .{ .cp = 0x2026, .glyph = .{ 0x40, 0x00, 0x40, 0x00, 0x40 } }, // '…' HORIZONTAL ELLIPSIS
    .{ .cp = 0x20AC, .glyph = .{ 0x14, 0x3E, 0x55, 0x55, 0x22 } }, // '€'
};

/// Decodes the next UTF-8 code point starting at `index.*` and advances past it. On an
/// invalid or truncated byte sequence, advances by one byte and returns `PLACEHOLDER`.
pub fn next_codepoint(text: []const u8, index: *usize) ?u21 {
    if (index.* >= text.len) return null;
    const b0 = text[index.*];
    if (b0 < 0x80) {
        index.* += 1;
        return b0;
    }
    const seq_len = std.unicode.utf8ByteSequenceLength(b0) catch {
        index.* += 1;
        return PLACEHOLDER;
    };
    if (index.* + seq_len > text.len) {
        index.* += 1;
        return PLACEHOLDER;
    }
    const cp = std.unicode.utf8Decode(text[index.* .. index.* + seq_len]) catch {
        index.* += 1;
        return PLACEHOLDER;
    };
    index.* += seq_len;
    return cp;
}

/// Returns the 5x7 glyph bitmap for `cp`, null for ASCII control codes (which advance without
/// painting pixels), or the `PLACEHOLDER` glyph when `cp` is outside the font's tables.
pub fn glyph_for(cp: u21) ?Glyph {
    if (cp >= 32 and cp <= 126) return FONT5X7[@intCast(cp - 32)];
    if (cp < 128) return null;
    if (cp >= 0xA0 and cp <= 0xFF) return LATIN1[@intCast(cp - 0xA0)];
    var lo: usize = 0;
    var hi: usize = EXTRA_GLYPHS.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        const entry = EXTRA_GLYPHS[mid];
        if (entry.cp == cp) return entry.glyph;
        if (entry.cp < cp) lo = mid + 1 else hi = mid;
    }
    return FONT5X7[PLACEHOLDER - 32];
}

/// Characters drawn, not bytes: matches the exact number of glyphs `Canvas.draw_text` paints.
pub fn char_count(text: []const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (next_codepoint(text, &i) != null) n += 1;
    return n;
}

/// Longest valid UTF-8 prefix of `text` holding at most `max_chars` characters, fitting within
/// `max_bytes` bytes (never splitting a multi-byte code point).
pub fn prefix_chars_fit(text: []const u8, max_chars: usize, max_bytes: usize) []const u8 {
    var i: usize = 0;
    var n: usize = 0;
    const limit = @min(text.len, max_bytes);
    while (n < max_chars and i < limit) {
        const clen = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
        if (i + clen > limit) break;
        i += clen;
        n += 1;
    }
    return text[0..i];
}

/// Longest UTF-8 prefix of `text` holding at most `max_chars` characters.
pub fn prefix_chars(text: []const u8, max_chars: usize) []const u8 {
    return prefix_chars_fit(text, max_chars, text.len);
}

/// Longest UTF-8 prefix of `text` fitting inside `max_bytes` bytes without splitting a character.
pub fn truncate_utf8(text: []const u8, max_bytes: usize) []const u8 {
    if (text.len <= max_bytes) return text;
    var i: usize = 0;
    while (i < max_bytes) {
        const clen = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
        if (i + clen > max_bytes) break;
        i += clen;
    }
    return text[0..i];
}

pub fn text_width(text: []const u8, scale: i32) i32 {
    if (text.len == 0) return 0;
    return @as(i32, @intCast(char_count(text))) * char_width(scale);
}

test "P48-09: UTF-8 measures one character per code point" {
    try std.testing.expectEqual(@as(usize, 6), char_count("H\xc3\xa9l\xc3\xa8ne"));
    try std.testing.expectEqual(text_width("Helene", 1), text_width("H\xc3\xa9l\xc3\xa8ne", 1));
}

test "font glyph lookup and width calculation" {
    try std.testing.expectEqual(@as(usize, 95), FONT5X7.len);
    try std.testing.expectEqual(@as(usize, 96), LATIN1.len);
    try std.testing.expectEqual(@as(i32, 12), char_width(2));
    try std.testing.expectEqual(@as(i32, 60), text_width("Hello", 2));
}

test "P48-21: Latin-1 and Extended-A glyphs are valid, sorted, and distinct from placeholder" {
    const testing = std.testing;
    const qmark = FONT5X7[PLACEHOLDER - 32];

    for (1..EXTRA_GLYPHS.len) |i| {
        try testing.expect(EXTRA_GLYPHS[i - 1].cp < EXTRA_GLYPHS[i].cp);
    }

    for (FONT5X7, 32..) |g, cp| {
        var lit = false;
        for (g) |col| {
            try testing.expectEqual(@as(u8, 0), col & 0x80);
            if (col != 0) lit = true;
        }
        if (cp != ' ') try testing.expect(lit);
    }

    for (LATIN1, 0xA0..) |g, cp| {
        var lit = false;
        for (g) |col| {
            try testing.expectEqual(@as(u8, 0), col & 0x80);
            if (col != 0) lit = true;
        }
        if (cp != 0xA0 and cp != 0xAD) try testing.expect(lit);
        if (cp >= 0xC0 and cp != 0xD7 and cp != 0xF7) {
            try testing.expect(!std.mem.eql(u8, &g, &qmark));
            try testing.expectEqual(g, glyph_for(@intCast(cp)).?);
        }
    }

    for (EXTRA_GLYPHS) |entry| {
        var lit = false;
        for (entry.glyph) |col| {
            try testing.expectEqual(@as(u8, 0), col & 0x80);
            if (col != 0) lit = true;
        }
        try testing.expect(lit);
        try testing.expect(!std.mem.eql(u8, &entry.glyph, &qmark));
        try testing.expectEqual(entry.glyph, glyph_for(entry.cp).?);
    }

    // Accented variants are distinct from one another and unsupported scripts fall back to '?'.
    try testing.expect(!std.mem.eql(u8, &glyph_for(0x00C2).?, &glyph_for(0x00C5).?)); // Â vs Å
    try testing.expect(!std.mem.eql(u8, &glyph_for(0x00E2).?, &glyph_for(0x00E5).?)); // â vs å
    try testing.expect(!std.mem.eql(u8, &glyph_for(0x00E8).?, &glyph_for(0x00E9).?)); // è vs é
    try testing.expect(!std.mem.eql(u8, &glyph_for(0x00E9).?, &glyph_for(0x00EA).?)); // é vs ê
    try testing.expect(!std.mem.eql(u8, &glyph_for(0x00EA).?, &glyph_for(0x00EB).?)); // ê vs ë
    try testing.expectEqual(qmark, glyph_for(0x03BB).?); // 'λ'
    try testing.expect(glyph_for('\n') == null);
}

test "P48-21: UTF-8 prefix and truncation helpers count characters and never split sequences" {
    const testing = std.testing;
    const cafe = "Caf\xc3\xa9 de l'\xc5\x92il";
    try testing.expectEqualStrings("Caf\xc3\xa9", prefix_chars(cafe, 4));
    try testing.expectEqualStrings("Caf", prefix_chars_fit(cafe, 5, 4));
    try testing.expectEqualStrings("Caf\xc3\xa9", truncate_utf8(cafe, 5));
    try testing.expectEqualStrings("Caf", truncate_utf8(cafe, 4));

    // Malformed / truncated bytes do not crash and advance safely by 1 byte.
    const bad = [_]u8{ 'A', 0xFF, 0xC3, 'B' };
    try testing.expectEqual(@as(usize, 4), char_count(&bad));
    var idx: usize = 0;
    try testing.expectEqual(@as(?u21, 'A'), next_codepoint(&bad, &idx));
    try testing.expectEqual(@as(?u21, PLACEHOLDER), next_codepoint(&bad, &idx));
    try testing.expectEqual(@as(?u21, PLACEHOLDER), next_codepoint(&bad, &idx));
    try testing.expectEqual(@as(?u21, 'B'), next_codepoint(&bad, &idx));
    try testing.expectEqual(@as(?u21, null), next_codepoint(&bad, &idx));
}
