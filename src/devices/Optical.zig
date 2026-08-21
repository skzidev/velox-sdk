const jmptbl = @import("velox_jumptable");
const errors = @import("../error.zig");

pub const Optical = struct {
    _handle: ?*anyopaque,

    pub fn init(port: u32) errors.DeviceInitError!Optical {
        if (!errors.portIsValid(port))
            return errors.DeviceInitError.InvalidPortError;
        return .{ ._handle = jmptbl.devices.vexDeviceGetByIndex(port) };
    }

    // TODO implement optical sensor defs
};
