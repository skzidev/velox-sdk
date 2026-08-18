const jmptbl = @import("velox_jumptable");
const units = @import("../units.zig");

pub const cartridges = enum {
    red,
    blue,
    green,
};

/// Represents a VEX V5 Motor (Both 11w and 5.5w)
pub const Motor = struct {
    const _handle: ?*anyopaque = null;
    /// Defines whether this motor is reversed or not
    /// This can be overrided at runtime.
    pub var isReversed: bool = false;
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
        if (isReversed) scalar *= -1;
        switch (unit) {
            .rpm => {
                jmptbl.motor.vexDeviceMotorVelocitySet(self._handle, scalar);
            },
            .volts => {
                jmptbl.motor.vexDeviceMotorVoltageSet(self._handle, scalar);
            },
            .percent => {
                jmptbl.motor.vexDeviceMotorVoltageSet(self._handle, (scalar / 100) * 127);
            },
        }
    }

    /// Get the temperature of the motor in the specified units
    ///
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
};
