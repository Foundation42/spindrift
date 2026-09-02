//! scheduler — the row-steps budget over sprays (campaign §3.6, G6).
//!
//! `drift/budget/row_steps` is a knob the sim reads once per tick, never
//! milliseconds. Over budget, sprays are updated by priority computed from
//! FED-TIME-ONLY inputs — staleness first (the spray that has waited
//! longest), then the camera's frustum (`plane.camera`, on the plane),
//! then intersection with a dynamic object — and the rest carry over to
//! the next tick with `drift/@name/throttled` as a MAILBOX occurrence.
//! This is the Sponge policy with the clock removed. A wall-clock governor
//! may write the budget knob, and that write rides the transcript; the sim
//! never reads the clock — which is what makes a throttled tick replay
//! byte-identically.
//!
//! One rule the campaign did not state, and this file does: **the
//! highest-priority spray always runs**, budget or no. A budget below the
//! smallest spray would otherwise be a dead sim that says `throttled`
//! forever; the budget bounds the total, it does not veto the first.
//!
//! Pure over its inputs and allocation-free: the host hands candidates and
//! a scratch, and gets back which run. Deterministic by construction —
//! the sort is a stable insertion sort over (staleness desc, frustum,
//! dynamic, index).

const std = @import("std");

/// Fed-time-only inputs, per spray, from the host.
pub const Priority = struct {
    /// Ticks this spray has been carried over. The one that waited longest
    /// runs first — starvation is the failure the order exists to prevent.
    staleness: u64 = 0,
    /// Its bounds are in the camera's frustum this tick.
    in_frustum: bool = true,
    /// Its bounds intersect a dynamic-tree object this tick.
    touches_dynamic: bool = false,
};

pub const Candidate = struct {
    /// Row-steps this spray would spend: its live rows.
    rows: u32,
    priority: Priority = .{},
};

fn before(a: Candidate, ai: u32, b: Candidate, bi: u32) bool {
    if (a.priority.staleness != b.priority.staleness) return a.priority.staleness > b.priority.staleness;
    if (a.priority.in_frustum != b.priority.in_frustum) return a.priority.in_frustum;
    if (a.priority.touches_dynamic != b.priority.touches_dynamic) return a.priority.touches_dynamic;
    return ai < bi;
}

/// Decide which candidates run this tick. `run[i]` is set for those that
/// fit the budget in priority order; `order` is scratch of `cands.len`.
/// Returns the row-steps planned. The first in priority order always runs.
pub fn plan(cands: []const Candidate, budget: u32, run: []bool, order: []u32) u32 {
    std.debug.assert(run.len == cands.len and order.len == cands.len);
    for (order, 0..) |*o, i| o.* = @intCast(i);
    // Stable insertion sort: n is a handful of sprays, and the order must
    // be the same on every machine — no pdq, no library fast path.
    var i: usize = 1;
    while (i < order.len) : (i += 1) {
        const key = order[i];
        var j = i;
        while (j > 0 and before(cands[key], key, cands[order[j - 1]], order[j - 1])) : (j -= 1) {
            order[j] = order[j - 1];
        }
        order[j] = key;
    }
    @memset(run, false);
    var spent: u32 = 0;
    for (order, 0..) |idx, rank| {
        const c = cands[idx];
        if (rank == 0 or spent + c.rows <= budget) {
            run[idx] = true;
            spent += c.rows;
        }
    }
    return spent;
}

test "scheduler: staleness first, then frustum, then dynamic, ties by index; the first always runs" {
    const cands = [_]Candidate{
        .{ .rows = 50, .priority = .{ .staleness = 0, .in_frustum = true } },
        .{ .rows = 50, .priority = .{ .staleness = 2, .in_frustum = false } },
        .{ .rows = 50, .priority = .{ .staleness = 0, .in_frustum = true, .touches_dynamic = true } },
        .{ .rows = 50, .priority = .{ .staleness = 0, .in_frustum = false } },
    };
    var run: [4]bool = undefined;
    var order: [4]u32 = undefined;
    // Budget for two: the stale one, then the dynamic-touching one in view.
    try std.testing.expectEqual(@as(u32, 100), plan(&cands, 100, &run, &order));
    try std.testing.expectEqual([4]u32{ 1, 2, 0, 3 }, order);
    try std.testing.expectEqual([4]bool{ false, true, true, false }, run);
    // A budget below the smallest spray still runs the first: not a dead sim.
    try std.testing.expectEqual(@as(u32, 50), plan(&cands, 10, &run, &order));
    try std.testing.expectEqual([4]bool{ false, true, false, false }, run);
    // Room for all: all run, in any order.
    try std.testing.expectEqual(@as(u32, 200), plan(&cands, 1000, &run, &order));
    try std.testing.expectEqual([4]bool{ true, true, true, true }, run);
    // Ties break by index, so the order is a function of the inputs alone.
    const same = [_]Candidate{ .{ .rows = 1 }, .{ .rows = 1 }, .{ .rows = 1 } };
    var run3: [3]bool = undefined;
    var order3: [3]u32 = undefined;
    _ = plan(&same, 2, &run3, &order3);
    try std.testing.expectEqual([3]u32{ 0, 1, 2 }, order3);
    try std.testing.expectEqual([3]bool{ true, true, false }, run3);
}
