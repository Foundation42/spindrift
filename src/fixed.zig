//! fixed — Q16.16 signed fixed point, the only number the sim knows.
//!
//! Positions are integer on the scene lattice (campaign §3.1, §7.3): the
//! high 16 bits of a coordinate are the lattice cell and the low 16 are the
//! sub-cell fraction, so a Morton key is a shift and a particle moving a
//! third of a cell per tick still moves (a pure lattice integer truncated
//! per tick would never get there — recon R-b §1). Velocity, size, colour
//! and the user channels ride the same format so every product in the
//! kernel is one i64 multiply and one shift.
//!
//! No float enters the sim loop. `toF64` exists for printing and
//! `parseDecimal` reads a decimal string with integer arithmetic, so a
//! knob typed as `9.8` lands on the same bits on every machine — G0 is
//! byte-identity and the campaign's G7 is a bit-identity gate only if the
//! arithmetic underneath it is integer (recon R-a §5).

const std = @import("std");

pub const Fixed = i32;
pub const FRAC_BITS: u5 = 16;
pub const ONE: Fixed = 1 << FRAC_BITS;
pub const HALF: Fixed = ONE / 2;
pub const Vec = [3]Fixed;

pub const zero_vec: Vec = .{ 0, 0, 0 };

pub fn fromInt(i: i32) Fixed {
    // Loud on overflow in Debug: a coordinate past ±32767 cells is a scene
    // that has outgrown the format, not a value to wrap.
    return i * ONE;
}

/// Floor of the product — the shift is arithmetic, so the rounding is toward
/// −∞ on both signs. One rule, stated once, so the GPU twin can match it.
pub fn mul(a: Fixed, b: Fixed) Fixed {
    const p: i64 = @as(i64, a) * @as(i64, b);
    return @intCast(p >> FRAC_BITS);
}

/// `num / den` as a fixed-point value, truncating toward zero.
pub fn fromRatio(num: i64, den: i64) Fixed {
    std.debug.assert(den != 0);
    return @intCast(@divTrunc(num << FRAC_BITS, den));
}

/// Nanoseconds → seconds. The fed-time delta becomes the kernel's dt through
/// exactly this and nothing else, so two runs with the same fed script see
/// the same dt bits (u128 so a multi-day time_ns cannot overflow).
pub fn fromNs(ns: u64) Fixed {
    const scaled: u128 = (@as(u128, ns) << FRAC_BITS) / std.time.ns_per_s;
    return @intCast(scaled);
}

pub fn vecMul(v: Vec, s: Fixed) Vec {
    return .{ mul(v[0], s), mul(v[1], s), mul(v[2], s) };
}

pub fn vecAdd(a: Vec, b: Vec) Vec {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}

/// Display only. Never feeds back into the sim.
pub fn toF64(x: Fixed) f64 {
    return @as(f64, @floatFromInt(x)) / @as(f64, @floatFromInt(ONE));
}

/// The field boundary's other direction: a row position handed to the
/// host's f32 physics (a cast's centre, a lattice grid point). Once per
/// tick per value, never inside the loop.
pub fn toF32(x: Fixed) f32 {
    return @floatCast(toF64(x));
}

/// A host f32 (a rasterised field value) quantised onto the row's number:
/// floor, saturating at the format's rails. The one place the field enters
/// the sim, once per lattice point per tick.
pub fn fromF32Saturating(v: f32) Fixed {
    const scaled = @floor(@as(f64, v) * @as(f64, @floatFromInt(ONE)));
    if (scaled != scaled) return 0; // NaN reads as nothing
    if (scaled >= std.math.maxInt(Fixed)) return std.math.maxInt(Fixed);
    if (scaled <= std.math.minInt(Fixed)) return std.math.minInt(Fixed);
    return @intFromFloat(scaled);
}

pub const ParseError = error{ BadNumber, Overflow };

