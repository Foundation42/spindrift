//! spray — a population with a kernel mounted on it, ticked by fed time.
//!
//! The `@<name>` instance of the tenant (campaign §3.2, ruled `spray`
//! 2026-09-01): position, aim, knobs, and the rows. The kernel is a rill
//! program whose plane is the row (`rill/src/row.zig`); a spray mounts one
//! the way a host mounts a rill on the world, and evaluates it once per
//! live row per tick.
//!
//! **The tick is six phases and only the sweep is parallel** (recon R-b
//! §3, kept from P0 — and G0 is what forces the shape):
//!
//!   1. broadcasts — every `plane.…` the kernel reads is fetched once from
//!      the plane, `@self` resolved to this spray, converted once to a row
//!      value (the one float boundary), and handed to the runtime;
//!   2. materialise — every channel the archetype `samples` is rasterised
//!      from the host's live bag onto a lattice over the spray's bounds,
//!      once, so `hear` is a trilinear read of integers (beat 2, §3.4);
//!   3. spawn — serial: `rate × dt` rows, exact in nanoseconds, popped from
//!      the freelist in a fixed order, born at the spray's position with the
//!      spray's `life` and a seed from the spray's seed and the birth ordinal;
//!   4. the sweep — chunked over `common/jobs.zig`, row-local: the kernel
//!      once per live row (its writes land after its sweep of that row),
//!      then `pos += vel · dt` and `age += dt`. A kernel's `perish` marks;
//!      nothing here kills;
//!   5. reap — serial, ascending id: doomed rows go back on the freelist.
//!      Push ORDER is what the next spawn's ids are a function of;
//!   6. cast — every channel the archetype `casts` gets ONE aggregate
//!      deposit: centre of mass, amplitude ∝ live count × per-row amplitude,
//!      radius from bounds; the host replaces last tick's (§3.4).
//!
//! Then the spray says what it is on the plane: `plane.drift.@<name>.count`,
//! `.bounds` and `.digest`, change-only. On unmount it says zero and
//! withdraws its casts — absence is said, and ownership is the ceiling.
//!
//! Integration is not a word: a velocity that did not move its position
//! would not be a velocity. Time is fed; dt is the fed delta; a regression
//! is loud. No float enters the loop: the lattice and the cast are the
//! boundaries, crossed once per tick.

const std = @import("std");
const rill = @import("rill");
const common = @import("common");
const struple = @import("struple");
const jobs = common.jobs;
const fixed = @import("fixed.zig");
const world_mod = @import("world.zig");
const fields_mod = @import("fields.zig");
const population = @import("population.zig");
const Population = population.Population;

const Fixed = fixed.Fixed;
const Vec = fixed.Vec;
const Val = rill.row.Val;

pub const Now = rill.Now;
pub const World = world_mod.World;
pub const Fields = fields_mod.Fields;

pub const TickError = error{TimeRegression} || std.mem.Allocator.Error;
pub const MountError = error{ Parse, Mount } || std.mem.Allocator.Error;

/// The instance knobs (campaign §3.2). Units are the row's: cells and
/// seconds in Q16.16; `life` is nanoseconds on the knob and on the row
/// (the row reads it back in seconds). A knob written on the plane at
/// `plane.drift.@<name>.<knob>` wins over the field here — the host's
/// business (`drift-run` does it; the tenant's bridge does).
pub const Knobs = struct {
    /// Rows per second.
    rate: Fixed = 0,
    /// Cells per second along `aim` — `spawn`'s launch speed.
    speed: Fixed = 0,
    /// ± cells per second of per-axis jitter at launch, from the row's seed.
    spread: Fixed = 0,
    /// How long a row lives, fed nanoseconds; `perish` reaps at it.
    life_ns: u64 = std.time.ns_per_s,
};

/// The four knobs the SPRAY owns under its own `@name`. A kernel may read
/// them — that is what they are for — but may not mean something else by
/// them, and may not put its own knobs beside them.
pub const SPRAY_KNOBS = [_][]const u8{ "rate", "speed", "spread", "life" };

/// **What the row's appearance coordinate IS** — the contract a host reads,
/// and the one thing about it spindrift does NOT do, which is evaluate it.
///
/// `fire.rill` writes a point in an appearance manifold to `row.u0`–`u2`
/// and no colour at all; `motes.rill` writes a phase to `row.u0`. Until
/// this, what those channels MEANT lived in a comment, and a reader had to
/// know by agreement — which is exactly how the fire manifold got authored
/// upside down on 2026-09-07 with every number still in range. A spray now
/// SAYS it, on the plane, beside its count and bounds.
///
/// Spindrift never resolves `manifold` and never evaluates anything against
/// it. It is a name the HOST resolves — matryoshka resolves it to a loam
/// RBF set and reads it in a shader — which is the same shape `World` and
/// `Fields` already have: spindrift declares the seam, a host fills it, and
/// the mock fills it for the gates. No dependency travels in either
/// direction, and no float enters the sim: the coordinate is Q16.16 in the
/// row and stays there until it leaves.
pub const Appearance = struct {
    /// Which user channels carry the coordinate, in order.
    coord: [3]u8 = .{ 0, 1, 2 },
    /// What the host reads the coordinate AGAINST. A name, resolved by the
    /// host; empty means the host's own default.
    manifold: []const u8 = "",

    /// A channel this population does not have is refused when it is SET,
    /// not clamped and not discovered later by a host reading a coordinate
    /// that was never written.
    pub fn check(self: Appearance) error{BadAppearance}!void {
        for (self.coord) |c| {
            if (c >= population.USER_CHANNELS) return error.BadAppearance;
        }
    }
};

/// `samples $wind cell 0.5` on the archetype: a channel the kernel may
/// `hear`, and the lattice's declared cell size in cells.
pub const Sampled = struct {
    channel: []const u8,
    cell: Fixed,
};

pub const RadiusPolicy = union(enum) {
    /// Half the bounds' diagonal, floored at one cell so a lone row casts.
    bounds,
    fixed: f32,
};

/// `casts $dankness amp 0.01 radius bounds [to #tag]` on the archetype.
pub const Casting = struct {
    channel: []const u8,
    /// Amplitude per live row; the aggregate's is this × the live count.
    per_row_amplitude: f32,
    radius: RadiusPolicy = .bounds,
    /// Null = the channel's default.
    decay_ns: ?u64 = null,
    /// Coupling, sigil included; empty = uncoupled.
    to: []const u8 = "",
};

/// What one tick did — the numbers `drift-run` prints and G6 will read.
pub const Stats = struct {
    spawned: u32 = 0,
    died: u32 = 0,
    /// Spawns refused because the population was at capacity. Was
    /// `throttled` until beat 4, when `throttled` became the scheduler's
    /// word (a spray carried over for budget) — two facts, two words.
    refused: u32 = 0,
    /// This tick was not run: the scheduler carried the spray over and
    /// said `throttled` on its mailbox (beat 4, G6).
    carried_over: bool = false,
    /// Rows the sweep evaluated — the budget unit (§3.6), counted BY the
    /// sweep per chunk, never assumed from the live count (mutation M11,
    /// beat 0).
    row_steps: u32 = 0,
    /// Kernel refusals across every row this tick, merged after the join.
    refusals: u32 = 0,
    /// Sampled channels the host does not declare — the lattice stays
    /// dead and `hear` refuses, said here rather than guessed.
    bags_missing: u32 = 0,
    /// Lattices whose cell was doubled to fit the cap this tick.
    coarsened: u32 = 0,
    /// Aggregate casts the host refused (an undeclared channel, no store).
    cast_refusals: u32 = 0,
    /// Rows whose neighbourhood was larger than `MAX_NEIGHBOURS`, so `near`
    /// handed on a truncated one. Said rather than absorbed.
    crowded: u32 = 0,
    /// The neighbourhood grid this tick — the cell it was cut at and how many
    /// cells that made. Zero on a spray whose kernel never says `near`. Said,
    /// because the cell is derived now: a host that wonders why a query got
    /// expensive should be able to read the answer rather than infer it, and
    /// the thing this replaced was a constant nobody could see either.
    neigh_cell: Fixed = 0,
    neigh_cells: u32 = 0,
    /// Marks the rows left this tick (`deposit`), and the ones the host
    /// would not take — an undeclared channel, or a host with nowhere to
    /// put them. Said rather than absorbed, as the cast refusals are.
    deposits: u32 = 0,
    deposits_refused: u32 = 0,
};

/// The LARGEST a chunk gets, and what a spray sweeping serially uses. ≈ 80
/// bytes of row across the arrays, so a chunk streams ≈ 80 KB — inside L2
/// with room for scratch.
///
/// It was the only chunk size until 2026-09-08 — "a constant until the first
/// customer scene moves it (R-b §3)", and the fireflies scene is that scene.
/// It moved because a cache number is the wrong number: 2482 rows made 2.4
/// chunks for THIRTY workers, a tenth of the machine, which is why the
/// engine's tick was slower than drift-run's single thread. `chooseChunk`
/// derives the real one; this is the ceiling and the serial default.
pub const DEFAULT_CHUNK: u32 = 1024;

/// Chunks a spray is cut into. Enough to spread over any machine several
/// times — chunks do not finish together, so one per worker leaves the
/// machine waiting on its slowest — and a spray at a third of its capacity
/// (which is where a life-bounded emitter settles) still fills a big one.
///
/// From CAPACITY and nothing else, deliberately: the worker count would be a
/// better number and cannot be had in time. `chunk` is also the host's
/// dirty-upload unit, and a host sizes its per-chunk arrays the moment it is
/// handed a spray — matryoshka's `spray_bridge.zig` allocates `run_n` at
/// mount and then skips any spray whose chunk table has since changed
/// length. Deriving on the first tick instead of at init moved the chunk
/// AFTER that, and the engine drew nothing at all, silently, for ever. A
/// number that a host builds on must be final before the host can read it.
pub const TARGET_CHUNKS: u32 = 256;

