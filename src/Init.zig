const std = @import("std");
const peripherals = @import("Peripherals.zig");

/// The "Juicy Main" — the entry point for all Velox user programs.
///
/// This is a comptime-generic struct. Pass your device configuration as the
/// type parameter and default-initialize to get a fully wired application
/// context.
///
/// ## Fields
///
/// - `.gpa` — a [`std.heap.DebugAllocator`] (formerly `GeneralPurposeAllocator`)
///   with thread safety enabled. Use this for general-purpose allocations in
///   your application.
/// - `.arena` — a [`std.heap.ArenaAllocator`] backed by the GPA. Useful for
///   short-lived allocations that can be freed in bulk.
/// - `.io` — a [`std.Io`] instance backed by [`V5Io`](root.V5Io). Pass this
///   to any function that accepts `std.Io`.
/// - `.devices` — a [`Peripherals`] struct whose fields correspond to the
///   device declarations in your config. Each field is a fully initialized
///   device handle.
///
/// ## Example
///
/// ```zig
/// const velox = @import("velox_sdk");
///
/// // Declare the devices your robot uses.
/// const MyDevices = struct {
///     drive_left: struct { .type = .motor },
///     drive_right: struct { .type = .motor },
///     intake_dist: struct { .type = .distance },
/// };
///
/// pub fn main() void {
///     // Default-initialize everything.
///     var app = velox.Init(MyDevices){};
///
///     // Use the devices.
///     app.devices.drive_left.spinAt(100, .percent);
///     app.devices.drive_right.spinAt(100, .percent);
///
///     // Use the I/O.
///     var stdout = app.io.stdout();
///     _ = try stdout.writeAll("robot ready\n");
/// }
/// ```
pub fn Init(comptime devs: anytype) type {
    return struct {
        /// A `DebugAllocator` (formerly `GeneralPurposeAllocator`) with
        /// thread safety enabled. Use this for general allocations.
        gpa: std.heap.DebugAllocator(.{ .thread_safe = true }),

        /// An `ArenaAllocator` backed by the GPA. Ideal for bulk-freed
        /// temporary allocations.
        arena: std.heap.ArenaAllocator,

        /// The [`std.Io`] instance for this application, providing console
        /// I/O, SD-card file access, concurrency, clocks, and PRNG.
        io: std.Io,

        /// Typed handles to all peripherals declared in the device
        /// configuration. Each field name matches the config struct.
        devices: peripherals.Peripherals(devs),
    };
}
