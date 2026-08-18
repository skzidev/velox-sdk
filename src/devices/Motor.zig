const jmptbl = @import("velox_jumptable");
const units = @import("../units.zig");

/// Represents a VEX V5 Motor (Both 11w and 5.5w)
pub const Motor = struct {
    const _handle: ?*anyopaque = null;
    /// Defines whether this motor is reversed or not
    /// This can be overrided at runtime.
    pub var isReversed: bool = false;
    /// Spins the motor at an specified number of specified units.
    ///
    /// **Parameters**:
    /// - `scalar` (i32): _The value at which the motor should spin._
    /// - `unit` (MotorUnit): _The units which the value is in._
    ///
    /// The sign of `scalar` controls which direction it spins in. If it is positive, it spins forward, otherwise backward.
    ///
    /// **Return Value**: `void`
    ///
    /// For instance:
    /// ```zig
    /// robot.front_left_motor.spinAt(127, .volts);
    /// robot.front_left_motor.spinAt(100, .rpm);
    /// ```
    pub fn spinAt(self: *Motor, scalar: i32, unit: units.MotorUnit) void {
        if (isReversed) scalar *= -1;
        switch (unit) {
            .rpm => {
                jmptbl.motor.vexDeviceMotorVelocitySet(self._handle, scalar);
            },
            .volts => {
                jmptbl.motor.vexDeviceMotorVoltageSet(self._handle, scalar);
            },
        }
    }
};