/// The fewest rows worth dispatching as a job: below this the dispatch IS the
/// work. Measured on the fireflies scene at 30 workers, Debug — chunks of
/// 1024/256/128/64/32/16 rows cost 2860/1304/1052/925/895/953 µs a tick, so
/// the floor is real but shallow, and everything above ~128 is waste.
pub const MIN_CHUNK: u32 = 32;

/// Rows one `near` may hand on. A cap and not a budget: a row with more
/// neighbours than this is a row in a crowd, and the sweep counts it
/// (`Stats.crowded`) rather than growing — capacity is still the only
/// allocation. The cap is per row, so a dense spray says so instead of
/// quietly costing more every tick.
pub const MAX_NEIGHBOURS: u32 = 64;

/// The finest a neighbourhood cell may be cut. A cloud with no extent at all
/// — every row on one spot, which is what a spray looks like on its first
/// tick — would otherwise shrink for ever, because a grid of ONE cell fits
/// any cap however fine that cell is cut.
pub const MIN_NEIGH_CELL: Fixed = fixed.fromRatio(1, 1024);

/// One live row in the neighbourhood grid: where it is, and which row it is.
/// The position rides ALONG rather than being chased through `neigh_pos` by
/// id, so the candidate loop is a sequential walk over sixteen-byte items in
/// cell order instead of a random access per candidate into another array.
pub const Item = struct {
    pos: [3]Fixed,
    id: u32,
};

/// Grid points per axis a lattice may have. 33³ Q16.16 values is 144 KB
/// per channel; a spray whose bounds want more gets a coarser cell and
/// says `coarsened`, never a bigger allocation — capacity is the only one.
pub const MAX_SAMPLES: u32 = 33;

/// A sampled channel's field, rasterised onto grid points over the
/// spray's bounds. Values are Q16.16 amplitudes at the points; `sampleAt`
/// is trilinear and `gradientAt` is central differences, both integer.
pub const Lattice = struct {
    channel: []const u8,
    declared_cell: Fixed,
    /// The cell in use — the declared one, doubled until the bounds fit.
    cell: Fixed = 0,
    origin: Vec = fixed.zero_vec,
    /// Grid points per axis, each ≥ 2 once materialised.
    dims: [3]u32 = .{ 0, 0, 0 },
    values: []Fixed,
    /// False until the host has answered for this channel this tick —
    /// an unknown channel leaves the lattice dead, and `hear` refuses.
    live: bool = false,
    coarsened: u8 = 0,

    pub fn index(self: *const Lattice, i: u32, j: u32, k: u32) usize {
        return (@as(usize, k) * self.dims[1] + j) * self.dims[0] + i;
    }

    pub fn at(self: *const Lattice, i: u32, j: u32, k: u32) Fixed {
        return self.values[self.index(i, j, k)];
    }

    /// `p − origin` in grid units, Q16.16, clamped to the grid: integer part
    /// is the point, fraction is the position between it and the next.
    fn local(self: *const Lattice, p: Vec, axis: usize) Fixed {
        const hi: i64 = @as(i64, @intCast(self.dims[axis] - 1)) << fixed.FRAC_BITS;
        const off: i64 = @as(i64, p[axis]) - self.origin[axis];
        const q: i64 = @divFloor(off << fixed.FRAC_BITS, self.cell);
        return @intCast(@min(@max(q, 0), hi));
    }

    /// Trilinear, exact: eight point reads and seven fixed lerps.
    pub fn sampleAt(self: *const Lattice, p: Vec) Fixed {
        var i: [3]u32 = undefined;
        var t: [3]Fixed = undefined;
        inline for (0..3) |a| {
            const l = self.local(p, a);
            var cellidx: u32 = @intCast(l >> fixed.FRAC_BITS);
            var frac: Fixed = l & (fixed.ONE - 1);
            if (cellidx >= self.dims[a] - 1) {
                cellidx = self.dims[a] - 2;
                frac = fixed.ONE;
            }
            i[a] = cellidx;
            t[a] = frac;
        }
        const c000 = self.at(i[0], i[1], i[2]);
        const c100 = self.at(i[0] + 1, i[1], i[2]);
        const c010 = self.at(i[0], i[1] + 1, i[2]);
        const c110 = self.at(i[0] + 1, i[1] + 1, i[2]);
        const c001 = self.at(i[0], i[1], i[2] + 1);
        const c101 = self.at(i[0] + 1, i[1], i[2] + 1);
        const c011 = self.at(i[0], i[1] + 1, i[2] + 1);
        const c111 = self.at(i[0] + 1, i[1] + 1, i[2] + 1);
        const c00 = lerp(c000, c100, t[0]);
        const c10 = lerp(c010, c110, t[0]);
        const c01 = lerp(c001, c101, t[0]);
        const c11 = lerp(c011, c111, t[0]);
        const c0 = lerp(c00, c10, t[1]);
        const c1 = lerp(c01, c11, t[1]);
        return lerp(c0, c1, t[2]);
    }

    /// Central differences at the nearest grid point, one-sided at the
    /// edges; amplitude per cell, so a row reads the same slope whatever
    /// the cell the lattice settled on.
    pub fn gradientAt(self: *const Lattice, p: Vec) Vec {
        var n: [3]u32 = undefined;
        inline for (0..3) |a| {
            const l = self.local(p, a);
            const nearest: u32 = @intCast((l + fixed.HALF) >> fixed.FRAC_BITS);
            n[a] = @min(nearest, self.dims[a] - 1);
        }
        var g: Vec = undefined;
        inline for (0..3) |a| {
            const lo: u32 = if (n[a] > 0) n[a] - 1 else n[a];
            const hi: u32 = if (n[a] + 1 < self.dims[a]) n[a] + 1 else n[a];
            var lo_i = n;
            var hi_i = n;
            lo_i[a] = lo;
            hi_i[a] = hi;
            const span: i64 = @as(i64, @intCast(hi - lo)) * self.cell;
            g[a] = if (span == 0) 0 else @intCast(@divFloor(@as(i64, self.at(hi_i[0], hi_i[1], hi_i[2]) - self.at(lo_i[0], lo_i[1], lo_i[2])) << fixed.FRAC_BITS, span));
        }
        return g;
    }

    fn lerp(a: Fixed, b: Fixed, t: Fixed) Fixed {
        return a +% fixed.mul(b -% a, t);
    }
};

const ArrayCast = struct {
    sub: usize,
    bytes: []u8,
    vals: []Val,
};

/// A mounted kernel: the parsed program, the row runtime over this spray's
/// population, and one evaluation scratch per chunk (chunk-indexed, so no
/// thread id is needed and the refusal merge is in one order).
const Kernel = struct {
    prog: rill.Program,
    rt: rill.row.Runtime,
    scratches: []rill.row.Scratch = &.{},
};

