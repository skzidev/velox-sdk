const jmptbl = @import("velox_jumptable");
const units = @import("../units.zig");
const errors = @import("../error.zig");
const pi = @import("std").math.pi;

pub const Inertial = struct {
    _handle: ?*anyopaque,
    pub fn init(port: u32) Inertial {
        return Inertial{
            ._handle = jmptbl.devices.vexDeviceGetByIndex(port - 1),
        };
    }

    pub fn reset(self: *Inertial) void {
        jmptbl.imu.vexDeviceImuReset(self._handle);
    }

    pub fn heading(self: *Inertial, unit: units.RotationalUnit) f64 {
        const deg = jmptbl.imu.vexDeviceImuHeadingGet(self._handle);
        return switch (unit) {
            .degree => deg,
            .radian => deg * (pi / 180),
            .turn => deg / 360,
        };
    }
};
