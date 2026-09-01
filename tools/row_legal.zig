//! row-legal — walk rill's registry and apply the row-legality test the
//! Spindrift campaign states (§3.3): "an operator is row-legal if it is
//! elementwise and any state it carries fits in the row's user channels."
//!
//! This is recon R-a's evidence. The brief asked for the list to come from
//! the registry, not from prose, so this derives it from the fields the
//! registry carries TODAY and says out loud where the registry cannot answer
//! — the state half of the test is not a registry column yet, which is the
//! column P1 adds (the ruled pattern: when a predicate over the registry is
//! a coverage surface, the registry carries the answer and the predicate is
//! derived).
//!
//! The mechanical half, "elementwise", from declared fields:
//!   - not `.effect`      — a plane write per row is not a row's own field
//!   - no section body    — `map`/`keep`/`reduce`/`sort` drive a body per element
//!   - not variadic       — `record`/`array` construction takes its ports from the call site
//!   - not `fails_mount`  — `expect` asserts once at mount; per row it means nothing
//!   - port 0 not array   — the piped position carries the row's value, and a row
//!                          field is never an array (an array LITERAL on a later
//!                          port is fine: `age | along life_curve` is `over`'s shape)
//!   - statics carry no plane row — `path`/`channel`/`subject`/`condition` touch
//!                          the plane; `word`/`literal`/`shape` are parse-time text
//!   - has an input       — a source with no input (`pi`, `clock`, `lfo`) is not
//!                          evaluated OVER anything; per row it is a constant
//!
//! Everything that passes is then split by `class`: `.pure` carries no state
//! and is row-legal outright; `.reads` carries state the registry cannot size
//! — listed separately, with the state layout read from ops.zig by hand in
//! the recon doc, because that is exactly the fact P1's column will declare.

const std = @import("std");
const rill = @import("rill");

const Verdict = enum { pure_ok, reads_state, refused };

fn typeName(reg: *const rill.Registry, id: rill.TypeId) []const u8 {
    return reg.types.name(id);
}

fn judge(def: *const rill.OpDef, why: *std.ArrayListUnmanaged(u8), gpa: std.mem.Allocator) !Verdict {
    const w = why.writer(gpa);
    if (def.class == .effect) {
        try w.print("effect: writes the plane", .{});
        return .refused;
    }
    if (def.body != 0) {
        try w.print("drives a section body per element", .{});
        return .refused;
    }
    if (def.variadic) {
        try w.print("variadic: ports come from the call site", .{});
        return .refused;
    }
    if (def.fails_mount) {
        try w.print("asserts at mount, once", .{});
        return .refused;
    }
    if (def.inputs.len == 0) {
        try w.print("no input: a source, not an elementwise op", .{});
        return .refused;
    }
    if (def.inputs[0].ty == rill.Tag.array) {
        try w.print("port 0 '{s}' is an array — a row field never is", .{def.inputs[0].name});
        return .refused;
    }
    for (def.statics) |s| switch (s.kind) {
        .path, .channel, .subject, .condition => {
            try w.print("static '{s}' names a plane row ({s})", .{ s.name, @tagName(s.kind) });
            return .refused;
        },
        .word, .literal, .shape => {},
    };
    if (def.class == .reads) {
        try w.print("reads: carries state the registry cannot size (or fed time)", .{});
        return .reads_state;
    }
    try w.print("pure, elementwise by declaration", .{});
    return .pure_ok;
}

pub fn main() !void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_impl.deinit();
    const gpa = gpa_impl.allocator();

    var reg = try rill.Registry.init(gpa);
    defer reg.deinit();
    try rill.registerCore(&reg);

    const out = std.io.getStdOut().writer();
    try out.print("rill core registry: {d} operators\n\n", .{reg.ops.items.len});

    var counts = [_]usize{ 0, 0, 0 };
    inline for (.{ Verdict.pure_ok, Verdict.reads_state, Verdict.refused }) |want| {
        try out.print("== {s} ==\n", .{switch (want) {
            .pure_ok => "row-legal now (pure, elementwise)",
            .reads_state => "elementwise, carries state — legal iff the state fits 4 user channels (registry cannot say; see recon)",
            .refused => "not row-legal by the declared fields",
        }});
        for (reg.ops.items) |*def| {
            var why: std.ArrayListUnmanaged(u8) = .empty;
            defer why.deinit(gpa);
            const v = try judge(def, &why, gpa);
            if (v != want) continue;
            counts[@intFromEnum(v)] += 1;
            try out.print("  {s:<14}", .{def.name});
            try out.print(" class={s:<6} ticks={s:<5} in=[", .{ @tagName(def.class), if (def.ticks) "yes" else "no" });
            for (def.inputs, 0..) |p, i| {
                if (i > 0) try out.print(" ", .{});
                try out.print("{s}:{s}{s}{s}{s}", .{
                    p.name,
                    typeName(&reg, p.ty),
                    if (p.broadcasts) "*" else "",
                    if (p.kw) "(kw)" else "",
                    if (p.optional) "?" else "",
                });
            }
            try out.print("]", .{});
            if (def.statics.len > 0) {
                try out.print(" statics=[", .{});
                for (def.statics, 0..) |s, i| {
                    if (i > 0) try out.print(" ", .{});
                    try out.print("{s}:{s}", .{ s.name, @tagName(s.kind) });
                }
                try out.print("]", .{});
            }
            try out.print("  — {s}\n", .{why.items});
        }
        try out.print("\n", .{});
    }
    try out.print("totals: pure row-legal {d}, stateful candidates {d}, refused {d}\n", .{ counts[0], counts[1], counts[2] });
    try out.print("(* = broadcasts; (kw) = keyword-introduced; ? = optional)\n", .{});
}