pub const Spray = struct {
    gpa: std.mem.Allocator,
    pop: Population,
    /// The `@name` on the plane — `plane.drift.@<name>.…` is where the
    /// knobs are read and the count is said; also the cast owner's name.
    name: []const u8 = "em",
    /// The spray's decorrelator: every row's seed derives from this and the
    /// row's birth ordinal, and nothing else.
    seed: u32,
    pos: Vec = fixed.zero_vec,
    /// Direction × 1.0; `spawn` launches along `aim × speed`. Not
    /// normalised — an aim of (0, 2, 0) is twice the speed, and saying so
    /// is cheaper than a square root in fixed point.
    aim: Vec = .{ 0, fixed.ONE, 0 },
    knobs: Knobs = .{},
    world: World,
    /// The host's field store; null = a spray with no fields (a kernel
    /// that `hear`s refuses at mount, and casts are dropped, counted).
    fields: ?Fields = null,
    /// `samples …` and `casts …` from the archetype.
    samples: []const Sampled = &.{},
    casts: []const Casting = &.{},
    /// Tags this spray carries, for coupled deposits (`to #tag`) — the
    /// spray's authored ear hears a coupled deposit only while it carries
    /// the tag, exactly as an entity-bound ear does. Set by the host.
    carried: []const []const u8 = &.{},
    /// Rows per job — and the dirty-upload unit a host reads, which is why it
    /// is settled at INIT and never moves: a host sizes per-chunk arrays from
    /// it as soon as it has the spray, and a chunk that changed afterwards
    /// would leave those the wrong length. A host that wants its own says
    /// `setChunk` before handing the spray anywhere.
    chunk: u32 = DEFAULT_CHUNK,

    /// Rows owed by `rate`, in (rows · 2¹⁶ · ns): `rate` is Q16.16 rows/s
    /// and dt is fed nanoseconds, so the product is exact and a whole row is
    /// `ONE × ns_per_s` of it. 40/s at 50 ms spawns exactly 2 a tick.
    spawn_acc: i128 = 0,
    /// Birth ordinal, the row seed's other half. Never reset.
    spawned: u32 = 0,
    now: Now = .{},
    started: bool = false,
    ticks: u64 = 0,
    last: Stats = .{},
    /// Ticks this spray has been carried over by the scheduler since it
    /// last ran — the first priority input, fed-time only. Reset by `tick`.
    staleness: u64 = 0,
    /// The first refusal's words from the last tick, for the host's log.
    last_refusal: rill.registry.Detail = .{},
    /// The neighbourhood: a DENSE grid over the live rows' bounds, rebuilt
    /// once a tick at the tail of the serial spawn. `grid_starts` is
    /// cells+1 long so a cell is `starts[c]..starts[c+1]`; `grid_items` is
    /// capacity long, in cell order; `neigh_bufs` is one `MAX_NEIGHBOURS`
    /// run per chunk, which is what makes `near` row-local in the parallel
    /// sweep.
    ///
    /// It was a HASH grid until 2026-09-08, and all three things that
    /// changed were things that cost, measured on the playground's own
    /// scene (2482 rows, 521 candidates examined per row to keep 52):
    ///
    /// - **Dense, not hashed.** A hash needs a cell-equality test per
    ///   candidate to undo its own collisions, and that test was rejecting a
    ///   QUARTER of every candidate examined — work with no geometric
    ///   excuse. A dense cell index cannot collide, so the test is gone, the
    ///   per-row cell array is gone, and an empty cell is an empty range
    ///   instead of somebody else's rows. Only 17% of cell probes used to
    ///   find a genuinely empty bucket.
    /// - **The cell follows the rows** (`sizeGrid`), instead of being a
    ///   constant no host ever set.
    /// - **The payload rides along** (`Item`), instead of being chased by id.
    grid_starts: []u32 = &.{},
    grid_items: []Item = &.{},
    /// The grid's corner, cell and shape, chosen by `sizeGrid` every build.
    /// x is the CONTIGUOUS axis, which is what lets `gatherNear` read a whole
    /// run of cells along x as one range: a 3×3×3 neighbourhood costs nine
    /// range lookups, not twenty-seven.
    grid_origin: [3]Fixed = .{ 0, 0, 0 },
    grid_dims: [3]u32 = .{ 1, 1, 1 },
    grid_cell: Fixed = fixed.ONE,
    /// Each live row's POSITION as of the build, BY ROW ID — what `push` and
    /// `sync` read for a neighbour the handle lane named, and what the query
    /// row's own position comes from. Never `pop.pos`, because the sweep
    /// integrates a row the instant its kernel is done, so by the time row 1
    /// is swept row 0 has already moved. Reading live positions made a
    /// neighbourhood that depended on the order rows happened to be visited
    /// in, which under chunking is no order at all. One snapshot, taken once,
    /// read by everybody: the same rule the lattices already follow.
    neigh_pos: [][3]Fixed = &.{},
    /// Each live row's VELOCITY as of the build — `align`'s reading, and the
    /// third of the flocking trio. Snapshotted for the same reason the
    /// positions are: the sweep integrates a row the instant its kernel is
    /// done, so a live read would have half the flock steering toward
    /// velocities the other half had not adopted yet, and the answer would
    /// depend on the order the chunks happened to run in.
    neigh_vel: [][3]Fixed = &.{},
    /// Each live row's USER CHANNELS as of the build. A word that reads a
    /// neighbour's state — `sync` reads its phase — must read the snapshot
    /// for the same reason `push` reads snapshot positions: a kernel's
    /// writes land at the end of that row's evaluation, so row 1 would see
    /// row 0's NEW phase and row 0 would see row 1's old one. The coupling
    /// would then depend on the sweep order, which under chunking is no
    /// order at all.
    neigh_user: []Fixed = &.{},
    neigh_bufs: []u32 = &.{},
    /// What each row asked to leave behind this tick, by row id — zero is
    /// "nothing". One slot per row rather than a queue: a row deposits at
    /// most once a tick (mount refuses a second `deposit`), so the slot IS
    /// the answer, the parallel sweep writes only its own rows' slots, and
    /// the serial flush walks them in id order, which is what makes the
    /// deposits land in the same order on every machine.
    dep_amp: []Fixed = &.{},
    /// The channel the mounted kernel's one `deposit` names. Empty = the
    /// kernel does not deposit and none of this runs.
    dep_channel: []const u8 = "",
    /// What this spray's rows mean by their coordinate channels, said on
    /// the plane for a host to read. Null until a host sets it.
    appearance: ?Appearance = null,
    said_appearance: bool = false,
    /// Set at mount when the kernel says `near`. A spray that never asks
    /// builds nothing. (This comment had drifted onto `appearance`.)
    wants_neighbours: bool = false,
    /// Rows whose neighbourhood overflowed this tick; merged into `Stats`.
    crowded_rows: u32 = 0,
    chunk_steps: []u32 = &.{},
    /// Per chunk: was a live row swept in it this tick? That is the whole
    /// rule — the renderer uploads dirty chunks and nothing else (campaign
    /// §3.7). A row born this tick is swept this tick; a row reaped this
    /// tick was swept this tick (`perish` marks during the sweep, the reap
    /// kills after), so the chunk it leaves is dirty now and quiet next
    /// tick. The first draft also marked at spawn and at reap; mutations
    /// dropping either survived every gate, because the sweep's mark had
    /// already said it — two decorations, deleted (ledger, beat 3).
    chunk_dirty: []bool = &.{},
    kernel: ?Kernel = null,
    /// One per `samples` entry, allocated on the first tick that sees them.
    lattices: []Lattice = &.{},
    bag_scratch: std.ArrayListUnmanaged(fields_mod.Deposit) = .empty,
    /// A broadcast that carries an ARRAY (a curve the Spray applet edits,
    /// read by `over` as `plane.drift.@self.size_curve`): converted once
    /// when its bytes change, owned here, handed to the runtime by
    /// pointer — once per tick per spray at most, never per row. Keyed by
    /// subscription index; the bytes are kept to notice a change.
    array_casts: std.ArrayListUnmanaged(ArrayCast) = .empty,

    /// What was last said on the plane, so a tick that changes nothing says
    /// nothing (change-only: a sensor precondition, and a quiet log).
    said_count: ?u32 = null,
    said_digest: ?u64 = null,
    said_bounds: ?[6]Fixed = null,
    said_coarsened: ?u32 = null,

    pub fn init(gpa: std.mem.Allocator, capacity: u32, seed: u32, world: World) !Spray {
        var sp = Spray{
            .gpa = gpa,
            .pop = try Population.init(gpa, capacity),
            .seed = seed,
            .world = world,
        };
        errdefer sp.pop.deinit();
        // The chunk, settled here and never again — see `TARGET_CHUNKS`.
        sp.chunk = std.math.clamp(capacity / TARGET_CHUNKS, MIN_CHUNK, DEFAULT_CHUNK);
        // One cell per row is the most the grid will ever be cut into, so the
        // starts array is capacity+1 and `sizeGrid` coarsens until it fits.
        // Capacity stays the only allocation, as it is for the lattices.
        sp.grid_starts = try gpa.alloc(u32, @as(usize, capacity) + 1);
        errdefer gpa.free(sp.grid_starts);
        sp.grid_items = try gpa.alloc(Item, capacity);
        errdefer gpa.free(sp.grid_items);
        sp.neigh_pos = try gpa.alloc([3]Fixed, capacity);
        errdefer gpa.free(sp.neigh_pos);
        sp.neigh_vel = try gpa.alloc([3]Fixed, capacity);
        errdefer gpa.free(sp.neigh_vel);
        sp.dep_amp = try gpa.alloc(Fixed, capacity);
        errdefer gpa.free(sp.dep_amp);
        @memset(sp.dep_amp, 0);
        sp.neigh_user = try gpa.alloc(Fixed, @as(usize, capacity) * population.USER_CHANNELS);
        return sp;
    }

    /// The neighbourhood: a uniform hash grid over the LIVE rows, rebuilt
    /// once a tick at the tail of the serial spawn — the moment positions
    /// are final for the tick and before the sweep reads them. It is not a
    /// seventh phase, deliberately: the sweep must see one snapshot of where
    /// everybody is, and the end of spawn is exactly that instant.
    ///
    /// Built only when a mounted kernel says `near`, so a spray that never
    /// asks pays nothing.
    fn buildNeighbourhood(self: *Spray) void {
        if (!self.wants_neighbours) return;
        const p = &self.pop;
        // One pass to snapshot every live row and to find the bounds the grid
        // is cut from. The spray computes bounds elsewhere for what it SAYS;
        // this is the same walk and the snapshot has to happen anyway, so the
        // grid costs no extra pass over the population.
        var lo = [3]Fixed{ 0, 0, 0 };
        var hi = [3]Fixed{ 0, 0, 0 };
        var live: u32 = 0;
        var id: u32 = 0;
        while (id < p.capacity) : (id += 1) {
            if (!p.alive[id]) continue;
            const q = [3]Fixed{ p.pos[0][id], p.pos[1][id], p.pos[2][id] };
            self.neigh_pos[id] = q;
            self.neigh_vel[id] = .{ p.vel[0][id], p.vel[1][id], p.vel[2][id] };
            @memcpy(self.neigh_user[@as(usize, id) * population.USER_CHANNELS ..][0..population.USER_CHANNELS], p.userOf(id));
            inline for (0..3) |a| {
                if (live == 0 or q[a] < lo[a]) lo[a] = q[a];
                if (live == 0 or q[a] > hi[a]) hi[a] = q[a];
            }
            live += 1;
        }
        self.sizeGrid(lo, hi, live);
        const starts = self.grid_starts[0 .. self.cellCount() + 1];
        @memset(starts, 0);
        if (live == 0) return;

        // Counting sort by cell: count, prefix, scatter. Two passes over the
        // live rows and no allocation. The prefix leaves `starts[c + 1]`
        // holding the BEGIN of cell c, which the scatter then walks forward
        // until it is the end — so afterwards `starts[c]..starts[c + 1]` is
        // cell c, with no third pass to fix up.
        id = 0;
        while (id < p.capacity) : (id += 1) {
            if (!p.alive[id]) continue;
            starts[self.cellOf(self.neigh_pos[id]) + 1] += 1;
        }
        var acc: u32 = 0;
        for (starts) |*c| {
            const n = c.*;
            c.* = acc;
            acc += n;
        }
        id = 0;
        while (id < p.capacity) : (id += 1) {
            if (!p.alive[id]) continue;
            const c = self.cellOf(self.neigh_pos[id]);
            self.grid_items[starts[c + 1]] = .{ .pos = self.neigh_pos[id], .id = id };
            starts[c + 1] += 1;
        }
    }

    /// The grid's corner, cell and shape for this tick's rows: the FINEST
    /// cell that still cuts the grid into at most ONE CELL PER LIVE ROW.
    ///
    /// One per row and not one per four, measured on both scenes — the trade
    /// is that a query walks `(cells per axis)²` ranges and tests
    /// `occupancy × cells` rows, and 4 → 2 → 1 took the crowd's tick 4.2 →
    /// 3.7 → 3.6 ms while the range lookups only went 6 → 9 → 12. Finer than
    /// one per row is not reachable in any case: the starts array is the
    /// capacity already committed, which is what makes this cost no
    /// allocation. It replaces a 1 m constant no host ever set, which against
    /// the first scene that leaned on it (reach 0.75) swept 27 m³ to answer a
    /// question about 1.8.
    ///
    /// Stepping down rather than a cube root keeps this integer and keeps it
    /// terminating; a cube root in Q16.16 would be a second definition of a
    /// thing nothing else here needs.
    fn sizeGrid(self: *Spray, lo: [3]Fixed, hi: [3]Fixed, live: u32) void {
        self.grid_origin = lo;
        if (live == 0) {
            self.grid_dims = .{ 1, 1, 1 };
            self.grid_cell = fixed.ONE;
            return;
        }
        const extent = [3]Fixed{ hi[0] -% lo[0], hi[1] -% lo[1], hi[2] -% lo[2] };
        const cap: u64 = @min(@as(u64, live), self.grid_starts.len - 1);
        // Start WIDER than the extent, so the grid is one cell whatever the
        // rows are doing, and only ever step to a cell that still fits. That
        // is what keeps `cellCount() <= grid_starts.len - 1` true by
        // construction rather than by hope: starting AT the widest extent
        // gives dims of two on every axis — eight cells — which a spray of
        // capacity four has no room for, and nothing downstream would have
        // said so.
        const widest = @max(extent[0], @max(extent[1], extent[2]));
        var cell: Fixed = @max(widest, MIN_NEIGH_CELL) +| 1;
        while (nextCell(cell) >= MIN_NEIGH_CELL and cellsFor(extent, nextCell(cell)) <= cap) cell = nextCell(cell);
        self.grid_cell = cell;
        inline for (0..3) |a| {
            self.grid_dims[a] = @intCast(@divFloor(@as(i64, extent[a]), @as(i64, cell)) + 1);
        }
        std.debug.assert(self.cellCount() <= self.grid_starts.len - 1);
    }

    /// The next cell size down. Three quarters, not a half: halving multiplies
    /// the cell COUNT by eight, so the grid can only land on every eighth
    /// size and the target is missed by up to that much — measured, halving
    /// left the crowd's tick at 3.73 ms where three-quarters reaches 3.59.
    /// Strictly decreasing for any `cell >= 4`, and `MIN_NEIGH_CELL` is 64.
    fn nextCell(cell: Fixed) Fixed {
        return @intCast(@divFloor(@as(i64, cell) * 3, 4));
    }

    fn cellsFor(extent: [3]Fixed, cell: Fixed) u64 {
        if (cell <= 0) return std.math.maxInt(u64);
        var n: u64 = 1;
        for (extent) |e| {
            const d: u64 = @as(u64, @intCast(@divFloor(@as(i64, e), @as(i64, cell)))) + 1;
            n = std.math.mul(u64, n, d) catch return std.math.maxInt(u64);
        }
        return n;
    }

    pub fn cellCount(self: *const Spray) u32 {
        return self.grid_dims[0] * self.grid_dims[1] * self.grid_dims[2];
    }

    /// A world coordinate's cell index on one axis. UNCLAMPED, and i64 —
    /// callers clamp into the grid, which is not a nicety: the bounds are cut
    /// from the live rows, so a query's radius reaches past the edge by
    /// design and there is nothing out there to find.
    fn cellAxis(self: *const Spray, v: i64, a: usize) i64 {
        return @divFloor(v - @as(i64, self.grid_origin[a]), @as(i64, self.grid_cell));
    }

    fn cellOf(self: *const Spray, q: [3]Fixed) u32 {
        var ix: [3]u64 = undefined;
        inline for (0..3) |a| {
            const k = self.cellAxis(@as(i64, q[a]), a);
            ix[a] = @intCast(std.math.clamp(k, 0, @as(i64, self.grid_dims[a]) - 1));
        }
        return @intCast((ix[2] * self.grid_dims[1] + ix[1]) * self.grid_dims[0] + ix[0]);
    }

    /// Every live row within `radius` of row `r`, itself excluded, into
    /// `out`. Only the cells the sphere can actually touch are walked — not a
    /// fixed 27 — and a run of them along x is ONE range, because x is the
    /// contiguous axis. A radius narrower than the cell asks for two cells on
    /// an axis and gets two; a radius wider than the cell asks for more and
    /// gets more, which is why `near` no longer refuses one (it used to, and
    /// had to: three cells an axis was all the old search could do, so a
    /// wider radius would have MISSED rows rather than found them).
    pub fn gatherNear(self: *const Spray, r: u32, radius: Fixed, out: []u32) struct { n: u32, crowded: bool } {
        const r2 = fixed.mul(radius, radius);
        const me = self.neigh_pos[r];
        var lo: [3]u32 = undefined;
        var hi: [3]u32 = undefined;
        inline for (0..3) |a| {
            const last: i64 = @as(i64, self.grid_dims[a]) - 1;
            const l = self.cellAxis(@as(i64, me[a]) - @as(i64, radius), a);
            const h = self.cellAxis(@as(i64, me[a]) + @as(i64, radius), a);
            lo[a] = @intCast(std.math.clamp(l, 0, last));
            hi[a] = @intCast(std.math.clamp(h, 0, last));
        }
        var n: u32 = 0;
        var iz = lo[2];
        while (iz <= hi[2]) : (iz += 1) {
            var iy = lo[1];
            while (iy <= hi[1]) : (iy += 1) {
                const base = (@as(usize, iz) * self.grid_dims[1] + iy) * self.grid_dims[0];
                const s = self.grid_starts[base + lo[0]];
                const e = self.grid_starts[base + hi[0] + 1];
                for (self.grid_items[s..e]) |it| {
                    if (it.id == r) continue;
                    var d2: i64 = 0;
                    inline for (0..3) |a| {
                        const d = me[a] -% it.pos[a];
                        d2 += @as(i64, fixed.mul(d, d));
                    }
                    if (d2 > @as(i64, r2)) continue;
                    // The cap is reached: STOP, do not keep scanning. `near`
                    // hands on the first `out.len` and reports the CAPPED
                    // count, so every row found past here was already being
                    // thrown away — the old code walked the rest of the cell
                    // to discard it. In a crowd that was half the query.
                    if (n >= out.len) return .{ .n = n, .crowded = true };
                    out[n] = it.id;
                    n += 1;
                }
            }
        }
        // Walked every cell the sphere touches without filling `out`.
        return .{ .n = n, .crowded = false };
    }

    /// A row's position as the neighbourhood saw it — the snapshot, not the
    /// live store. `push` leans away from where things WERE this tick.
    pub fn neighPos(self: *const Spray, id: u32) [3]Fixed {
        return self.neigh_pos[id];
    }

    /// A row's velocity as the neighbourhood saw it.
    pub fn neighVel(self: *const Spray, id: u32) [3]Fixed {
        return self.neigh_vel[id];
    }

    /// A row's user channel as the neighbourhood saw it.
    pub fn neighUser(self: *const Spray, id: u32, ch: u16) Fixed {
        return self.neigh_user[@as(usize, id) * population.USER_CHANNELS + ch];
    }

    /// This row's slice of the per-chunk neighbour buffer.
    pub fn neighBuf(self: *Spray, r: u32) []u32 {
        const c = r / self.chunk;
        return self.neigh_bufs[c * MAX_NEIGHBOURS ..][0..MAX_NEIGHBOURS];
    }

    /// Declare what the rows' coordinate channels mean. Refuses a channel
    /// this population does not have, by name, rather than leaving a host to
    /// read a coordinate nobody wrote.
    pub fn setAppearance(self: *Spray, a: Appearance) error{BadAppearance}!void {
        try a.check();
        self.appearance = a;
        self.said_appearance = false;
    }

    pub fn deinit(self: *Spray) void {
        self.unmountKernel();
        self.gpa.free(self.grid_starts);
        self.gpa.free(self.grid_items);
        self.gpa.free(self.neigh_pos);
        self.gpa.free(self.neigh_vel);
        self.gpa.free(self.dep_amp);
        self.gpa.free(self.neigh_user);
        self.gpa.free(self.neigh_bufs);
        self.pop.deinit();
        self.gpa.free(self.chunk_steps);
        self.gpa.free(self.chunk_dirty);
        self.dropArrayCasts();
        self.array_casts.deinit(self.gpa);
        for (self.lattices) |l| self.gpa.free(l.values);
        self.gpa.free(self.lattices);
        self.bag_scratch.deinit(self.gpa);
    }

    // -- the kernel ----------------------------------------------------------

    /// Parse `source` with `reg` and mount it on this spray's rows. A
    /// refusal — parse or mount — lands in `diag` in words, and the error
    /// names which. `reg` must outlive the spray: the program borrows it.
    /// A spray with a kernel mounted must not be moved: the runtime holds a
    /// pointer to the program inside it.
    /// The part of `path` after this spray's own broadcast prefix, or null
    /// if the path is somebody else's. `@self` and the spray's own `@name`
    /// are the same room.
    fn ownKnobTail(self: *const Spray, path: []const u8) ?[]const u8 {
        const pre = "plane.drift.@";
        if (!std.mem.startsWith(u8, path, pre)) return null;
        const rest = path[pre.len..];
        inline for (.{ "self", "" }) |lit| {
            const who = if (lit.len != 0) lit else self.name;
            if (rest.len > who.len + 1 and std.mem.startsWith(u8, rest, who) and rest[who.len] == '.') {
                return rest[who.len + 1 ..];
            }
        }
        return null;
    }

    pub fn mountKernel(self: *Spray, reg: *rill.Registry, kernel_name: []const u8, source: []const u8, diag: *rill.registry.Detail) MountError!void {
        self.unmountKernel();
        var pdiag = rill.Diag{};
        var prog = rill.parseKernel(self.gpa, reg, kernel_name, source, &pdiag) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                diag.set("{s}:{d}:{d}: {s}", .{ kernel_name, pdiag.line, pdiag.col, pdiag.msg() });
                return error.Parse;
            },
        };
        errdefer prog.deinit();
        // The spray's own refusals, before rill's: a `hear` of a channel the
        // archetype does not sample has no lattice to read, and the answer
        // is the archetype's declaration, not a zero.
        for (prog.nodes.items) |*n| {
            const def = reg.get(n.op);
            if (!std.mem.eql(u8, def.name, "hear")) continue;
            const chan = n.statics[0].channel;
            if (self.fields == null) {
                diag.set("{s}: '{s} at …' — this spray has no field store to hear; the host mounted it without fields", .{ n.name, chan });
                return error.Mount;
            }
            const declared = for (self.samples) |s| {
                if (std.mem.eql(u8, s.channel, chan)) break true;
            } else false;
            if (!declared) {
                diag.set("{s}: '{s} at …' — this spray does not sample {s}; declare `samples {s} cell <c>` on its ^spray", .{ n.name, chan, chan, chan });
                return error.Mount;
            }
        }
        // The kernel's knobs live in their own room (2026-09-07, ruled).
        // `rate`, `speed`, `spread` and `life` under the spray's own @name
        // are the SPRAY's — the host's documented interface, driven from a
        // rill (`write plane.drift.@sparks.rate 2 mul`) and re-read by the
        // host every tick. Everything else a kernel wants to be told goes
        // under `.k.`, and naming it flat is refused HERE rather than
        // obeyed: `plane.drift.@self.spread` meant as a kernel's own
        // spreading rate silently retuned the launch cone to 0.013 cells/s
        // while the mount line printed the 1.6 the flag had asked for, and
        // every row went up in a pencil, green. One path, two owners, and
        // neither of them wrong — so the fix is a room, not a rule about
        // names. Gravity moved with the rest: it was never a spray knob,
        // only a kernel one that drift-run seeded on the flat path, which
        // is the whole confusion in miniature.
        for (prog.subs.items) |sub| {
            const tail = self.ownKnobTail(sub.path) orelse continue;
            if (std.mem.startsWith(u8, tail, "k.")) continue;
            const reserved = for (SPRAY_KNOBS) |r| {
                if (std.mem.eql(u8, tail, r)) break true;
            } else false;
            if (!reserved) {
                diag.set("{s}: '{s}' is in the spray's own room — {s} is not one of its knobs ({s}). A kernel's own knobs go under `.k.`: say `plane.drift.@self.k.{s}`", .{ kernel_name, sub.path, tail, "rate, speed, spread, life", tail });
                return error.Mount;
            }
        }
        self.wants_neighbours = false;
        self.dep_channel = "";
        for (prog.nodes.items) |*n| {
            const nm = reg.get(n.op).name;
            if (std.mem.eql(u8, nm, "near")) self.wants_neighbours = true;
            if (!std.mem.eql(u8, nm, "deposit")) continue;
            // A row leaves ONE mark a tick, so the spray keeps one slot per
            // row and one channel — which means a second `deposit` would
            // silently overwrite the first for every row. Refused here
            // rather than ruled in a comment.
            if (self.dep_channel.len != 0) {
                diag.set("{s}: a second `deposit` — a row leaves one mark a tick, and this would overwrite the one to {s}; pick a channel and deposit to it once", .{ n.name, self.dep_channel });
                return error.Mount;
            }
            const chan = n.statics[0].channel;
            if (self.fields == null) {
                diag.set("{s}: 'deposit {s} …' — this spray has no field store to deposit into; the host mounted it without fields", .{ n.name, chan });
                return error.Mount;
            }
            self.dep_channel = chan;
        }

        // `mount` borrows a pointer to the program; the Kernel owns both, so
        // build the kernel in place and mount against its own field.
        self.kernel = .{ .prog = prog, .rt = undefined };
        const k = &self.kernel.?;
        k.rt = rill.row.Runtime.mount(self.gpa, &k.prog, self.pop.asRowPlane(), diag) catch |err| switch (err) {
            error.OutOfMemory => {
                self.kernel = null;
                return error.OutOfMemory;
            },
            else => {
                self.kernel = null;
                return error.Mount;
            },
        };
    }

    pub fn unmountKernel(self: *Spray) void {
        const k = &(self.kernel orelse return);
        for (k.scratches) |*s| s.deinit();
        self.gpa.free(k.scratches);
        k.rt.deinit();
        k.prog.deinit();
        self.kernel = null;
        self.dropArrayCasts();
    }

    fn dropArrayCasts(self: *Spray) void {
        for (self.array_casts.items) |c| {
            self.gpa.free(c.bytes);
            self.gpa.free(c.vals);
        }
        self.array_casts.clearRetainingCapacity();
    }

    pub fn hasKernel(self: *const Spray) bool {
        return self.kernel != null;
    }

    /// Which chunks changed this tick, for a renderer's upload. Valid after
    /// `tick`; one entry per chunk of `chunk` rows.
    pub fn dirtyChunks(self: *const Spray) []const bool {
        return self.chunk_dirty;
    }

    /// The rows' own marks, handed to the host in ROW ID ORDER — serial, in
    /// the cast phase, because the sweep that filled these slots is parallel
    /// and a store is a store. Same phase as the aggregate cast and for the
    /// same reason: both are the spray writing to fields, and neither may
    /// happen while rows are still moving.
    ///
    /// The radius is the row's own `size`, which is the only honest answer —
    /// a mark is as wide as the thing that left it — and a row with no size
    /// leaves nothing. Every slot is cleared on the way past, so a row that
    /// stops depositing stops depositing.
    fn flushDeposits(self: *Spray, stats: *Stats) void {
        if (self.dep_channel.len == 0) return;
        const host = self.fields orelse return;
        var id: u32 = 0;
        while (id < self.pop.capacity) : (id += 1) {
            const amp = self.dep_amp[id];
            if (amp == 0) continue;
            self.dep_amp[id] = 0;
            if (!self.pop.alive[id]) continue;
            const r = self.pop.size[id];
            if (r <= 0) continue;
            host.deposit(self.name, self.now.time_ns, .{
                .channel = self.dep_channel,
                .pos = .{ fixed.toF32(self.pop.pos[0][id]), fixed.toF32(self.pop.pos[1][id]), fixed.toF32(self.pop.pos[2][id]) },
                .amplitude = fixed.toF32(amp),
                .radius = fixed.toF32(r),
            }) catch {
                stats.deposits_refused += 1;
                continue;
            };
            stats.deposits += 1;
        }
    }

    /// The lattice for a sampled channel, for `hear`. Null = not sampled.
    pub fn lattice(self: *const Spray, channel: []const u8) ?*const Lattice {
        for (self.lattices) |*l| {
            if (std.mem.eql(u8, l.channel, channel)) return l;
        }
        return null;
    }

    // -- the tick ------------------------------------------------------------

    /// One fed tick. The first call sets the epoch (dt = 0: nothing spawns,
    /// nothing moves); every later call advances by the fed delta. `js` null
    /// runs the sweep inline on the caller. `plane` is where broadcasts are
    /// read from and the count is said to; null is a spray with no world to
    /// talk to (the kernel's `plane.…` reads then stay quiet).
    pub fn tick(self: *Spray, now: Now, js: ?*jobs.JobSystem, plane: ?rill.Plane) TickError!void {
        if (self.started and (now.time_ns < self.now.time_ns or now.frame < self.now.frame)) {
            return error.TimeRegression;
        }
        const dt_ns: u64 = if (self.started) now.time_ns - self.now.time_ns else 0;
        self.now = now;
        self.started = true;
        const dt = fixed.fromNs(dt_ns);

        var stats = Stats{};
        try self.sizeChunks();
        @memset(self.chunk_dirty, false);
        try self.broadcastPhase(plane);
        try self.materialisePhase(&stats);
        self.spawnPhase(dt_ns, &stats);
        self.crowded_rows = 0;
        self.buildNeighbourhood(); // phase 3's tail: one snapshot of where everybody is
        if (self.wants_neighbours) {
            stats.neigh_cell = self.grid_cell;
            stats.neigh_cells = self.cellCount();
        }
        try self.sweepPhase(dt, dt_ns, js, &stats);
        stats.crowded = self.crowded_rows;
        self.reapPhase(&stats);
        self.castPhase(&stats);
        self.last = stats;
        self.ticks += 1;
        self.staleness = 0;
        if (plane) |p| try self.say(p);
    }

    /// The scheduler's other answer: this tick is not run. Fed time is not
    /// advanced (the next `tick` covers the gap in one larger dt — fed, so
    /// replay holds), staleness grows, and `drift/@<name>/throttled` fires
    /// as a MAILBOX occurrence carrying how long the spray has waited. The
    /// spawn-refusal COUNT keeps its own word, `refused`.
    pub fn carryOver(self: *Spray, plane: ?rill.Plane) !void {
        self.staleness += 1;
        self.last = .{ .carried_over = true };
        const p = plane orelse return;
        var pk = struple.Packer.init(self.gpa);
        defer pk.deinit();
        try pk.appendInt(@intCast(self.staleness));
        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "plane.drift.@{s}.throttled", .{self.name}) catch return error.OutOfMemory;
        p.write(path, pk.bytes(), .occurrence, .base, 0) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => {},
        };
    }

    // -- phase 1: broadcasts ---------------------------------------------------

    fn broadcastPhase(self: *Spray, plane: ?rill.Plane) !void {
        const k = &(self.kernel orelse return);
        const p = plane orelse return;
        var pk = struple.Packer.init(self.gpa);
        defer pk.deinit();
        var path_buf: [512]u8 = undefined;
        for (k.prog.subs.items, 0..) |s, i| {
            if (!k.rt.isBroadcast(i)) continue;
            const path = self.resolveSelf(&path_buf, s.path);
            pk.reset();
            p.read(path, &pk) catch {
                k.rt.setBroadcast(i, null);
                continue;
            };
            if (rill.row.fromStruple(self.gpa, pk.bytes())) |v| {
                k.rt.setBroadcast(i, v);
                continue;
            }
            k.rt.setBroadcast(i, try self.arrayBroadcast(i, pk.bytes()));
        }
    }

    /// An array on a broadcast path: converted when its bytes change and
    /// held here; the same bytes next tick cost a memcmp. Not an array ⇒
    /// null, and the kernel's port refuses per row by name.
    fn arrayBroadcast(self: *Spray, sub: usize, bytes: []const u8) !?Val {
        for (self.array_casts.items, 0..) |c, ci| {
            if (c.sub != sub) continue;
            if (std.mem.eql(u8, c.bytes, bytes)) return .{ .array = c.vals };
            self.gpa.free(c.bytes);
            self.gpa.free(c.vals);
            _ = self.array_casts.swapRemove(ci);
            break;
        }
        const vals = (try rill.row.arrayFromStruple(self.gpa, bytes)) orelse return null;
        errdefer self.gpa.free(vals);
        const owned = try self.gpa.dupe(u8, bytes);
        errdefer self.gpa.free(owned);
        try self.array_casts.append(self.gpa, .{ .sub = sub, .bytes = owned, .vals = vals });
        return .{ .array = vals };
    }

    /// `plane.drift.@self.rate` → `plane.drift.@<name>.rate`. Elsewhere the
    /// path is itself.
    fn resolveSelf(self: *const Spray, buf: []u8, path: []const u8) []const u8 {
        const at = std.mem.indexOf(u8, path, "@self") orelse return path;
        return std.fmt.bufPrint(buf, "{s}@{s}{s}", .{ path[0..at], self.name, path[at + "@self".len ..] }) catch path;
    }

    // -- phase 2: materialise --------------------------------------------------

    /// Rasterise every sampled channel's bag onto its lattice over the
    /// spray's bounds. The bounds are last tick's rows plus the spawn
    /// point, padded by a cell; the cell doubles until the grid fits the
    /// cap. Every grid point sums the engine's kernel over the deposits
    /// this spray hears, is clamped by the channel, and lands as Q16.16 —
    /// the field enters the sim here, once per point per tick.
    fn materialisePhase(self: *Spray, stats: *Stats) !void {
        if (self.samples.len == 0) return;
        if (self.lattices.len != self.samples.len) {
            for (self.lattices) |l| self.gpa.free(l.values);
            self.gpa.free(self.lattices);
            self.lattices = try self.gpa.alloc(Lattice, self.samples.len);
            var made: usize = 0;
            errdefer {
                for (self.lattices[0..made]) |l| self.gpa.free(l.values);
                self.gpa.free(self.lattices);
                self.lattices = &.{};
            }
            for (self.samples, self.lattices) |s, *l| {
                l.* = .{ .channel = s.channel, .declared_cell = s.cell, .values = try self.gpa.alloc(Fixed, MAX_SAMPLES * MAX_SAMPLES * MAX_SAMPLES) };
                made += 1;
            }
        }
        const host = self.fields orelse {
            for (self.lattices) |*l| l.live = false;
            stats.bags_missing += @intCast(self.samples.len);
            return;
        };

        // The box: live rows and the spawn point, padded by one cell.
        var lo = self.pos;
        var hi = self.pos;
        var id: u32 = 0;
        while (id < self.pop.capacity) : (id += 1) {
            if (!self.pop.alive[id]) continue;
            inline for (0..3) |a| {
                lo[a] = @min(lo[a], self.pop.pos[a][id]);
                hi[a] = @max(hi[a], self.pop.pos[a][id]);
            }
        }

        for (self.lattices) |*l| {
            self.bag_scratch.clearRetainingCapacity();
            const maybe_bag = host.bag(l.channel, self.now.time_ns, self.gpa, &self.bag_scratch) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => null, // a refusal is an undeclared channel by another name
            };
            const bag = maybe_bag orelse {
                l.live = false;
                stats.bags_missing += 1;
                continue;
            };
            // Fit: cell doubles until every axis has ≤ MAX_SAMPLES points.
            var cell = l.declared_cell;
            var doublings: u8 = 0;
            var dims: [3]u32 = undefined;
            while (true) {
                var fits = true;
                inline for (0..3) |a| {
                    const extent: i64 = @as(i64, hi[a]) - lo[a] + 2 * @as(i64, cell);
                    const n: i64 = @divFloor(extent + cell - 1, cell) + 1;
                    dims[a] = @intCast(@max(n, 2));
                    if (dims[a] > MAX_SAMPLES) fits = false;
                }
                if (fits or cell >= std.math.maxInt(Fixed) / 2) break;
                cell *= 2;
                doublings += 1;
            }
            inline for (0..3) |a| dims[a] = @min(dims[a], MAX_SAMPLES);
            l.cell = cell;
            l.dims = dims;
            l.coarsened = doublings;
            inline for (0..3) |a| l.origin[a] = lo[a] - cell;
            if (doublings > 0) stats.coarsened += 1;

            // Rasterise.
            var k: u32 = 0;
            while (k < dims[2]) : (k += 1) {
                var j: u32 = 0;
                while (j < dims[1]) : (j += 1) {
                    var i: u32 = 0;
                    while (i < dims[0]) : (i += 1) {
                        const at = [3]f32{
                            fixed.toF32(l.origin[0] +% @as(Fixed, @intCast(i)) * cell),
                            fixed.toF32(l.origin[1] +% @as(Fixed, @intCast(j)) * cell),
                            fixed.toF32(l.origin[2] +% @as(Fixed, @intCast(k)) * cell),
                        };
                        var value: f32 = 0;
                        for (bag.deposits) |d| {
                            if (!fields_mod.hears(d, self.carried)) continue;
                            const kv = fields_mod.kernelAt(d, at) orelse continue;
                            value += kv.value;
                        }
                        l.values[l.index(i, j, k)] = fixed.fromF32Saturating(std.math.clamp(value, bag.clamp_lo, bag.clamp_hi));
                    }
                }
            }
            l.live = true;
        }
    }

    // -- phase 3: spawn (serial) -----------------------------------------------

    fn spawnPhase(self: *Spray, dt_ns: u64, stats: *Stats) void {
        if (dt_ns == 0) return;
        const one_row: i128 = @as(i128, fixed.ONE) * std.time.ns_per_s;
        self.spawn_acc += @as(i128, self.knobs.rate) * dt_ns;
        if (self.spawn_acc < 0) self.spawn_acc = 0; // a negative rate owes nothing, and owes nothing later
        var owed: u32 = @intCast(@divFloor(self.spawn_acc, one_row));
        self.spawn_acc -= @as(i128, owed) * one_row;
        while (owed > 0) : (owed -= 1) {
            const id = self.pop.spawn() orelse {
                stats.refused += owed;
                return;
            };
            const p = &self.pop;
            p.seed[id] = mix(self.seed, self.spawned);
            self.spawned +%= 1;
            p.life_ns[id] = self.knobs.life_ns;
            p.size[id] = fixed.ONE;
            p.colour[0][id] = fixed.ONE;
            p.alpha[id] = fixed.ONE; // opaque until a kernel fades it (beat 6)
            inline for (0..3) |a| p.pos[a][id] = self.pos[a];
            stats.spawned += 1;
        }
    }

    // -- phase 4: the sweep (chunked) ------------------------------------------

    const SweepCtx = struct { spray: *Spray, dt: Fixed, dt_ns: u64 };

    /// A host that wants the chunk its own way. Say it BEFORE handing the
    /// spray anywhere: a host sizes its per-chunk arrays from `chunk` when it
    /// takes the spray, and moving it afterwards leaves those the wrong
    /// length — which in matryoshka means the spray runs and draws nothing.
    pub fn setChunk(self: *Spray, rows: u32) void {
        self.chunk = @max(1, rows);
    }

    /// The per-chunk arrays follow `chunk`, which a host may set after init.
    fn sizeChunks(self: *Spray) !void {
        const n_chunks: usize = (self.pop.capacity + self.chunk - 1) / self.chunk;
        if (self.chunk_steps.len != n_chunks) {
            self.gpa.free(self.chunk_steps);
            self.chunk_steps = try self.gpa.alloc(u32, n_chunks);
        }
        if (self.chunk_dirty.len != n_chunks) {
            self.gpa.free(self.chunk_dirty);
            self.chunk_dirty = try self.gpa.alloc(bool, n_chunks);
            @memset(self.chunk_dirty, false);
        }
        if (self.neigh_bufs.len != n_chunks * MAX_NEIGHBOURS) {
            self.gpa.free(self.neigh_bufs);
            self.neigh_bufs = try self.gpa.alloc(u32, n_chunks * MAX_NEIGHBOURS);
        }
    }

    fn sweepPhase(self: *Spray, dt: Fixed, dt_ns: u64, js: ?*jobs.JobSystem, stats: *Stats) !void {
        const n_chunks: usize = self.chunk_steps.len;
        @memset(self.chunk_steps, 0);
        if (self.kernel) |*k| {
            if (k.scratches.len != n_chunks) {
                for (k.scratches) |*s| s.deinit();
                self.gpa.free(k.scratches);
                k.scratches = try self.gpa.alloc(rill.row.Scratch, n_chunks);
                var made: usize = 0;
                errdefer {
                    for (k.scratches[0..made]) |*s| s.deinit();
                    self.gpa.free(k.scratches);
                    k.scratches = &.{};
                }
                for (k.scratches) |*s| {
                    s.* = try k.rt.newScratch(self.gpa);
                    made += 1;
                }
            }
            for (k.scratches) |*s| {
                s.refusals = 0;
                s.first_node = null;
            }
        }

        var ctx = SweepCtx{ .spray = self, .dt = dt, .dt_ns = dt_ns };
        if (js) |sys| {
            var counter = jobs.Counter.init(0);
            sys.parallelFor(self.pop.capacity, self.chunk, sweepJob, &ctx, &counter);
            sys.waitFor(&counter);
        } else {
            var start: u32 = 0;
            while (start < self.pop.capacity) : (start += self.chunk) {
                sweepRows(&ctx, start, @min(start + self.chunk, self.pop.capacity));
            }
        }

        var steps: u32 = 0;
        for (self.chunk_steps, self.chunk_dirty) |c, *d| {
            steps += c;
            if (c > 0) d.* = true;
        }
        stats.row_steps = steps;
        // Merge refusals in chunk order — exact, no atomics, one order.
        if (self.kernel) |*k| {
            self.last_refusal.clear();
            for (k.scratches) |*s| {
                stats.refusals += @intCast(s.refusals);
                if (s.first_node != null and self.last_refusal.len == 0) {
                    self.last_refusal.set("{s}", .{s.first.text()});
                }
            }
        }
    }

    fn sweepJob(job: *jobs.Job) void {
        const range = job.getData(jobs.BatchRange);
        const ctx: *const SweepCtx = @ptrCast(@alignCast(range.context));
        sweepRows(ctx, range.start, range.end);
    }

    /// Per row: the kernel, then integration, then age. Row-local by
    /// construction — the only indices touched are `id`'s own, plus this
    /// chunk's own step slot and scratch. The lattices are read-only here.
    fn sweepRows(ctx: *const SweepCtx, start: u32, end: u32) void {
        const s = ctx.spray;
        const p = &s.pop;
        const chunk_index = start / s.chunk;
        const dt = ctx.dt;
        var steps: u32 = 0;
        var id = start;
        while (id < end) : (id += 1) {
            if (!p.alive[id]) continue;
            if (s.kernel) |*k| k.rt.evalRow(&k.scratches[chunk_index], id, dt, s);
            // A stuck row has no velocity (beat 4, ruled: position the hit
            // point, velocity zero, `row.stuck` set). Held HERE, once, after
            // the kernel's writes land — not in every force word. The first
            // draft only zeroed the velocity in `stick`; the next tick's
            // `gravity` put it back and the landed row sank through the
            // floor at 2.5 cells a tick. This is the one rule: the integrate
            // below then moves it nowhere (a draft that also skipped the
            // integrate survived the mutation that removed the skip — a
            // decoration, deleted). A stuck row still ages and still reads
            // its curves; it just stays where it landed.
            if (p.stuck[id] != 0) {
                inline for (0..3) |a| p.vel[a][id] = 0;
            }
            // integrate — a velocity moves its position; not a word
            inline for (0..3) |a| p.pos[a][id] += fixed.mul(p.vel[a][id], dt);
            // age — fed nanoseconds, exact
            p.age_ns[id] += ctx.dt_ns;
            steps += 1;
        }
        s.chunk_steps[chunk_index] = steps;
    }

    // -- phase 5: reap (serial, ascending) -------------------------------------

    fn reapPhase(self: *Spray, stats: *Stats) void {
        var id: u32 = 0;
        while (id < self.pop.capacity) : (id += 1) {
            if (self.pop.alive[id] and self.pop.doomed[id]) {
                self.pop.kill(id);
                stats.died += 1;
            }
        }
    }

    // -- phase 6: cast ----------------------------------------------------------

    /// One aggregate per declared channel: the centre of mass of the live
    /// rows (an exact integer mean, then one conversion), amplitude = per-row
    /// × live, radius from the bounds. The host replaces last tick's. No
    /// live rows, no cast — the previous one decays on its own; unmount
    /// withdraws it.
    fn castPhase(self: *Spray, stats: *Stats) void {
        self.flushDeposits(stats);
        if (self.casts.len == 0 or self.pop.live == 0) return;
        const host = self.fields orelse {
            stats.cast_refusals += @intCast(self.casts.len);
            return;
        };
        var sum: [3]i64 = .{ 0, 0, 0 };
        var lo: Vec = undefined;
        var hi: Vec = undefined;
        var any = false;
        var id: u32 = 0;
        while (id < self.pop.capacity) : (id += 1) {
            if (!self.pop.alive[id]) continue;
            inline for (0..3) |a| {
                const v = self.pop.pos[a][id];
                sum[a] += v;
                if (!any or v < lo[a]) lo[a] = v;
                if (!any or v > hi[a]) hi[a] = v;
            }
            any = true;
        }
        const n: i64 = self.pop.live;
        const centre = [3]f32{
            fixed.toF32(@intCast(@divFloor(sum[0], n))),
            fixed.toF32(@intCast(@divFloor(sum[1], n))),
            fixed.toF32(@intCast(@divFloor(sum[2], n))),
        };
        var half_diag: f32 = 0;
        inline for (0..3) |a| {
            const e = fixed.toF32(hi[a] -% lo[a]) / 2;
            half_diag += e * e;
        }
        half_diag = @sqrt(half_diag);
        for (self.casts) |c| {
            const radius: f32 = switch (c.radius) {
                .bounds => @max(half_diag, 1.0),
                .fixed => |r| r,
            };
            host.cast(self.name, self.now.time_ns, .{
                .channel = c.channel,
                .pos = centre,
                .amplitude = c.per_row_amplitude * @as(f32, @floatFromInt(self.pop.live)),
                .radius = radius,
                .decay_ns = c.decay_ns,
                .to = c.to,
            }) catch {
                stats.cast_refusals += 1;
            };
        }
    }

    // -- the plane -------------------------------------------------------------

    /// Say what the population is: `count`, `bounds` and `digest`, each
    /// written only when it changed. The population itself never leaves
    /// memory except through a dump (campaign §3.1).
    pub fn say(self: *Spray, plane: rill.Plane) !void {
        var pk = struple.Packer.init(self.gpa);
        defer pk.deinit();
        var path_buf: [256]u8 = undefined;

        const count = self.pop.live;
        if (self.said_count != count) {
            pk.reset();
            try pk.appendInt(count);
            try self.write(plane, &path_buf, "count", pk.bytes());
            self.said_count = count;
        }

        const now_digest = self.digest();
        if (self.said_digest != now_digest) {
            pk.reset();
            try pk.appendInt(@bitCast(now_digest));
            try self.write(plane, &path_buf, "digest", pk.bytes());
            self.said_digest = now_digest;
        }

        const now_bounds = self.bounds();
        const same = if (self.said_bounds) |b| std.mem.eql(Fixed, &b, &now_bounds) else false;
        if (!same) {
            pk.reset();
            try packBounds(self.gpa, &pk, now_bounds);
            try self.write(plane, &path_buf, "bounds", pk.bytes());
            self.said_bounds = now_bounds;
        }

        // `coarsened` (ruled, beat 2 accepted): how many times the declared
        // cell was doubled to fit the cap, the largest over the sampled
        // channels; zero when the declared cell held. Change-only, so a
        // sentry can watch it and not only the Spray applet. A function of
        // the bounds and the declared cell alone — fed inputs — so a
        // coarsened run replays byte-identical (gated).
        // The appearance is a DECLARATION, not a measurement: it changes
        // when a host changes it and not otherwise, so it is said once and
        // then not again. Said at all only when there is one — a spray whose
        // rows mean nothing in particular says nothing, rather than saying a
        // default somebody might read as a promise.
        if (self.appearance) |ap| {
            if (!self.said_appearance) {
                pk.reset();
                try packAppearance(self.gpa, &pk, ap);
                try self.write(plane, &path_buf, "appearance", pk.bytes());
                self.said_appearance = true;
            }
        }

        const now_coarsened = self.coarsened();
        if (self.said_coarsened != now_coarsened) {
            pk.reset();
            try pk.appendInt(now_coarsened);
            try self.write(plane, &path_buf, "coarsened", pk.bytes());
            self.said_coarsened = now_coarsened;
        }
    }

    /// The largest doubling any sampled channel's lattice took this tick.
    pub fn coarsened(self: *const Spray) u32 {
        var worst: u32 = 0;
        for (self.lattices) |l| {
            if (l.live) worst = @max(worst, l.coarsened);
        }
        return worst;
    }

    /// Absence, said: `count` is zero, the kernel is gone, and the spray's
    /// casts are withdrawn — ownership is the ceiling. The other two leaves
    /// keep their last value (a bound of nothing is not a box).
    pub fn unmount(self: *Spray, plane: rill.Plane) !void {
        self.unmountKernel();
        if (self.fields) |f| f.withdraw(self.name);
        var pk = struple.Packer.init(self.gpa);
        defer pk.deinit();
        var path_buf: [256]u8 = undefined;
        try pk.appendInt(0);
        try self.write(plane, &path_buf, "count", pk.bytes());
        self.said_count = 0;
    }

    fn write(self: *const Spray, plane: rill.Plane, buf: []u8, leaf: []const u8, bytes: []const u8) !void {
        const path = std.fmt.bufPrint(buf, "plane.drift.@{s}.{s}", .{ self.name, leaf }) catch return error.OutOfMemory;
        plane.write(path, bytes, .value, .base, 0) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => {}, // a plane that refuses the say is a host matter; the sim is unchanged
        };
    }

    /// A cheap change detector over the live rows, in id order: positions,
    /// velocities and ages. Not the dump's digest (that is over the dump's
    /// bytes, and building a dump every tick to hash it is a dump every
    /// tick); a sensor that wants "did anything move" wants this.
    pub fn digest(self: *const Spray) u64 {
        var h = std.hash.Wyhash.init(0);
        var id: u32 = 0;
        while (id < self.pop.capacity) : (id += 1) {
            if (!self.pop.alive[id]) continue;
            h.update(std.mem.asBytes(&id));
            inline for (0..3) |a| {
                h.update(std.mem.asBytes(&self.pop.pos[a][id]));
                h.update(std.mem.asBytes(&self.pop.vel[a][id]));
            }
            h.update(std.mem.asBytes(&self.pop.age_ns[id]));
        }
        return h.final();
    }

    /// min xyz, max xyz over live rows; all zero when there are none.
    pub fn bounds(self: *const Spray) [6]Fixed {
        var out = [6]Fixed{ 0, 0, 0, 0, 0, 0 };
        var any = false;
        var id: u32 = 0;
        while (id < self.pop.capacity) : (id += 1) {
            if (!self.pop.alive[id]) continue;
            inline for (0..3) |a| {
                const v = self.pop.pos[a][id];
                if (!any or v < out[a]) out[a] = v;
                if (!any or v > out[3 + a]) out[3 + a] = v;
            }
            any = true;
        }
        return out;
    }
};

