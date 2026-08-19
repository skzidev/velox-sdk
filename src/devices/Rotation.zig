const jmptbl = @import("velox_jumptable");

pub const Rotation = struct {
    _handle: ?*anyopaque,

    pub fn init(
        port: u32,
    ) Rotation {
        return Rotation{
            ._handle = jmptbl.devices.vexDeviceGetByIndex(port - 1),
        };
    }

    /// TODO add units
    pub fn pos(self: *Rotation) i32 {
        return jmptbl.rotation.vexDeviceAbsEncPositionGet(self._handle);
    }
};
