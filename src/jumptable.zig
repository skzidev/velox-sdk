//! vex SDK function overrides
//! **this should not have to exist. I just wanted to ship faster and that means I'll have to fix this in the codegen script later.
//!
//! Basically, velox_jumptable declares [*c] ptrs to opaque types and returns opaque types by value even though this is illegal in Zig 0.16,
//! so I should instead use the ABI-equivalent form of "?*anyopaque", and additionall FatFs "FRESULT" should become c_int.
//!

pub const task = struct {
    /// Add a task that runs `callback` and receives `arg`. Returns the task
    /// id, or 0 on failure.
    pub extern const vexTaskAddWithArg: *const fn (callback: *const fn () callconv(.c) i32, interval: i32, arg: [*c]void, label: [*:0]const u8) callconv(.c) u32;

    /// Index of the currently running task.
    pub extern const vexTaskGetIndex: *const fn () callconv(.c) u32;

    /// Sleep the current task for `time` milliseconds.
    pub extern const vexTaskSleep: *const fn (time: u32) callconv(.c) void;

    /// Yield the current task to the scheduler.
    pub extern const vexTaskYield: *const fn () callconv(.c) void;
};

pub const serial = struct {
    /// Write `data_len` bytes from `data` to `channel`. Returns the number of
    /// bytes written, or -1 on error.
    pub extern const vexSerialWriteBuffer: *const fn (channel: u32, data: [*c]u8, data_len: u32) callconv(.c) i32;

    /// Read one byte from `channel`, or -1 if none is available.
    pub extern const vexSerialReadChar: *const fn (channel: u32) callconv(.c) i32;

    /// Return the next byte in `channel` without consuming it, or -1 if none.
    pub extern const vexSerialPeekChar: *const fn (channel: u32) callconv(.c) i32;

    /// Number of bytes of free transmit buffer space on `channel`, or -1.
    pub extern const vexSerialWriteFree: *const fn (channel: u32) callconv(.c) i32;
};

pub const file = struct {
    /// Mount the SD card. Returns a FatFs `FRESULT` (ignored here).
    pub extern const vexFileMountSD: *const fn () callconv(.c) c_int;

    /// Open `filename` with a FatFs mode string. Returns an opaque FIL handle,
    /// or null on failure.
    pub extern const vexFileOpen: *const fn (filename: [*:0]const u8, mode: [*:0]const u8) callconv(.c) ?*anyopaque;

    /// Close the file handle `fdp`.
    pub extern const vexFileClose: *const fn (fdp: ?*anyopaque) callconv(.c) void;

    /// Read `nItems` items of `size` bytes each into `buf`. Returns the number
    /// of items read, or -1 on error.
    pub extern const vexFileRead: *const fn (buf: [*c]u8, size: u32, nItems: u32, fdp: ?*anyopaque) callconv(.c) i32;

    /// Write `nItems` items of `size` bytes each from `buf`. Returns the number
    /// of items written, or -1 on error.
    pub extern const vexFileWrite: *const fn (buf: [*c]u8, size: u32, nItems: u32, fdp: ?*anyopaque) callconv(.c) i32;

    /// Size of the open file in bytes, or a negative value on error.
    pub extern const vexFileSize: *const fn (fdp: ?*anyopaque) callconv(.c) i32;

    /// Seek `fdp` to `offset` using FatFs `whence` (0 = SEEK_SET). Returns a
    /// FatFs `FRESULT` (ignored here).
    pub extern const vexFileSeek: *const fn (fdp: ?*anyopaque, offset: u32, whence: i32) callconv(.c) c_int;

    /// Current read/write position of `fdp`, or a negative value on error.
    pub extern const vexFileTell: *const fn (fdp: ?*anyopaque) callconv(.c) i32;

    /// Flush buffered data of `fdp` to the SD card.
    pub extern const vexFileSync: *const fn (fdp: ?*anyopaque) callconv(.c) void;
};

pub const system = struct {
    /// Milliseconds since power on.
    pub extern const vexSystemTimeGet: *const fn () callconv(.c) u32;

    /// Microseconds since power on.
    pub extern const vexSystemHighResTimeGet: *const fn () callconv(.c) u64;

    /// Microseconds since the user program started.
    pub extern const vexSystemPowerupTimeGet: *const fn () callconv(.c) u64;
};