/// `{max: {x, y, z}, min: {x, y, z}}` in cells, as f64 — the plane is the
/// world's and the world reads floats; this is the boundary, once per tick.
fn packAppearance(gpa: std.mem.Allocator, pk: *struple.Packer, ap: Appearance) !void {
    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    defer arena_impl.deinit();
    const a = arena_impl.allocator();
    // An array's child is the elements' encodings run together — one packer
    // for the three, then framed as the array.
    var elems = struple.Packer.init(a);
    for (ap.coord) |c| try elems.appendInt(c);
    var coord_p = struple.Packer.init(a);
    try coord_p.appendArray(elems.bytes());
    var man_p = struple.Packer.init(a);
    try man_p.appendString(ap.manifold);
    var k_coord = struple.Packer.init(a);
    try k_coord.appendString("coord");
    var k_man = struple.Packer.init(a);
    try k_man.appendString("manifold");
    try pk.appendMap(&.{ .{ k_man.bytes(), man_p.bytes() }, .{ k_coord.bytes(), coord_p.bytes() } });
}

fn packBounds(gpa: std.mem.Allocator, pk: *struple.Packer, b: [6]Fixed) !void {
    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    defer arena_impl.deinit();
    const a = arena_impl.allocator();
    const axes = [_][]const u8{ "x", "y", "z" };
    var halves: [2][]const u8 = undefined;
    for (0..2) |h| {
        var entries: [3][2][]const u8 = undefined;
        for (axes, 0..) |name, i| {
            var kp = struple.Packer.init(a);
            try kp.appendString(name);
            var vp = struple.Packer.init(a);
            try vp.appendF64(fixed.toF64(b[h * 3 + i]));
            entries[i] = .{ kp.bytes(), vp.bytes() };
        }
        var mp = struple.Packer.init(a);
        try mp.appendMap(&entries);
        halves[h] = mp.bytes();
    }
    var kmin = struple.Packer.init(a);
    try kmin.appendString("min");
    var kmax = struple.Packer.init(a);
    try kmax.appendString("max");
    try pk.appendMap(&.{ .{ kmin.bytes(), halves[0] }, .{ kmax.bytes(), halves[1] } });
}

