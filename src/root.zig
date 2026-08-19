//! # Velox SDK
//! This library allows Velox user code to interface with the VEX V5 hardware
//!

const std = @import("std");
const io = @import("./Io.zig");
const init = @import("Init.zig");

// Provides the juicy main Init type for Velox
pub const Init = init.Init;
/// Provides access to the display
pub const Display = @import("display.zig").Display;
/// Peripheral management
pub const Peripherals = @import("Peripherals.zig");
/// Provides an IO interface which users can use.
/// An instance of this is provided in the Juicy Main.
pub const V5Io = io.V5Io;

const motor = @import("devices/Motor.zig");
const distance = @import("devices/Distance.zig");
const adi = @import("devices/ADI.zig");
const bumper = @import("devices/Bumper.zig");
const rotational = @import("devices/Rotation.zig");
const interial = @import("devices/Inertial.zig");

pub const Motor = motor.Motor;
pub const Distance = distance.Distance;
pub const ADI = adi.ADI;
pub const Bumper = bumper.Bumper;
pub const Rotation = rotational.Rotation;
