const std = @import("std");
const io = @import("./Io.zig");

pub const Display = @import("display.zig");
pub const Peripherals = @import("Peripherals.zig");
pub const V5Io = io.V5Io;

pub const std_options: std.Options = .{
    .page_size_min = 4 << 10,
    .page_size_max = 4 << 10,
};
