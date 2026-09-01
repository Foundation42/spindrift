//! spindrift — a particle system that is rill-shaped from the first line.
//!
//! Emitters are rill programs, per-particle behaviour is rill operators
//! evaluated over populations, coupling to the world is `$` fields in both
//! directions and tracer verbs. CPU first; the GPU arrives later as a second
//! evaluator of the same text, not a port. See `docs/spindrift-campaign.md`.
//!
//! What this library owns: the population format (`population.zig`), the
//! fixed-point number the sim runs on (`fixed.zig`), the `World` query
//! interface a host implements and the mock floor (`world.zig`), the dump
//! (`dump.zig`), and the emitter with its three-phase tick over
//! `common/jobs.zig` (`emitter.zig`). What it borrows: rill's plane,
//! registry and parser; common's one JobSystem; struple for every byte that
//! leaves memory.
//!
//! P0 (this): population and determinism. The kernel is a Zig stand-in for
//! `spawn`/`gravity`/`perish` that P1 deletes — see `emitter.zig`.
//!
//!     var floor = spindrift.world.Floor{};
//!     var em = try spindrift.Emitter.init(gpa, 4096, seed, floor.asWorld());
//!     defer em.deinit();
//!     em.knobs = .{ .rate = fixed.fromInt(400), .speed = fixed.fromInt(3), .gravity = -fixed.fromInt(10) };
//!     // per fed tick: try em.tick(.{ .frame = f, .time_ns = t }, job_system);
//!     const bytes = try spindrift.dump.write(gpa, &em.pop, em.ticks);

const std = @import("std");

pub const fixed = @import("fixed.zig");
pub const population = @import("population.zig");
pub const world = @import("world.zig");
pub const dump = @import("dump.zig");
pub const emitter = @import("emitter.zig");

// The working surface, re-exported flat.
pub const Fixed = fixed.Fixed;
pub const Vec = fixed.Vec;
pub const Population = population.Population;
pub const Handle = population.Handle;
pub const World = world.World;
pub const Floor = world.Floor;
pub const Nowhere = world.Nowhere;
pub const Emitter = emitter.Emitter;
pub const Knobs = emitter.Knobs;
pub const Stats = emitter.Stats;
pub const Now = emitter.Now;

test {
    _ = @import("fixed.zig"); // the number
    _ = @import("population.zig"); // rows, freelist, handles
    _ = @import("world.zig"); // the query interface and the floor
    _ = @import("dump.zig"); // one canonical struple
    _ = @import("emitter.zig"); // knobs, the tick, the stand-in kernel
    _ = @import("tests.zig"); // the gates: G0 and its mutations
}
