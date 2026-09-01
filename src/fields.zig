//! fields — the field interface a host implements, the kernel a spray
//! rasterises with, and the mock store the gates run on.
//!
//! **Fields, both ways** (campaign §3.4, beat 2). Sampling: fields are
//! receiver-summed over live casters — right for a dozen ears, wrong for
//! 10⁵ rows. A spray whose archetype declares `samples $wind cell 0.5`
//! asks the host for the channel's live BAG once per tick, rasterises it
//! onto a lattice over its own bounds, and rows trilinear-sample the
//! lattice (`spray.zig`, `words.zig`'s `hear`). Casting: a spray casts ONE
//! aggregate deposit per channel per tick — centre of mass, amplitude ∝
//! live count × per-row amplitude, radius from bounds — and the host
//! REPLACES the spray's previous one (cross-tick coalesce). Ownership is
//! the ceiling: unmount withdraws the bag.
//!
//! **The model is the engine's**, transcribed from matryoshka's
//! `src/fields.zig` (rill-casts.md §3–§6, cc-note-casts.md §2–§4) so an ear
//! in the engine and a row in a spray agree about the same deposit:
//!
//!     contribution(t) = amplitude · exp(−(t − born)/τ), culled below ε
//!     q = 1 − (d/r)²,  d < r;   k(d) = q²;   ∇k = −(4q/r²)·(at − pos)
//!
//! The gradient points TOWARD the caster. The value is clamped by the
//! channel; the gradient comes from the unclamped sum. A coupled deposit
//! (`to #tag`) reaches only an audience carrying the tag; the operator's
//! instruments hear everything. Everything is deterministic in fed time.
//!
//! This is a second copy of that model, on purpose: the mock must agree
//! with the engine, and spindrift cannot depend on matryoshka. Recorded
//! with a trigger — a third client of the field model moves it into a
//! sibling both can import.
//!
//! The spatial kernel is applied here, by spindrift, in both the mock and
//! the engine (the bridge hands the bag; the spray rasterises). The
//! temporal physics — decay, cull, replace — is the host's; the mock's is
//! the engine's transcribed.

const std = @import("std");
const rill = @import("rill");
const struple = @import("struple");
const fixed = @import("fixed.zig");

pub const Error = error{ UnknownChannel, Refused } || std.mem.Allocator.Error;

/// One live deposit as the host hands it for rasterisation: the amplitude
/// is the CURRENT contribution (decay applied by the host), positions and
/// radius in cells. `tag` is the coupling (`to #tag`), empty = uncoupled,
/// borrowed for the call.
pub const Deposit = struct {
    pos: [3]f32,
    amplitude: f32,
    radius: f32,
    tag: []const u8 = "",
};

/// A channel's live bag plus the physics the sample needs.
pub const Bag = struct {
    deposits: []const Deposit,
    clamp_lo: f32 = -std.math.inf(f32),
    clamp_hi: f32 = std.math.inf(f32),
};

/// What a spray deposits: its one aggregate per channel per tick.
pub const Cast = struct {
    channel: []const u8,
    pos: [3]f32,
    amplitude: f32,
    radius: f32,
    /// Null = the channel's default.
    decay_ns: ?u64 = null,
    /// Coupling, sigil included; empty = uncoupled.
    to: []const u8 = "",
};

