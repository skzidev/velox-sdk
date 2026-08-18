const jmptbl = @import("velox_jumptable");
const units = @import("../units.zig");
const errors = @import("../error.zig");

/// An enum representing the possible, official VEX motor cartridges
pub const MotorCartridge = enum(c_int) {
    /// ## 36:1
    red = 0,
    /// ## 18:1
    green,
    /// ## 6:1
    blue,
    _,
};

/// An enum representing the V5 motor braking modes
pub const BrakeMode = enum(c_int) {
    // this MUST BE the same as in the jumptable
    /// ## Coast Mode
    /// Provide no active braking.
    ///
    /// The motor will be naturally slowed down by friction
    coast = 0,
    /// ## Brake Mode
    /// Provide active braking, but do not hold the motor in its place.
    ///
    brake,
    /// ## Hold mode
    /// Lock the motor in place where it is.
    ///
    hold,
    _,
};

/// Represents a VEX V5 Motor (Both 11w and 5.5w)
pub const Motor = struct {
    _handle: ?*anyopaque = null,
    /// Defines whether this motor is reversed or not
    /// This can be overrided at runtime.
    isReversed: bool = false,
    //// The motor cartridge that is inserted into the motor
    cartridge: MotorCartridge,
    /// Spins the motor at an specified number of specified units.
    ///
    /// The sign of `scalar` controls which direction it spins in. If it is positive, it spins forward, otherwise backward.
    ///
    /// **Return Value**: `void`
    ///
    /// For instance:
    /// ```zig
    /// robot.front_left_motor.spinAt(127, .volts);
    /// robot.front_left_motor.spinAt(120, .rpm);
    /// robot.front_left_motor.spinAt(75, .percent);
    /// ```
    pub fn spinAt(
        self: *Motor,
        /// The value at which the motor should spin.
        scalar: i32,
        /// The units which the value is in.
        unit: units.MotorUnit,
    ) void {
        scalar = if (self.isReversed) -scalar else scalar;
        switch (unit) {
            .rpm => {
                jmptbl.motor.vexDeviceMotorVelocitySet(self._handle, scalar);
            },
            .volts => {
                jmptbl.motor.vexDeviceMotorVoltageSet(self._handle, scalar);
            },
            .percent => {
                jmptbl.motor.vexDeviceMotorVoltageSet(self._handle, (scalar * 127) / 100);
            },
        }
    }

    pub fn init(
        /// The port # of the device
        port: i8,
        /// Whether the motor shold be reversed
        reversed: bool,
        /// The motor cartridge.
        cart: MotorCartridge,
    ) errors.DeviceInitError!Motor {
        if (port < -21 or port > 21 or port == 0)
            return errors.DeviceError.InvalidPortError;
        const handle = jmptbl.devices.vexDeviceGetByIndex(port - 1);
        return Motor{
            ._handle = handle,
            .isReversed = reversed,
            .cartridge = cart,
        };
    }

    /// Get the temperature of the motor in the specified units
    ///
    /// **Return Value**: The temperature in the specified units.
    pub fn temp(
        self: *Motor,
        /// The units in which the response should be returned
        unit: units.TempUnit,
    ) f64 {
        const cTemp = jmptbl.motor.vexDeviceMotorTemperatureGet(self._handle);
        return switch (unit) {
            .celsius => cTemp,
            .farenheit => (cTemp * (9 / 5)) + 32,
        };
    }

    /// Returns a boolean flag which tells if the motor is overheating
    pub fn isOverheating(self: *Motor) bool {
        return jmptbl.motor.vexDeviceMotorOverTempFlagGet(self._handle);
    }

    /// Sets the braking mode on the motor
    pub fn setBrakingMode(self: *Motor, mode: BrakeMode) void {
        jmptbl.motor.vexDeviceMotorBrakeModeSet(self._handle, mode);
    }
};
