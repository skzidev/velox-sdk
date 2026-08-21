//! # Velox SDK
//!
//! The Velox SDK provides a safe, idiomatic Zig abstraction layer over the
//! VEX V5 Brain hardware. It lets user programs control motors, read sensors,
//! display text on the LCD, access the SD card, and manage concurrent tasks
//! — all without calling raw C / PROS / RobotC APIs.
//!
//! ## Quick start
//!
//! The entry point for user code is the [`Init`] (sometimes called the
//! "Juicy Main"). It bundles a debug allocator, an arena allocator, a
//! [`V5Io`] instance (which implements `std.Io`), and a comptime-generated
//! [`Peripherals`] struct that holds typed device handles.
//!
//! ```zig
//! const velox = @import("velox_sdk");
//!
//! const MyDevices = struct {
//!     front_left: struct { .type = .motor },
//!     front_right: struct { .type = .motor },
//!     distance_sensor: struct { .type = .distance },
//! };
//!
//! pub fn main() void {
//!     var app = velox.Init(MyDevices){};
//!     app.devices.front_left.spinAt(100, .percent);
//! }
//! ```
//!
//! ## Concurrency
//!
//! The V5 Brain has no OS — concurrency is cooperative and managed through
//! the VEXos task scheduler. The [`V5Io`] type wraps this as a
//! `std.Io`, so standard-library-compatible async primitives (futex,
//! cancellation, clocks) work out of the box.
//!
//! ## Memory
//!
//! There is no heap allocator available on the V5. The SDK provides a
//! [`std.heap.DebugAllocator`] and an [`std.heap.ArenaAllocator`] through
//! [`Init`], backed by a fixed buffer. All task slots are a pre-allocated
//! pool of a fixed size (currently 16).

const std = @import("std");
const io = @import("./Io.zig");
const init = @import("Init.zig");

/// The "Juicy Main" init type — the entry point for all Velox user programs.
///
/// Returned from calling `velox_sdk.Init(MyDevices){}`. Contains the
/// allocator, I/O handle, and all device peripherals you declared at
/// compile time. The `MyDevices` type parameter is a struct whose fields
/// each declare a device kind (e.g. `.type = .motor`).
///
/// See the module-level documentation for a full example.
pub const Init = init.Init;

/// An abstraction over the V5 Brain's LCD display.
///
/// Provides simple line-based text output to the built-in LCD screen.
///
/// ```zig
/// velox_sdk.Display.printOnLine("Hello, VEX!", 0);
/// ```
pub const Display = @import("display.zig").Display;

/// A comptime-generic type that builds a struct of typed device handles
/// from a user-supplied configuration.
///
/// Each field in the config struct becomes a field in the resulting
/// [`Peripherals`] struct, with its type determined by the `.type` key
/// (e.g. `.motor`, `.distance`).
///
/// ```zig
/// const MyDevices = struct {
///     motor_left: struct { .type = .motor },
///     dist_front: struct { .type = .distance },
/// };
///
/// const Devices = velox_sdk.Peripherals(MyDevices);
/// ```
pub const Peripherals = @import("Peripherals.zig");

/// A `std.Io` implementation tailored for the VEX V5 Brain.
///
/// Supports console I/O over serial, a single SD-card file at a time,
/// cooperative concurrency via VEXos tasks, cancellation, monotonic clocks,
/// and a hardware-seeded PRNG.
///
/// An instance is provided inside [`Init`]. Use `app.io` to obtain the
/// `std.Io` interface.
///
/// ```zig
/// var stdout = app.io.stdout();
/// _ = try stdout.writeAll("booted\n");
/// ```
pub const V5Io = io.V5Io;

const motor = @import("devices/Motor.zig");
const distance = @import("devices/Distance.zig");
const adi = @import("devices/ADI.zig");
const bumper = @import("devices/Bumper.zig");
const rotational = @import("devices/Rotation.zig");
const inertial = @import("devices/Inertial.zig");

/// A VEX V5 Smart Motor (both 11 W and 5.5 W variants).
///
/// Supports setting speed in RPM, voltage, or percent; reading temperature,
/// encoder position, and efficiency; and configuring braking mode and
/// cartridge type.
///
/// ```zig
/// var motor = try velox_sdk.Motor.init(1, false, .green);
/// motor.spinAt(200, .rpm);
/// ```
pub const Motor = motor.Motor;

/// A VEX V5 Distance Sensor (276-4852).
///
/// Measures distance to the nearest detected object in mm, cm, inches, or
/// feet, and reports confidence, object size, and object velocity.
///
/// ```zig
/// var dist = try velox_sdk.Distance.init(5);
/// const cm: f32 = dist.distance(.centimeter);
/// ```
pub const Distance = distance.Distance;

/// A VEX ADI (Analog/Digital Interface) port on the 3-wire expander.
///
/// Configures a single ADI port as analog in/out or digital in/out, and
/// provides raw read/write access.
///
/// ```zig
/// var adi = velox_sdk.ADI.init(1, .digitalIn);
/// const val = adi.get();
/// ```
pub const ADI = adi.ADI;

/// A VEX bumper switch sensor, connected via an ADI digital input port.
///
/// Wraps an [`ADI`] in digital-input mode and exposes a simple
/// pressed/released state.
///
/// ```zig
/// var bumper = velox_sdk.Bumper.init(1);
/// if (bumper.state() == .pressed) { ... }
/// ```
pub const Bumper = bumper.Bumper;

/// A VEX V5 Rotation Sensor (absolute encoder).
///
/// Provides position, angle, velocity, and reset functionality with
/// support for multiple rotational units.
///
/// ```zig
/// var rot = velox_sdk.Rotation.init(3);
/// rot.reset();
/// const deg: i32 = rot.angle(.degree);
/// ```
pub const Rotation = rotational.Rotation;

/// A VEX V5 Inertial Sensor
///
/// Provides heading, acceleration, and rotation functionality.
///
/// ```zig
/// var imu = velox_sdk.Inertial.init(3);
/// const heading = imu.heading(.degree);
/// ```
pub const Inertial = inertial.Inertial;
