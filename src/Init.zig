const std = @import("std");
const peripherals = @import("Peripherals.zig");

pub const Init = struct {
    gpa: std.heap.DebugAllocator(.{ .thread_safe = true }),
    arena: std.heap.ArenaAllocator,
    io: std.Io,
    devices: peripherals.Peripherals,
};