/// The host's field store, as a spray sees it. Same fn-pointer discipline
/// as `World` and rill's `Plane`.
pub const Fields = struct {
    ctx: *anyopaque,
    /// Append the channel's live deposits as of `now_ns` to `out` and return
    /// the bag's clamp; null = the channel is not declared (loud at the
    /// caller — a reading of 0 from a channel that does not exist would be
    /// the wrong kind of plausible). Deposits are borrowed for the tick.
    bagFn: *const fn (ctx: *anyopaque, channel: []const u8, now_ns: u64, gpa: std.mem.Allocator, out: *std.ArrayListUnmanaged(Deposit)) Error!?Bag,
    /// Replace `owner`'s deposit on the cast's channel with this one — an
    /// owner has ONE deposit per channel, restated each tick.
    castFn: *const fn (ctx: *anyopaque, owner: []const u8, now_ns: u64, cast: Cast) Error!void,
    /// Drop every deposit `owner` holds, on every channel.
    withdrawFn: *const fn (ctx: *anyopaque, owner: []const u8) void,

    pub fn bag(self: Fields, channel: []const u8, now_ns: u64, gpa: std.mem.Allocator, out: *std.ArrayListUnmanaged(Deposit)) Error!?Bag {
        return self.bagFn(self.ctx, channel, now_ns, gpa, out);
    }
    pub fn cast(self: Fields, owner: []const u8, now_ns: u64, c: Cast) Error!void {
        return self.castFn(self.ctx, owner, now_ns, c);
    }
    pub fn withdraw(self: Fields, owner: []const u8) void {
        self.withdrawFn(self.ctx, owner);
    }
};

/// The engine's kernel, value and gradient, at `at` for one deposit.
/// Returns null outside the radius.
pub fn kernelAt(d: Deposit, at: [3]f32) ?struct { value: f32, grad: [3]f32 } {
    const dx = at[0] - d.pos[0];
    const dy = at[1] - d.pos[1];
    const dz = at[2] - d.pos[2];
    const d2 = dx * dx + dy * dy + dz * dz;
    const r2 = d.radius * d.radius;
    if (d2 >= r2) return null;
    const q = 1.0 - d2 / r2;
    const g = d.amplitude * (-4.0 * q / r2);
    return .{ .value = d.amplitude * q * q, .grad = .{ g * dx, g * dy, g * dz } };
}

