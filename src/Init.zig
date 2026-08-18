const std = @import("std");
const peripherals = @import("Peripherals.zig");

pub fn Init(comptime devs: anytype) type {
    return struct {
        /// A DebugAllocator (formerly GeneralPurposeAllocator) provided for the user's use
        gpa: std.heap.DebugAllocator(.{ .thread_safe = true }),
        /// An ArenaAllocator provided for the user's use
        arena: std.heap.ArenaAllocator,
        /// An Io implementation
        io: std.Io,
        /// Access to device peripherals (SmartPort/ADI devices defined at comptime)
        devices: peripherals.Peripherals(devs),
    };
}
