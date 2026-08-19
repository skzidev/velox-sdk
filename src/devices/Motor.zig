const jmptbl = @import("velox_jumptable");
const units = @import("../units.zig");
const errors = @import("../error.zig");
const pi = @import("std").math.pi;

/// An enum representing the supported VEX motor cartridges
pub const MotorCartridge = enum(c_int) {
    /// ## 36:1 _(100rpm)_
    /// V5 Red Cartridge (276-5840)
    red = 0,
    /// ## 18:1 _(200rpm)_
    /// V5 Green Cartridge (276-5841)
    green,
    /// ## 6:1 _(600rpm)_
    /// V5 Blue Cartridge (276-5842)
    blue,
    _,
};

pub const MotorKind = enum(c_int) {
    full = 0,
    half,
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
    /// Lock the motor in its current position.
    ///
    hold,
    _,
};

/// # V5 Smart Motor (11w AND 5.5w)
///
/// Represents Motors:
/// - 5.5W Smart Motor (276-4842)
/// - 11W Smart Motor (276-4840)
///
pub const Motor = struct {
    _handle: ?*anyopaque,
    /// Defines whether this motor is reversed or not
    /// This can be overrided at runtime.
    isReversed: bool,
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
        const speed = if (self.isReversed) -scalar else scalar;
        switch (unit) {
            .rpm => {
                jmptbl.motor.vexDeviceMotorVelocitySet(self._handle, speed);
            },
            .volts => {
                jmptbl.motor.vexDeviceMotorVoltageSet(self._handle, speed);
            },
            .percent => {
                jmptbl.motor.vexDeviceMotorVoltageSet(self._handle, @divTrunc((speed * 127), 100));
            },
        }
    }

    pub fn init(
        /// The port # of the device
        port: u32,
        /// Whether the motor shold be reversed
        reversed: bool,
        /// The motor cartridge.
        cart: MotorCartridge,
    ) errors.DeviceInitError!Motor {
        if (!errors.portIsValid(port))
            return errors.DeviceInitError.InvalidPortError;
        const handle = jmptbl.devices.vexDeviceGetByIndex(port - 1);
        // set default units
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
            .fahrenheit => (cTemp * (9 / 5)) + 32,
        };
    }

    /// Returns a boolean flag which tells if the motor is overheating
    ///
    /// **Return value**: A booelan representing whether the motor has overheated (and is therefore throttling) or not.
    pub fn isOverheating(self: *Motor) bool {
        return jmptbl.motor.vexDeviceMotorOverTempFlagGet(self._handle);
    }

    /// Sets the braking mode on the motor
    pub fn setBrakingMode(self: *Motor, mode: BrakeMode) void {
        jmptbl.motor.vexDeviceMotorBrakeModeSet(self._handle, mode);
    }

    /// Gets the position reported by the motor enocder in the specified units
    pub fn pos(self: *Motor, unit: units.RotationalUnit) f64 {
        if (unit == .degree or unit == .radian) {
            jmptbl.motor.vexDeviceMotorEncoderUnitsSet(self._handle, .kMotorEncoderDegrees);
        } else {
            jmptbl.motor.vexDeviceMotorEncoderUnitsSet(self._handle, .kMotorEncoderRotations);
        }
        var v = jmptbl.motor.vexDeviceMotorPositionGet(self._handle);
        if (unit == .radian) {
            v *= (180 / pi);
        }
        return v;
    }

    pub fn kind(self: *Motor) MotorKind {
        return jmptbl.motor.vexDeviceMotorTypeGet(self._handle);
    }

    pub fn efficiency(self: *Motor) f64 {
        return jmptbl.motor.vexDeviceMotorEfficiencyGet(self._handle);
    }

    pub fn setPos(self: *Motor, value: f64, unit: units.RotationalUnit) void {
        var v = value;
        if (unit == .degree or unit == .radian) {
            jmptbl.motor.vexDeviceMotorEncoderUnitsSet(self._handle, .kMotorEncoderDegrees);
            if (unit == .radian)
                v *= (pi / 180);
        } else {
            jmptbl.motor.vexDeviceMotorEncoderUnitsSet(self._handle, .kMotorEncoderRotations);
        }
        jmptbl.motor.vexDeviceMotorPositionSet(self._handle, v);
    }
};
