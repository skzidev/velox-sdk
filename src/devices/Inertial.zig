const jmptbl = @import("velox_jumptable");
const units = @import("../units.zig");
const errors = @import("../error.zig");
const std = @import("std");
const pi = std.math.pi;

pub const Inertial = struct {
    _handle: ?*anyopaque,

    pub const InertialQuaternion = struct {
        x: f64,
        y: f64,
        z: f64,
        w: f64,
    };

    pub fn init(port: u32) Inertial {
        return Inertial{
            ._handle = jmptbl.devices.vexDeviceGetByIndex(port - 1),
        };
    }

    pub fn reset(self: *Inertial) void {
        jmptbl.imu.vexDeviceImuReset(self._handle);
    }

    pub fn quat(self: *Inertial, alloc: std.mem.Allocator) !InertialQuaternion {
        const quatPtr = try alloc.alloc(InertialQuaternion, 1);
        defer alloc.destroy(quatPtr);
        jmptbl.imu.vexDeviceImuQuaternionGet(self._handle, quatPtr);
        return quatPtr[0];
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
