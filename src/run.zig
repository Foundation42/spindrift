//! drift-run — mount a spray on rill's mock plane over the mock floor, feed
//! it fixed ticks, and dump the population.
//!
//! `rill-run`'s shape (seeds, ticks, a fixed dt, a plane you can watch),
//! with a population instead of a slot table. It lives here and not in rill
//! because rill does not depend on spindrift (recon R-b §6). There is no
//! engine: a knob path is only a name, and the spray reads its knobs from
//! the same mock plane a mounted `.rill` writes to — so `--rill` is the
//! CHOPs layer of campaign §3.3 driving a spray whose kernel is rill text.
//!
//! The kernel is `--kernel <file.rill>`, or `kernels/embers.rill` embedded.
//! What the spray says on the plane (`plane.drift.@<name>.count`, `.bounds`,
//! `.digest`) is fed to the mounted rill as deltas each tick — the mock
//! plane records writes and notifies nobody, so this runner does what the
//! engine's plane would.
//!
//! Usage:
//!   drift-run [options]
//!
//!   --kernel <file.rill>   the kernel (default: the embedded embers)
//!   --capacity <n>         rows (default 4096); the only allocation
//!   --rng <u32>            the spray seed (default 1)
//!   --fixed-dt <ms>        milliseconds per tick (default 16) — the ONLY clock
//!   --ticks <n>            ticks fed after the epoch (default 60)
//!   --rate <rows/s>        knobs, decimal text, integer-parsed (no float
//!   --speed <cells/s>        enters the sim); the plane overrides these
//!   --spread <cells/s>       at plane.drift.@<name>.<knob> when set
//!   --life <ms>
//!   --gravity <cells/s²>   seeds plane.drift.@<name>.gravity (the embers kernel reads it)
//!   --pos <x,y,z>          spray position, cells
//!   --aim <x,y,z>          launch direction × 1.0 (default 0,1,0)
//!   --world floor|none     the mock World (default floor)
//!   --name <em>            the spray's @name on the plane (default em)
//!   --jobs <n>             worker threads for the sweep (default 0: inline)
//!   --chunk <n>            rows per job (default 1024)
//!   --rill <file.rill>     mount a program on the mock plane beside the spray
//!   --seed <path>=<v>      set a plane path before mount (repeatable)
//!   --every <n>            print a line every n ticks (default 1; 0 = only the end)
//!   --dump <file>          write the population after the last tick

const std = @import("std");
const spindrift = @import("spindrift");
const rill = @import("rill");
const struple = @import("struple");
const common = @import("common");

const fixed = spindrift.fixed;
const Fixed = fixed.Fixed;

const MAX_TICKS = 1_000_000;

const embers = @embedFile("embers.rill");

const Feed = struct { path: []const u8, value: []const u8 };

fn usage() void {
    std.debug.print(
        \\drift-run — mount a spray on the mock plane, feed fixed ticks, dump the rows.
        \\
        \\  drift-run [options]
        \\
        \\  --kernel <file.rill>  the kernel (default: the embedded embers)
        \\  --capacity <n>        rows (default 4096)
        \\  --rng <u32>           spray seed (default 1)
        \\  --fixed-dt <ms>       milliseconds per tick (default 16) — the only clock
        \\  --ticks <n>           ticks fed after the epoch (default 60)
        \\  --rate --speed --spread <decimal>   knobs (cells, seconds)
        \\  --life <ms>           row lifetime
        \\  --gravity <decimal>   seeds plane.drift.@<name>.gravity for the embers kernel
        \\  --pos <x,y,z>  --aim <x,y,z>
        \\  --world floor|none    the mock World (default floor)
        \\  --name <em>           the spray's @name on the plane (default em)
        \\  --jobs <n>            worker threads (default 0: inline)
        \\  --chunk <n>           rows per job (default 1024)
        \\  --rill <file.rill>    mount a program beside the spray
        \\  --seed <path>=<v>     set a plane path before mount (repeatable)
        \\  --every <n>           print every n ticks (default 1; 0 = end only)
        \\  --dump <file>         write the population after the last tick
        \\
        \\Example — 400 embers a second under gravity, one second, dumped:
        \\  drift-run --rate 400 --speed 3 --spread 1 --gravity -9.8 --life 800 --ticks 60 --dump embers.struple
        \\
    , .{});
}

