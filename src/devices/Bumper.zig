const jmptbl = @import("velox_jumptable");
const adi = @import("./ADI.zig");

pub const BumerState = enum(c_int) { pressed = 0, released };

pub const Bumper = struct {
    _adi: adi.ADI,

    pub fn init(port: u8) Bumper {
        const adiInstance = adi.ADI.init(port, adi.ADIKind.digitalIn);
        return Bumper{
            ._adi = adiInstance,
        };
    }

    pub fn state(self: *Bumper) BumerState {
        return self._adi.get();
    }
};
