//! spindrift — a particle system that is rill-shaped from the first line.
//!
//! Emitters are rill programs, per-particle behaviour is rill operators
//! evaluated over populations, coupling to the world is `$` fields in both
//! directions and tracer verbs. CPU first; the GPU arrives later as a second
//! evaluator of the same text, not a port. See `docs/spindrift-campaign.md`.
//!
//! What this library owns: the population format and the row plane a
//! kernel is mounted on (`population.zig`), the fixed-point number the sim
//! runs on (`fixed.zig`), the `World` query interface a host implements and
//! the mock floor (`world.zig`), the dump (`dump.zig`), the spray with its
//! four-phase tick over `common/jobs.zig` (`spray.zig`), and the words —
//! `spawn`, `gravity`, `perish` — registered into rill's registry like any
//! other (`words.zig`). What it borrows: rill's plane, registry, parser and
//! row runtime; common's one JobSystem; struple for every byte that leaves
//! memory.
//!
//! P1 (this): the kernel is rill text mounted on the spray.
//!
//!     var reg = try rill.Registry.init(gpa);
//!     try rill.registerCore(&reg);
//!     try spindrift.words.register(&reg);
//!     var floor = spindrift.Floor{};
//!     var spray = try spindrift.Spray.init(gpa, 4096, seed, floor.asWorld());
//!     defer spray.deinit();
//!     spray.knobs = .{ .rate = fixed.fromInt(400), .speed = fixed.fromInt(3) };
//!     var diag = rill.registry.Detail{};
//!     try spray.mountKernel(&reg, "embers", "spawn\ngravity -9.8\nperish", &diag);
//!     // per fed tick: try spray.tick(.{ .frame = f, .time_ns = t }, job_system, plane);
//!     const bytes = try spindrift.dump.write(gpa, &spray.pop, spray.ticks);

const std = @import("std");

pub const fixed = @import("fixed.zig");
pub const population = @import("population.zig");
pub const world = @import("world.zig");
pub const dump = @import("dump.zig");
pub const spray = @import("spray.zig");
pub const words = @import("words.zig");

// The working surface, re-exported flat.
pub const Fixed = fixed.Fixed;
pub const Vec = fixed.Vec;
pub const Population = population.Population;
pub const Handle = population.Handle;
pub const World = world.World;
pub const Floor = world.Floor;
pub const Nowhere = world.Nowhere;
pub const Spray = spray.Spray;
pub const Knobs = spray.Knobs;
pub const Stats = spray.Stats;
pub const Now = spray.Now;

test {
    _ = @import("fixed.zig"); // the number
    _ = @import("population.zig"); // rows, freelist, handles
    _ = @import("world.zig"); // the query interface and the floor
    _ = @import("dump.zig"); // one canonical struple
    _ = @import("spray.zig"); // knobs, the tick, the kernel mount
    _ = @import("words.zig"); // spawn, gravity, perish
    _ = @import("tests.zig"); // the gates: G0 and its mutations
}
