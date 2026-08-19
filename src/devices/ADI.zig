const jmptbl = @import("velox_jumptable");

pub const ADIKind = enum(c_int) {
    anlogIn = 0,
    analogOut,
    digitalIn,
    digitalOut,
    unknown = 255,
};

pub const ADI = struct {
    _expander: ?*anyopaque,
    _port: u32,
    _kind: ADIKind,

    pub fn init(
        port: u8,
        kind: ADIKind,
    ) ADI {
        // TODO add support for using ADI expanders
        // This just means that the user can pass this port in if they would like
        const expander = jmptbl.devices.vexDeviceGetByIndex(22);
        jmptbl.adi.vexDeviceAdiPortConfigSet(expander, port, kind);
        return ADI{
            ._expander = expander,
            ._port = port,
            ._kind = kind,
        };
    }

    pub fn get(self: *ADI) u32 {
        return jmptbl.adi.vexDeviceAdiValueGet(self._expander, self._port);
    }

    pub fn set(self: *ADI, value: i32) void {
        jmptbl.adi.vexDeviceAdiValueSet(self._expander, self._port, value);
    }
};