/// Does an audience carrying `carried` hear this deposit? Uncoupled
/// deposits reach everyone; a coupled one only its tag's carriers.
pub fn hears(d: Deposit, carried: []const []const u8) bool {
    if (d.tag.len == 0) return true;
    for (carried) |t| {
        if (std.mem.eql(u8, t, d.tag)) return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// The mock store — the engine's model, transcribed. Channels are declared
// with epsilon, default decay and clamp; owners hold bags; a restated
// deposit (same owner, channel, pos, radius, decay, tag on a later tick)
// replaces and restarts; the same within a tick sums; `tick` culls what
// decayed below epsilon; `sample` is the receiver-side sum — the mock ear.
// ---------------------------------------------------------------------------

pub const Channel = struct {
    name: []const u8,
    epsilon: f32 = 0.01,
    default_decay_ns: u64 = std.time.ns_per_s,
    clamp_lo: f32 = -std.math.inf(f32),
    clamp_hi: f32 = std.math.inf(f32),
};

pub const Reading = struct { value: f32, gradient: [3]f32 };

pub const MockFields = struct {
    gpa: std.mem.Allocator,
    channels: std.ArrayListUnmanaged(Channel) = .empty,
    /// Every deposit, in insertion order (owner order is insertion order
    /// here; the engine keeps mount order — both are stable, which is the
    /// determinism pin).
    deposits: std.ArrayListUnmanaged(Stored) = .empty,
    now_ns: u64 = 0,
    /// Casts refused — unknown channel — for a gate to count.
    refused: u32 = 0,

    const Stored = struct {
        owner: []u8,
        channel: []u8,
        pos: [3]f32,
        amplitude: f32,
        radius: f32,
        decay_ns: u64,
        born_ns: u64,
        tag: []u8,
        /// A spray's aggregate: replaced by the next cast from the same
        /// owner on the same channel, whatever its position.
        aggregate: bool,

        fn contribution(self: Stored, now: u64) f32 {
            if (self.decay_ns == 0) return self.amplitude;
            const dt: f32 = @floatFromInt(now -| self.born_ns);
            const tau: f32 = @floatFromInt(self.decay_ns);
            return self.amplitude * @exp(-dt / tau);
        }
    };

    pub fn init(gpa: std.mem.Allocator) MockFields {
        return .{ .gpa = gpa };
    }

    pub fn deinit(self: *MockFields) void {
        for (self.deposits.items) |d| self.freeStored(d);
        self.deposits.deinit(self.gpa);
        for (self.channels.items) |c| self.gpa.free(c.name);
        self.channels.deinit(self.gpa);
    }

    fn freeStored(self: *MockFields, d: Stored) void {
        self.gpa.free(d.owner);
        self.gpa.free(d.channel);
        self.gpa.free(d.tag);
    }

    /// Declare a channel; the name wears its `$`. Redeclaring updates the
    /// physics and keeps the bags (instrument adjustment, not a world reset).
    pub fn declare(self: *MockFields, ch: Channel) !void {
        for (self.channels.items) |*c| {
            if (std.mem.eql(u8, c.name, ch.name)) {
                const name = c.name;
                c.* = ch;
                c.name = name;
                return;
            }
        }
        var owned = ch;
        owned.name = try self.gpa.dupe(u8, ch.name);
        try self.channels.append(self.gpa, owned);
    }

    fn channel(self: *const MockFields, name: []const u8) ?*const Channel {
        for (self.channels.items) |*c| {
            if (std.mem.eql(u8, c.name, name)) return c;
        }
        return null;
    }

    /// A caster's deposit (a rill's `cast`, through `asPlane`). Same owner,
    /// channel, pos, radius, decay and tag on a LATER tick replaces and
    /// restarts the decay; on the SAME tick it sums.
    pub fn deposit(self: *MockFields, owner: []const u8, chan: []const u8, pos: [3]f32, amplitude: f32, radius: f32, decay_ns: ?u64, tag: []const u8) Error!void {
        const ch = self.channel(chan) orelse {
            self.refused += 1;
            return error.UnknownChannel;
        };
        const tau = decay_ns orelse ch.default_decay_ns;
        for (self.deposits.items) |*d| {
            if (d.aggregate or !std.mem.eql(u8, d.owner, owner) or !std.mem.eql(u8, d.channel, chan)) continue;
            if (!(sameVec(d.pos, pos) and sameF32(d.radius, radius) and d.decay_ns == tau and std.mem.eql(u8, d.tag, tag))) continue;
            if (d.born_ns == self.now_ns) {
                d.amplitude += amplitude;
            } else {
                d.amplitude = amplitude;
                d.born_ns = self.now_ns;
            }
            return;
        }
        try self.store(owner, chan, pos, amplitude, radius, tau, tag, false);
    }

    fn store(self: *MockFields, owner: []const u8, chan: []const u8, pos: [3]f32, amplitude: f32, radius: f32, tau: u64, tag: []const u8, aggregate: bool) !void {
        const o = try self.gpa.dupe(u8, owner);
        errdefer self.gpa.free(o);
        const c = try self.gpa.dupe(u8, chan);
        errdefer self.gpa.free(c);
        const t = try self.gpa.dupe(u8, tag);
        errdefer self.gpa.free(t);
        try self.deposits.append(self.gpa, .{ .owner = o, .channel = c, .pos = pos, .amplitude = amplitude, .radius = radius, .decay_ns = tau, .born_ns = self.now_ns, .tag = t, .aggregate = aggregate });
    }

    /// Advance fed time and cull what decayed below its channel's epsilon.
    pub fn tick(self: *MockFields, now_ns: u64) void {
        self.now_ns = now_ns;
        var i: usize = 0;
        while (i < self.deposits.items.len) {
            const d = self.deposits.items[i];
            const eps = if (self.channel(d.channel)) |c| c.epsilon else 0;
            if (@abs(d.contribution(now_ns)) < eps) {
                self.freeStored(d);
                _ = self.deposits.orderedRemove(i);
                continue;
            }
            i += 1;
        }
    }

    /// The receiver-side sum at a standpoint — the mock ear. Null = unknown
    /// channel. `carried` is the audience's tags; empty hears only the
    /// uncoupled, `hear_all` hears everything (the operator's instrument).
    pub fn sample(self: *const MockFields, chan: []const u8, at: [3]f32, hear_all: bool, carried: []const []const u8) ?Reading {
        const ch = self.channel(chan) orelse return null;
        var value: f32 = 0;
        var grad: [3]f32 = .{ 0, 0, 0 };
        for (self.deposits.items) |d| {
            if (!std.mem.eql(u8, d.channel, chan)) continue;
            const dep = Deposit{ .pos = d.pos, .amplitude = d.contribution(self.now_ns), .radius = d.radius, .tag = d.tag };
            if (!hear_all and !hears(dep, carried)) continue;
            const k = kernelAt(dep, at) orelse continue;
            value += k.value;
            grad[0] += k.grad[0];
            grad[1] += k.grad[1];
            grad[2] += k.grad[2];
        }
        return .{ .value = std.math.clamp(value, ch.clamp_lo, ch.clamp_hi), .gradient = grad };
    }

    pub fn depositCount(self: *const MockFields, chan: []const u8) usize {
        var n: usize = 0;
        for (self.deposits.items) |d| {
            if (std.mem.eql(u8, d.channel, chan)) n += 1;
        }
        return n;
    }

    // -- as the spray's Fields ---------------------------------------------

    pub fn asFields(self: *MockFields) Fields {
        return .{ .ctx = self, .bagFn = bagThunk, .castFn = castThunk, .withdrawFn = withdrawThunk };
    }

    fn bagThunk(ctx: *anyopaque, chan: []const u8, now_ns: u64, gpa: std.mem.Allocator, out: *std.ArrayListUnmanaged(Deposit)) Error!?Bag {
        const self: *MockFields = @ptrCast(@alignCast(ctx));
        const ch = self.channel(chan) orelse return null;
        const start = out.items.len;
        for (self.deposits.items) |d| {
            if (!std.mem.eql(u8, d.channel, chan)) continue;
            try out.append(gpa, .{ .pos = d.pos, .amplitude = d.contribution(now_ns), .radius = d.radius, .tag = d.tag });
        }
        return .{ .deposits = out.items[start..], .clamp_lo = ch.clamp_lo, .clamp_hi = ch.clamp_hi };
    }

    /// A spray's aggregate: one per (owner, channel), replaced whatever its
    /// position — cross-tick coalesce as ruled.
    fn castThunk(ctx: *anyopaque, owner: []const u8, now_ns: u64, c: Cast) Error!void {
        const self: *MockFields = @ptrCast(@alignCast(ctx));
        self.now_ns = now_ns;
        const ch = self.channel(c.channel) orelse {
            self.refused += 1;
            return error.UnknownChannel;
        };
        const tau = c.decay_ns orelse ch.default_decay_ns;
        for (self.deposits.items) |*d| {
            if (!d.aggregate or !std.mem.eql(u8, d.owner, owner) or !std.mem.eql(u8, d.channel, c.channel)) continue;
            d.pos = c.pos;
            d.amplitude = c.amplitude;
            d.radius = c.radius;
            d.decay_ns = tau;
            d.born_ns = now_ns;
            if (!std.mem.eql(u8, d.tag, c.to)) {
                self.gpa.free(d.tag);
                d.tag = try self.gpa.dupe(u8, c.to);
            }
            return;
        }
        try self.store(owner, c.channel, c.pos, c.amplitude, c.radius, tau, c.to, true);
    }

    fn withdrawThunk(ctx: *anyopaque, owner: []const u8) void {
        const self: *MockFields = @ptrCast(@alignCast(ctx));
        var i: usize = 0;
        while (i < self.deposits.items.len) {
            const d = self.deposits.items[i];
            if (std.mem.eql(u8, d.owner, owner)) {
                self.freeStored(d);
                _ = self.deposits.orderedRemove(i);
                continue;
            }
            i += 1;
        }
    }

    // -- as a rill plane's cast door ----------------------------------------

    /// Wrap a plane so a rill's `cast` deposits here under `owner` (one per
    /// mounted rill — mount order, the engine's rule), and everything else
    /// goes through to `inner`. This is how a caster rill and a spray share
    /// one field store on the mock, as they share the engine's.
    pub const CastDoor = struct {
        inner: rill.Plane,
        fields: *MockFields,
        owner: []const u8,

        pub fn asPlane(self: *CastDoor) rill.Plane {
            var p = self.inner;
            p.ctx = self;
            p.subscribeFn = subscribeThunk;
            p.unsubscribeFn = unsubscribeThunk;
            p.readFn = readThunk;
            p.writeFn = writeThunk;
            p.castFn = castDoorThunk;
            p.tagFn = tagThunk;
            return p;
        }
        fn subscribeThunk(ctx: *anyopaque, path: []const u8, sub: rill.plane.SubId) rill.plane.PlaneError!void {
            const self: *CastDoor = @ptrCast(@alignCast(ctx));
            return self.inner.subscribe(path, sub);
        }
        fn unsubscribeThunk(ctx: *anyopaque, sub: rill.plane.SubId) void {
            const self: *CastDoor = @ptrCast(@alignCast(ctx));
            self.inner.unsubscribe(sub);
        }
        fn readThunk(ctx: *anyopaque, path: []const u8, out: *struple.Packer) rill.plane.PlaneError!void {
            const self: *CastDoor = @ptrCast(@alignCast(ctx));
            return self.inner.read(path, out);
        }
        fn writeThunk(ctx: *anyopaque, path: []const u8, val: []const u8, kind: rill.DeltaKind, mode: rill.WriteMode, stmt: u32) rill.plane.PlaneError!void {
            const self: *CastDoor = @ptrCast(@alignCast(ctx));
            return self.inner.write(path, val, kind, mode, stmt);
        }
        fn tagThunk(ctx: *anyopaque, t: rill.plane.TagWrite) rill.plane.PlaneError!void {
            const self: *CastDoor = @ptrCast(@alignCast(ctx));
            return self.inner.tag(t);
        }
        fn castDoorThunk(ctx: *anyopaque, c: rill.plane.Cast) rill.plane.PlaneError!void {
            const self: *CastDoor = @ptrCast(@alignCast(ctx));
            const pos = posFromStruple(c.pos) orelse return error.Denied;
            const decay: ?u64 = if (c.decay) |d| (if (d.frames) null else d.count) else null;
            self.fields.deposit(self.owner, c.channel, pos, @floatCast(c.amplitude), @floatCast(c.radius), decay, c.to) catch |err| return switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => error.Denied,
            };
        }
    };
};

/// `{x, y, z}` in cells, as a rill `cast … at` position arrives.
pub fn posFromStruple(bytes: []const u8) ?[3]f32 {
    var buf: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const v = rill.row.fromStruple(fba.allocator(), bytes) orelse return null;
    return switch (v) {
        .vec3 => |p| .{ fixed.toF32(p[0]), fixed.toF32(p[1]), fixed.toF32(p[2]) },
        else => null,
    };
}

fn sameF32(a: f32, b: f32) bool {
    return @as(u32, @bitCast(a)) == @as(u32, @bitCast(b));
}

fn sameVec(a: [3]f32, b: [3]f32) bool {
    return sameF32(a[0], b[0]) and sameF32(a[1], b[1]) and sameF32(a[2], b[2]);
}

test "mock fields: a deposit decays in fed time, is culled at tau·ln(A/eps), and a restated one restarts" {
    var f = MockFields.init(std.testing.allocator);
    defer f.deinit();
    try f.declare(.{ .name = "$wind", .epsilon = 0.01, .default_decay_ns = std.time.ns_per_s });
    f.tick(0);
    try f.deposit("caster", "$wind", .{ 0, 0, 0 }, 0.8, 4, null, "");
    const r0 = f.sample("$wind", .{ 0, 0, 0 }, true, &.{}).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), r0.value, 1e-6);
    f.tick(std.time.ns_per_s);
    const r1 = f.sample("$wind", .{ 0, 0, 0 }, true, &.{}).?;
    try std.testing.expectApproxEqAbs(@as(f32, 0.8 / std.math.e), r1.value, 1e-5);
    // Restated on a later tick: replaces at full amplitude, decay restarts.
    try f.deposit("caster", "$wind", .{ 0, 0, 0 }, 0.8, 4, null, "");
    try std.testing.expectEqual(@as(usize, 1), f.depositCount("$wind"));
    try std.testing.expectApproxEqAbs(@as(f32, 0.8), f.sample("$wind", .{ 0, 0, 0 }, true, &.{}).?.value, 1e-6);
    // ln(80) ≈ 4.382 s: gone a moment after, present a moment before.
    f.tick(std.time.ns_per_s + 4_380_000_000);
    try std.testing.expectEqual(@as(usize, 1), f.depositCount("$wind"));
    f.tick(std.time.ns_per_s + 4_390_000_000);
    try std.testing.expectEqual(@as(usize, 0), f.depositCount("$wind"));
    // An unknown channel refuses and counts.
    try std.testing.expectError(error.UnknownChannel, f.deposit("caster", "$fog", .{ 0, 0, 0 }, 1, 1, null, ""));
    try std.testing.expectEqual(@as(u32, 1), f.refused);
}

