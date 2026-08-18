const jmptbl = @import("velox_jumptable");
const units = @import("../units.zig");
const errors = @import("../error.zig");

pub const Distance = struct {
    _handle: ?*anyopaque,
    pub fn init(
        port: u32,
    ) errors.DeviceInitError!Distance {
        if (port < -21 or port > 21 or port == 0)
            return errors.DeviceInitError.InvalidPortError;
        return Distance{ ._handle = jmptbl.devices.vexDeviceGetByIndex(port - 1) };
    }

    pub fn getDistance(self: *Distance, unit: units.LengthUnit) u32 {
        const mm = jmptbl.distance.vexDeviceDistanceDistanceGet(self._handle);
        return switch (unit) {
            // metric
            .millimeter => mm,
            .centimeter => mm / 10,
            // imperial
            .inch => mm / 25.4,
        };
    }
};