const Options = struct {
    kernel_path: ?[]const u8 = null,
    capacity: u32 = 4096,
    rng: u32 = 1,
    dt_ms: u64 = 16,
    ticks: u32 = 60,
    knobs: spindrift.Knobs = .{ .rate = fixed.fromInt(100), .speed = fixed.fromInt(2), .spread = fixed.HALF, .life_ns = std.time.ns_per_s },
    gravity: Fixed = -(9 * fixed.ONE + 52428), // -9.8
    pos: fixed.Vec = fixed.zero_vec,
    aim: fixed.Vec = .{ 0, fixed.ONE, 0 },
    floor: bool = true,
    name: []const u8 = "em",
    jobs: u32 = 0,
    chunk: u32 = spindrift.spray.DEFAULT_CHUNK,
    rill_path: ?[]const u8 = null,
    every: u32 = 1,
    dump_path: ?[]const u8 = null,
};

fn parseVec(text: []const u8) !fixed.Vec {
    var out: fixed.Vec = undefined;
    var it = std.mem.splitScalar(u8, text, ',');
    for (&out) |*c| {
        const part = it.next() orelse return error.BadVec;
        c.* = try fixed.parseDecimal(std.mem.trim(u8, part, " "));
    }
    if (it.next() != null) return error.BadVec;
    return out;
}

/// A knob written on the plane wins over the command line. Numbers arrive
/// as struple ints or floats; this is the sim's one boundary where a float
/// may appear, and it is converted once, here, never inside the loop —
/// the same bargain rill's ledger records for `feed()`.
fn knobFromPlane(mock: *rill.MockPlane, buf: []u8, name: []const u8, knob: []const u8) ?Fixed {
    const path = std.fmt.bufPrint(buf, "plane.drift.@{s}.{s}", .{ name, knob }) catch return null;
    const bytes = mock.store.get(path) orelse return null;
    const v = rill.row.fromStruple(mock.gpa, bytes) orelse return null;
    return switch (v) {
        .scalar => |x| x,
        else => null,
    };
}

fn logThunk(_: ?*anyopaque, label: []const u8, val: []const u8) void {
    std.debug.print("     ~ tap {s} = {s}\n", .{ label, fmtValue(val) });
}

fn errorThunk(_: ?*anyopaque, ev: rill.eval.ErrorEvent) void {
    if (ev.detail.len > 0) {
        std.debug.print("     ! {s} ({s}) refused: {s}\n", .{ ev.node, ev.op, ev.detail });
    } else {
        std.debug.print("     ! {s} ({s}) refused: {s}\n", .{ ev.node, ev.op, ev.err });
    }
}

var fmt_buf: [128]u8 = undefined;
fn fmtValue(encoded: []const u8) []const u8 {
    var r = struple.reader(encoded);
    const first = (r.next() catch return "?") orelse return "(empty)";
    return switch (first) {
        .int => |v| std.fmt.bufPrint(&fmt_buf, "{d}", .{v}) catch "?",
        .float64 => |v| std.fmt.bufPrint(&fmt_buf, "{d:.4}", .{v}) catch "?",
        .float32 => |v| std.fmt.bufPrint(&fmt_buf, "{d:.4}", .{v}) catch "?",
        .boolean => |b| if (b) "true" else "false",
        .string => |s| std.fmt.bufPrint(&fmt_buf, "\"{s}\"", .{s}) catch "?",
        .map => "{…}",
        else => "…",
    };
}

