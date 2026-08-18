//! # Velox SDK
//! This library allows Velox user code to interface with the VEX V5 hardware
//!

const std = @import("std");
const io = @import("./Io.zig");
const init = @import("Init.zig");

// Provides the juicy main Init type for Velox
pub const Init = init.Init;
/// Provides access to the display
pub const Display = @import("display.zig");
/// Peripheral management
pub const Peripherals = @import("Peripherals.zig");
/// Provides an IO interface which users can use.
/// An instance of this is provided in the Juicy Main.
pub const V5Io = io.V5Io;

const motor = @import("devices/Motor.zig");

pub const devices = struct {
    Motor: motor.Motor = motor.Motor,
};
