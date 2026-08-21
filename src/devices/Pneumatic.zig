const adi = @import("ADI.zig");
const jmptbl = @import("velox_jumptable");

pub const Pneumatic = struct {
    _adi: adi.ADI,
    pub fn init(port: u8, expander: u32) Pneumatic {
        return .{
            ._adi = adi.ADI.init(port, .digitalOut, expander),
        };
    }

    pub fn extend(self: *Pneumatic) void {
        self._adi.set(true);
    }

    pub fn retract(self: *Pneumatic) void {
        self._adi.set(false);
    }

    pub fn toggle(self: *Pneumatic) void {
        self._adi.set(!self._adi.get());
    }

    pub fn set(self: *Pneumatic, v: bool) void {
        self._adi.set(v);
    }
};