pub fn main() !u8 {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_impl.deinit();
    const gpa = gpa_impl.allocator();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    var o = Options{};
    var seeds: std.ArrayListUnmanaged(Feed) = .empty;
    defer seeds.deinit(gpa);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const a = args[i];
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) {
            usage();
            return 0;
        }
        if (i + 1 >= args.len) {
            std.debug.print("'{s}' wants a value\n", .{a});
            return 2;
        }
        i += 1;
        const v = args[i];
        const bad = struct {
            fn f(flag: []const u8, val: []const u8, want: []const u8) u8 {
                std.debug.print("{s} wants {s}, got '{s}'\n", .{ flag, want, val });
                return 2;
            }
        }.f;
        if (std.mem.eql(u8, a, "--kernel")) {
            o.kernel_path = v;
        } else if (std.mem.eql(u8, a, "--capacity")) {
            o.capacity = std.fmt.parseInt(u32, v, 10) catch return bad(a, v, "a count");
            if (o.capacity == 0) return bad(a, v, "a count above zero");
        } else if (std.mem.eql(u8, a, "--rng")) {
            o.rng = std.fmt.parseInt(u32, v, 10) catch return bad(a, v, "a u32");
        } else if (std.mem.eql(u8, a, "--fixed-dt")) {
            o.dt_ms = std.fmt.parseInt(u64, v, 10) catch return bad(a, v, "milliseconds");
            if (o.dt_ms == 0) return bad(a, v, "milliseconds above zero");
        } else if (std.mem.eql(u8, a, "--ticks")) {
            o.ticks = std.fmt.parseInt(u32, v, 10) catch return bad(a, v, "a count");
        } else if (std.mem.eql(u8, a, "--rate")) {
            o.knobs.rate = fixed.parseDecimal(v) catch return bad(a, v, "rows per second");
        } else if (std.mem.eql(u8, a, "--speed")) {
            o.knobs.speed = fixed.parseDecimal(v) catch return bad(a, v, "cells per second");
        } else if (std.mem.eql(u8, a, "--spread")) {
            o.knobs.spread = fixed.parseDecimal(v) catch return bad(a, v, "cells per second");
        } else if (std.mem.eql(u8, a, "--gravity")) {
            o.gravity = fixed.parseDecimal(v) catch return bad(a, v, "cells per second squared");
        } else if (std.mem.eql(u8, a, "--life")) {
            const ms = std.fmt.parseInt(u64, v, 10) catch return bad(a, v, "milliseconds");
            o.knobs.life_ns = ms * std.time.ns_per_ms;
        } else if (std.mem.eql(u8, a, "--pos")) {
            o.pos = parseVec(v) catch return bad(a, v, "x,y,z");
        } else if (std.mem.eql(u8, a, "--aim")) {
            o.aim = parseVec(v) catch return bad(a, v, "x,y,z");
        } else if (std.mem.eql(u8, a, "--world")) {
            if (std.mem.eql(u8, v, "floor")) {
                o.floor = true;
            } else if (std.mem.eql(u8, v, "none")) {
                o.floor = false;
            } else return bad(a, v, "floor or none");
        } else if (std.mem.eql(u8, a, "--name")) {
            o.name = v;
        } else if (std.mem.eql(u8, a, "--jobs")) {
            o.jobs = std.fmt.parseInt(u32, v, 10) catch return bad(a, v, "a thread count");
        } else if (std.mem.eql(u8, a, "--chunk")) {
            o.chunk = std.fmt.parseInt(u32, v, 10) catch return bad(a, v, "rows per job");
            if (o.chunk == 0) return bad(a, v, "rows per job above zero");
        } else if (std.mem.eql(u8, a, "--rill")) {
            o.rill_path = v;
        } else if (std.mem.eql(u8, a, "--seed")) {
            const eq = std.mem.indexOfScalar(u8, v, '=') orelse return bad(a, v, "<path>=<value>");
            try seeds.append(gpa, .{ .path = v[0..eq], .value = v[eq + 1 ..] });
        } else if (std.mem.eql(u8, a, "--every")) {
            o.every = std.fmt.parseInt(u32, v, 10) catch return bad(a, v, "a count");
        } else if (std.mem.eql(u8, a, "--dump")) {
            o.dump_path = v;
        } else {
            std.debug.print("unknown option '{s}'\n\n", .{a});
            usage();
            return 2;
        }
    }
    if (o.ticks > MAX_TICKS) {
        std.debug.print("that is {d} ticks; the cap is {d}\n", .{ o.ticks, MAX_TICKS });
        return 2;
    }

    // -- the plane, the registry, the optional rill --------------------------
    var mock = rill.MockPlane.init(gpa);
    defer mock.deinit();
    var pk = struple.Packer.init(gpa);
    defer pk.deinit();
    for (seeds.items) |s| {
        pk.reset();
        try packText(&pk, s.value);
        try mock.put(s.path, pk.bytes());
    }
    // The gravity knob is seeded like any other, unless a --seed already said.
    {
        var buf: [256]u8 = undefined;
        const gpath = try std.fmt.bufPrint(&buf, "plane.drift.@{s}.gravity", .{o.name});
        if (mock.store.get(gpath) == null) {
            pk.reset();
            try pk.appendF64(fixed.toF64(o.gravity));
            try mock.put(gpath, pk.bytes());
        }
    }

    var reg = try rill.Registry.init(gpa);
    defer reg.deinit();
    try rill.registerCore(&reg);
    try spindrift.words.register(&reg);

    var prog: ?rill.Program = null;
    defer if (prog) |*p| p.deinit();
    var rt: ?rill.Runtime = null;
    defer if (rt) |*r| r.deinit();
    if (o.rill_path) |path| {
        const source = std.fs.cwd().readFileAlloc(gpa, path, 1 << 20) catch |err| {
            std.debug.print("cannot read {s}: {s}\n", .{ path, @errorName(err) });
            return 2;
        };
        defer gpa.free(source);
        var diag = rill.Diag{};
        prog = rill.parse(gpa, &reg, std.fs.path.stem(path), source, &diag) catch |err| {
            std.debug.print("{s}:{d}:{d}: {s}\n(parse refused: {s})\n", .{ path, diag.line, diag.col, diag.msg(), @errorName(err) });
            return 1;
        };
        rt = rill.Runtime.mount(gpa, &prog.?, mock.asPlane(), .{ .log_fn = logThunk, .error_fn = errorThunk }) catch |err| {
            std.debug.print("mount refused: {s}\n", .{@errorName(err)});
            return 1;
        };
        std.debug.print("mounted '{s}': {d} nodes, {d} subscriptions, {d} writes declared\n", .{
            std.fs.path.stem(path), prog.?.nodeCount(), prog.?.subs.items.len, prog.?.writes.items.len,
        });
    }

    // -- the spray and its kernel --------------------------------------------
    var floor = spindrift.Floor{};
    var nowhere = spindrift.Nowhere{};
    const world = if (o.floor) floor.asWorld() else nowhere.asWorld();
    var spray = try spindrift.Spray.init(gpa, o.capacity, o.rng, world);
    defer spray.deinit();
    spray.name = o.name;
    spray.knobs = o.knobs;
    spray.pos = o.pos;
    spray.aim = o.aim;
    spray.chunk = o.chunk;

    var kernel_source: []const u8 = embers;
    var kernel_owned: ?[]u8 = null;
    defer if (kernel_owned) |k| gpa.free(k);
    var kernel_name: []const u8 = "embers";
    if (o.kernel_path) |path| {
        kernel_owned = std.fs.cwd().readFileAlloc(gpa, path, 1 << 20) catch |err| {
            std.debug.print("cannot read {s}: {s}\n", .{ path, @errorName(err) });
            return 2;
        };
        kernel_source = kernel_owned.?;
        kernel_name = std.fs.path.stem(path);
    }
    {
        var diag = rill.registry.Detail{};
        spray.mountKernel(&reg, kernel_name, kernel_source, &diag) catch |err| {
            std.debug.print("kernel refused ({s}): {s}\n", .{ @errorName(err), diag.text() });
            return 1;
        };
    }

    var js: ?*common.jobs.JobSystem = null;
    defer if (js) |s| s.deinit();
    if (o.jobs > 0) js = try common.jobs.JobSystem.init(gpa, o.jobs);

    var nb: [32]u8 = undefined;
    std.debug.print("spray @{s}: kernel '{s}' ({d} nodes), capacity {d}, rng {d}, dt {d}ms, world {s}, jobs {d}\n", .{
        o.name, kernel_name, spray.kernel.?.prog.nodeCount(), o.capacity, o.rng, o.dt_ms, if (o.floor) "floor" else "none", o.jobs,
    });
    std.debug.print("  knobs: rate {s}", .{fixed.format(spray.knobs.rate, &nb)});
    std.debug.print(" speed {s}", .{fixed.format(spray.knobs.speed, &nb)});
    std.debug.print(" spread {s}", .{fixed.format(spray.knobs.spread, &nb)});
    std.debug.print(" life {d}ms", .{spray.knobs.life_ns / std.time.ns_per_ms});
    std.debug.print(" gravity {s}\n", .{fixed.format(o.gravity, &nb)});

    var path_buf: [256]u8 = undefined;
    var seen_writes: usize = 0;
    var t: u32 = 0;
    while (t <= o.ticks) : (t += 1) {
        const now = rill.Now{ .frame = t, .time_ns = @as(u64, t) * o.dt_ms * std.time.ns_per_ms };
        if (rt) |*r| try r.tick(now);
        // The plane wins over the command line, knob by knob, each tick.
        if (knobFromPlane(&mock, &path_buf, o.name, "rate")) |v| spray.knobs.rate = v;
        if (knobFromPlane(&mock, &path_buf, o.name, "speed")) |v| spray.knobs.speed = v;
        if (knobFromPlane(&mock, &path_buf, o.name, "spread")) |v| spray.knobs.spread = v;
        try spray.tick(now, js, mock.asPlane());

        // Everything written this tick — the rill's and the spray's — is
        // fed back to the rill as deltas, which is what the engine's plane
        // does for a subscriber and what the mock does not.
        for (mock.writes.items[seen_writes..]) |w| {
            std.debug.print("   <- {s} = {s}\n", .{ w.path, fmtValue(w.value) });
            if (rt) |*r| try r.feed(.{ .path = w.path, .value = w.value });
        }
        seen_writes = mock.writes.items.len;

        if (spray.last.refusals > 0) {
            std.debug.print("     ! kernel refused {d} row(s): {s}\n", .{ spray.last.refusals, spray.last_refusal.text() });
        }
        const last = t == o.ticks;
        if ((o.every > 0 and t % o.every == 0) or last) {
            std.debug.print("tick {d:>6}  t={d}ms  live {d:>6}  +{d} -{d}{s}  steps {d}\n", .{
                t,                                                   now.time_ns / std.time.ns_per_ms, spray.pop.live, spray.last.spawned, spray.last.died,
                if (spray.last.throttled > 0) "  THROTTLED" else "", spray.last.row_steps,
            });
        }
    }

    const bytes = try spindrift.dump.write(gpa, &spray.pop, spray.ticks);
    defer gpa.free(bytes);
    std.debug.print("population: {d} live of {d}, dump {d} bytes, digest {x:0>16}\n", .{
        spray.pop.live, spray.pop.capacity, bytes.len, spindrift.dump.digest(bytes),
    });
    if (o.dump_path) |path| {
        try std.fs.cwd().writeFile(.{ .sub_path = path, .data = bytes });
        std.debug.print("wrote {s}\n", .{path});
    }
    return 0;
}