/// `-9.8`, `0.25`, `3`, `+12.` — decimal text to Q16.16 with integer
/// arithmetic, truncating the fraction toward zero past 16 bits. A float
/// parse would be deterministic too, but it would be a float in the sim's
/// front door, and the rule is simpler to keep when there are none at all.
pub fn parseDecimal(text: []const u8) ParseError!Fixed {
    if (text.len == 0) return error.BadNumber;
    var i: usize = 0;
    var negative = false;
    if (text[0] == '-' or text[0] == '+') {
        negative = text[0] == '-';
        i = 1;
    }
    var int_part: i64 = 0;
    var saw_digit = false;
    while (i < text.len and text[i] != '.') : (i += 1) {
        const c = text[i];
        if (c < '0' or c > '9') return error.BadNumber;
        int_part = int_part * 10 + (c - '0');
        if (int_part > 32767) return error.Overflow;
        saw_digit = true;
    }
    var frac_num: i64 = 0;
    var frac_den: i64 = 1;
    if (i < text.len and text[i] == '.') {
        i += 1;
        while (i < text.len) : (i += 1) {
            const c = text[i];
            if (c < '0' or c > '9') return error.BadNumber;
            // Ten decimal digits already exceed Q16.16's resolution; further
            // digits cannot change the answer and would overflow the i64.
            if (frac_den < 10_000_000_000) {
                frac_num = frac_num * 10 + (c - '0');
                frac_den *= 10;
            }
            saw_digit = true;
        }
    }
    if (!saw_digit) return error.BadNumber;
    const magnitude: i64 = (int_part << FRAC_BITS) + @divTrunc(frac_num << FRAC_BITS, frac_den);
    const signed = if (negative) -magnitude else magnitude;
    if (signed > std.math.maxInt(Fixed) or signed < std.math.minInt(Fixed)) return error.Overflow;
    return @intCast(signed);
}

/// Decimal text for a fixed value, four fractional digits, no float. For
/// logs and the runner's output.
pub fn format(x: Fixed, buf: []u8) []const u8 {
    const negative = x < 0;
    const mag: u64 = @intCast(if (negative) -@as(i64, x) else @as(i64, x));
    const int_part = mag >> FRAC_BITS;
    const frac = ((mag & (ONE - 1)) * 10_000) >> FRAC_BITS;
    return std.fmt.bufPrint(buf, "{s}{d}.{d:0>4}", .{ if (negative) "-" else "", int_part, frac }) catch "?";
}

test "fixed: products floor toward -inf on both signs, one rule" {
    try std.testing.expectEqual(fromInt(6), mul(fromInt(2), fromInt(3)));
    try std.testing.expectEqual(fromInt(-6), mul(fromInt(-2), fromInt(3)));
    // 0.5 * 0.5 = 0.25 exactly
    try std.testing.expectEqual(ONE / 4, mul(HALF, HALF));
    // -1/65536 * 1/2 floors to -1/65536, not to zero: the shift is arithmetic
    try std.testing.expectEqual(@as(Fixed, -1), mul(-1, HALF));
}

test "fixed: dt from nanoseconds is exact at the powers of two the gates lean on" {
    try std.testing.expectEqual(ONE, fromNs(std.time.ns_per_s));
    try std.testing.expectEqual(HALF, fromNs(std.time.ns_per_s / 2));
    try std.testing.expectEqual(ONE / 4, fromNs(std.time.ns_per_s / 4));
    // 16 ms is not exact and must truncate the same way every time
    try std.testing.expectEqual(@as(Fixed, 1048), fromNs(16 * std.time.ns_per_ms));
}

test "fixed: decimal text parses with integer arithmetic" {
    try std.testing.expectEqual(fromInt(3), try parseDecimal("3"));
    try std.testing.expectEqual(fromInt(-3), try parseDecimal("-3"));
    try std.testing.expectEqual(ONE / 4, try parseDecimal("0.25"));
    try std.testing.expectEqual(-ONE / 4, try parseDecimal("-0.25"));
    // 9.8 → 9 + floor(0.8 * 65536) = 9 * 65536 + 52428
    try std.testing.expectEqual(@as(Fixed, 9 * ONE + 52428), try parseDecimal("9.8"));
    try std.testing.expectError(error.BadNumber, parseDecimal(""));
    try std.testing.expectError(error.BadNumber, parseDecimal("."));
    try std.testing.expectError(error.BadNumber, parseDecimal("1e3"));
    try std.testing.expectError(error.Overflow, parseDecimal("40000"));
    var buf: [32]u8 = undefined;
    try std.testing.expectEqualStrings("-9.7999", format(try parseDecimal("-9.8"), &buf));
    try std.testing.expectEqualStrings("0.2500", format(ONE / 4, &buf));
}