/// A 32-bit mix (murmur3's finaliser over a keyed input). Every row seed
/// and every jitter draw comes from this, so the whole population is a
/// pure function of the spray seed and fed history.
pub fn mix(key: u32, n: u32) u32 {
    var h = key ^ (n *% 0x9E3779B9);
    h ^= h >> 16;
    h *%= 0x85EBCA6B;
    h ^= h >> 13;
    h *%= 0xC2B2AE35;
    h ^= h >> 16;
    return h;
}

/// A per-axis draw in [−spread, spread], integer arithmetic only: the top
/// 32 bits of hash × (2·spread + 1) is a uniform index into that range.
pub fn jitter(row_seed: u32, axis: usize, spread: Fixed) Fixed {
    if (spread <= 0) return 0;
    const h = mix(row_seed, @intCast(axis + 1));
    const span: u64 = @as(u64, @intCast(spread)) * 2 + 1;
    const draw: i64 = @intCast((@as(u64, h) * span) >> 32);
    return @intCast(draw - spread);
}

test "mix: different ordinals under one key are different seeds, and the same is the same" {
    try std.testing.expectEqual(mix(7, 0), mix(7, 0));
    try std.testing.expect(mix(7, 0) != mix(7, 1));
    try std.testing.expect(mix(7, 0) != mix(8, 0));
}

