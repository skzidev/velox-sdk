const jmptbl = @import("velox_jumptable");
const units = @import("../units.zig");
const pi = @import("std").math.pi;

pub const Rotation = struct {
    _handle: ?*anyopaque,

    pub fn init(
        port: u32,
    ) Rotation {
        return Rotation{
            ._handle = jmptbl.devices.vexDeviceGetByIndex(port - 1),
        };
    }

    pub fn reset(self: *Rotation) void {
        jmptbl.rotation.vexDeviceAbsEncReset(self._handle);
    }

    pub fn velocity(self: *Rotation) i32 {
        // TODO add units
        return jmptbl.rotation.vexDeviceAbsEncVelocityGet(self._handle);
    }

    pub fn isReversed(self: *Rotation) bool {
        return jmptbl.rotation.vexDeviceAbsEncReverseFlagGet(self._handle);
    }

    pub fn setReversed(self: *Rotation, reversed: bool) void {
        jmptbl.rotation.vexDeviceAbsEncReverseFlagSet(self._handle, reversed);
    }

    /// TODO add units
    pub fn pos(self: *Rotation) i32 {
        return jmptbl.rotation.vexDeviceAbsEncPositionGet(self._handle);
    }

    pub fn setPos(self: *Rotation, value: i32) void {
        jmptbl.rotation.vexDeviceAbsEncPositionSet(self._handle, value);
    }

    pub fn angle(self: *Rotation, unit: units.RotationalUnit) i32 {
        const deg = jmptbl.rotation.vexDeviceAbsEncAngleGet(self._handle);
        return switch (unit) {
            .radian => deg * (pi / 180),
            .degree => deg,
            .turn => deg / 360,
        };
    }

    pub fn setDataRate(self: *Rotation, rate: u32) void {
        return jmptbl.rotation.vexDeviceAbsEncDataRateSet(self._handle, rate);
    }
};