test "mock fields: the kernel is the engine's — q² value, gradient toward the caster, zero at the radius" {
    const d = Deposit{ .pos = .{ 0, 0, 0 }, .amplitude = 2, .radius = 4 };
    const at_half = kernelAt(d, .{ 2, 0, 0 }).?; // d/r = 0.5 → q = 0.75 → k = 0.5625
    try std.testing.expectApproxEqAbs(@as(f32, 2 * 0.5625), at_half.value, 1e-6);
    try std.testing.expect(at_half.grad[0] < 0); // toward the caster at the origin
    try std.testing.expectEqual(@as(?@TypeOf(at_half), null), kernelAt(d, .{ 4, 0, 0 }));
    try std.testing.expectApproxEqAbs(@as(f32, 2), kernelAt(d, .{ 0, 0, 0 }).?.value, 1e-6);
}

test "mock fields: a coupled deposit reaches its tag's carriers and nobody else; the operator hears all" {
    var f = MockFields.init(std.testing.allocator);
    defer f.deinit();
    try f.declare(.{ .name = "$alarm" });
    try f.deposit("caster", "$alarm", .{ 0, 0, 0 }, 1, 4, null, "#garrison");
    try std.testing.expectEqual(@as(f32, 0), f.sample("$alarm", .{ 0, 0, 0 }, false, &.{}).?.value);
    try std.testing.expectEqual(@as(f32, 0), f.sample("$alarm", .{ 0, 0, 0 }, false, &.{"#raiders"}).?.value);
    try std.testing.expectEqual(@as(f32, 1), f.sample("$alarm", .{ 0, 0, 0 }, false, &.{"#garrison"}).?.value);
    try std.testing.expectEqual(@as(f32, 1), f.sample("$alarm", .{ 0, 0, 0 }, true, &.{}).?.value);
}

test "mock fields: an aggregate is replaced whatever its position, and withdrawn with its owner" {
    var f = MockFields.init(std.testing.allocator);
    defer f.deinit();
    try f.declare(.{ .name = "$dank" });
    const fl = f.asFields();
    try fl.cast("smoke", 0, .{ .channel = "$dank", .pos = .{ 0, 0, 0 }, .amplitude = 1, .radius = 3 });
    try fl.cast("smoke", 1, .{ .channel = "$dank", .pos = .{ 5, 0, 0 }, .amplitude = 2, .radius = 3 });
    try std.testing.expectEqual(@as(usize, 1), f.depositCount("$dank"));
    try std.testing.expectEqual(@as(f32, 0), f.sample("$dank", .{ 0, 0, 0 }, true, &.{}).?.value);
    try std.testing.expectEqual(@as(f32, 2), f.sample("$dank", .{ 5, 0, 0 }, true, &.{}).?.value);
    fl.withdraw("smoke");
    try std.testing.expectEqual(@as(usize, 0), f.depositCount("$dank"));
    try std.testing.expectError(error.UnknownChannel, fl.cast("smoke", 2, .{ .channel = "$nope", .pos = .{ 0, 0, 0 }, .amplitude = 1, .radius = 1 }));
}