/// `12` is an int, `1.5` a float, `true`/`false` a bool, anything else a
/// string — rill-run's rule, kept so a seed spells the same here.
fn packText(pk: *struple.Packer, text: []const u8) !void {
    if (std.mem.eql(u8, text, "true")) return pk.appendBool(true);
    if (std.mem.eql(u8, text, "false")) return pk.appendBool(false);
    if (std.mem.indexOfAny(u8, text, ".eE") == null) {
        if (std.fmt.parseInt(i64, text, 10)) |v| return pk.appendInt(v) else |_| {}
    }
    if (std.fmt.parseFloat(f64, text)) |f| return pk.appendF64(f) else |_| {}
    return pk.appendString(text);
}

test "drift-run: a vector parses as three decimals and nothing else" {
    const v = try parseVec("1,-2.5,0");
    try std.testing.expectEqual(fixed.fromInt(1), v[0]);
    try std.testing.expectEqual(@divExact(-fixed.fromInt(5), 2), v[1]);
    try std.testing.expectEqual(@as(Fixed, 0), v[2]);
    try std.testing.expectError(error.BadVec, parseVec("1,2"));
    try std.testing.expectError(error.BadVec, parseVec("1,2,3,4"));
}

test "drift-run: a plane knob overrides the command line, int exact and float floored once" {
    var mock = rill.MockPlane.init(std.testing.allocator);
    defer mock.deinit();
    var buf: [256]u8 = undefined;
    try std.testing.expectEqual(@as(?Fixed, null), knobFromPlane(&mock, &buf, "em", "rate"));
    try mock.putValue("plane.drift.@em.rate", @as(i64, 400));
    try std.testing.expectEqual(fixed.fromInt(400), knobFromPlane(&mock, &buf, "em", "rate").?);
    try mock.putValue("plane.drift.@em.speed", @as(f64, 2.5));
    try std.testing.expectEqual(@divExact(fixed.fromInt(5), 2), knobFromPlane(&mock, &buf, "em", "speed").?);
}

test "drift-run: the embedded kernel is the shipped text and parses with the words registered" {
    var reg = try rill.Registry.init(std.testing.allocator);
    defer reg.deinit();
    try rill.registerCore(&reg);
    try spindrift.words.register(&reg);
    var diag = rill.Diag{};
    var prog = try rill.parseKernel(std.testing.allocator, &reg, "embers", embers, &diag);
    defer prog.deinit();
    try std.testing.expectEqual(@as(usize, 3), prog.nodeCount());
}