test "jitter: stays inside ±spread and is zero at zero spread" {
    var n: u32 = 0;
    while (n < 1000) : (n += 1) {
        const j = jitter(mix(3, n), 0, fixed.ONE);
        try std.testing.expect(j >= -fixed.ONE and j <= fixed.ONE);
    }
    try std.testing.expectEqual(@as(Fixed, 0), jitter(mix(3, 1), 0, 0));
}

test "lattice: trilinear is exact on the grid and between it on every axis, and the gradient is the slope in amplitude per cell" {
    const gpa = std.testing.allocator;
    var l = Lattice{ .channel = "$t", .declared_cell = fixed.ONE, .cell = fixed.ONE, .origin = .{ 0, 0, 0 }, .dims = .{ 3, 3, 3 }, .values = try gpa.alloc(Fixed, 27), .live = true };
    defer gpa.free(l.values);
    // f = 2x + 3y + 5z: linear, so trilinear reproduces it EXACTLY anywhere,
    // and every axis contributes — a field constant in y and z let a
    // mutation that dropped the y and z lerps survive the first draft of
    // this gate (Q11, ledger): A equalled B on the axes it broke.
    var k: u32 = 0;
    while (k < 3) : (k += 1) {
        var j: u32 = 0;
        while (j < 3) : (j += 1) {
            var i: u32 = 0;
            while (i < 3) : (i += 1) l.values[l.index(i, j, k)] = fixed.fromInt(@intCast(2 * i + 3 * j + 5 * k));
        }
    }
    try std.testing.expectEqual(fixed.fromInt(0), l.sampleAt(.{ 0, 0, 0 }));
    try std.testing.expectEqual(fixed.fromInt(2), l.sampleAt(.{ fixed.ONE, 0, 0 }));
    try std.testing.expectEqual(fixed.fromInt(10), l.sampleAt(.{ fixed.ONE, fixed.ONE, fixed.ONE }));
    try std.testing.expectEqual(fixed.fromInt(5), l.sampleAt(.{ fixed.HALF, fixed.HALF, fixed.HALF })); // 1 + 1.5 + 2.5
    try std.testing.expectEqual(fixed.fromInt(4), l.sampleAt(.{ 0, fixed.HALF, fixed.HALF })); // 0 + 1.5 + 2.5
    try std.testing.expectEqual(fixed.fromInt(3), l.sampleAt(.{ fixed.ONE + fixed.HALF, 0, 0 }));
    // Past the grid clamps to the edge.
    try std.testing.expectEqual(fixed.fromInt(4), l.sampleAt(.{ fixed.fromInt(9), 0, 0 }));
    try std.testing.expectEqual(fixed.fromInt(0), l.sampleAt(.{ -fixed.fromInt(9), 0, 0 }));
    try std.testing.expectEqual(fixed.fromInt(20), l.sampleAt(.{ fixed.fromInt(9), fixed.fromInt(9), fixed.fromInt(9) }));
    // Gradient: (2, 3, 5) per cell everywhere — middle and edges alike.
    try std.testing.expectEqual(Vec{ fixed.fromInt(2), fixed.fromInt(3), fixed.fromInt(5) }, l.gradientAt(.{ fixed.ONE, fixed.ONE, fixed.ONE }));
    try std.testing.expectEqual(Vec{ fixed.fromInt(2), fixed.fromInt(3), fixed.fromInt(5) }, l.gradientAt(.{ 0, 0, 0 }));
    try std.testing.expectEqual(Vec{ fixed.fromInt(2), fixed.fromInt(3), fixed.fromInt(5) }, l.gradientAt(.{ fixed.fromInt(2), fixed.fromInt(2), fixed.fromInt(2) }));
    // A coarser cell halves the per-cell slope of the same field.
    l.cell = 2 * fixed.ONE;
    try std.testing.expectEqual(Vec{ fixed.fromInt(1), @divExact(fixed.fromInt(3), 2), @divExact(fixed.fromInt(5), 2) }, l.gradientAt(.{ 2 * fixed.ONE, 2 * fixed.ONE, 2 * fixed.ONE }));
}
