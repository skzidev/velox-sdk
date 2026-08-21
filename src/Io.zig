//! a [`std.Io`] implementation for the VEX V5 Brain.
//!
//! it supports:
//! * Console I/O (`stdout`, `stderr`, `stdin`) over serial channel 1.
//! * A single SD-card file at a time, opened with `File.open`, since the
//!   VEXos jumptable only exposes one open `FIL` handle through this
//!   interface. Opening a second file fails with `error.DeviceBusy`.
//! * Concurrency through VEXos tasks (`vexTaskAddWithArg`), using a fixed
//!   pool of task slots (there is no heap available on the V5).
//! * Cooperative cancelation: cancelation is requested with `Future.cancel`
//!   and observed by the task at its next cancelation point (any `Io` call
//!   that may return `error.Canceled`). Tasks are never forcibly stopped.
//! * The `.awake`/`.boot` clocks, derived from `vexSystemHighResTimeGet`
//!   which has microsecond resolution. `.real` and CPU clocks are
//!   unsupported.
//! * `random`, using a shared xoshiro256** generator seeded from hardware
//!   timers at first use. `randomSecure` reports `error.EntropyUnavailable`
//!   since the jumptable exposes no secure entropy source.
//!
//! Everything is is stubbed to std.Io.failing*.

const std = @import("std");
const jmptbl = @import("velox_jumptable");

/// The serial channel used for console I/O
const serial_channel: u32 = 1;

/// The number of concurrently running tasks in the fixed task slot pool.
const task_slots_count = 16;
/// The alignment of the per-task context and result buffers.
const task_buffer_alignment = 16;
/// The maximum size of a function argument tuple copied into a task slot.
const task_context_buffer_size = 64;
/// The maximum size in bytes of a task result.
const task_result_buffer_size = 128;
/// Cancelation is only checked between sleeps of this many milliseconds.
const sleep_chunk_ms: u32 = 5;

/// The opaque handle returned by `vexFileOpen` and accepted by the other
/// `vexFile*` functions.
const FilPtr = ?*anyopaque;

/// Per-task cancelation state.
///
/// `canceled` is a pending, not-yet-acknowledged cancelation request. A
/// cancelation point (`checkCancel`) acknowledges the request by clearing it
/// and returning `error.Canceled`, so that only the next cancelation point
/// reports it, matching the standard library contract. `recancel` re-arms the
/// request afterwards.
const CancelState = struct {
    canceled: std.atomic.Value(bool) = .init(false),
    // CancelProtection is `enum(u1)`, which is not extern-compatible, so it is
    // stored as a bool: `false` == `.unblocked`, `true` == `.blocked`.
    cancel_protection: std.atomic.Value(bool) = .init(false),
};

/// A task slot: the fixed memory backing one concurrent task.
const TaskSlot = struct {
    /// The user function to call. Receives the copied context and the slot's
    /// result buffer.
    start: *const fn (context: *const anyopaque, result: *anyopaque) void = undefined,
    context_buffer: [task_context_buffer_size]u8 align(task_buffer_alignment) = undefined,
    context_len: usize = 0,
    result_buffer: [task_result_buffer_size]u8 align(task_buffer_alignment) = undefined,
    result_len: usize = 0,
    /// Set to `true` by the task immediately before it returns, with release
    /// semantics. Read with acquire semantics by `await`/`cancel`.
    done: std.atomic.Value(bool) = .init(false),
    in_use: std.atomic.Value(bool) = .init(false),
    cancel_state: CancelState = .{},
    /// The VEXos task index (`vexTaskGetIndex`) of the running task, used to
    /// look up the slot from a cancelation point.
    task_index: u32 = 0,
};

/// The fixed pool of task slots.
var task_slots: [task_slots_count]TaskSlot = @splat(.{});

/// The cancel state for any task not spawned through `concurrent`, e.g. the
/// program's main task.
var main_task_state: CancelState = .{};

/// A shared pseudo random number generator, seeded at first use from hardware
/// timers. Protected by a spinlock so that the two V5 cores can share it.
var prng_lock: std.atomic.Value(bool) = .init(false);
var prng_seeded: bool = false;
var prng: std.Random.DefaultPrng = .init(0);

/// Returns the cancel state belonging to the currently executing task.
fn currentCancelState() *CancelState {
    const index = jmptbl.task.vexTaskGetIndex();
    for (&task_slots) |*slot| {
        if (slot.in_use.load(.acquire) and slot.task_index == index) {
            return &slot.cancel_state;
        }
    }
    return &main_task_state;
}

/// A pure cancelation point for `state`: returns `error.Canceled` if there is
/// an outstanding cancelation request and cancel protection is unblocked.
fn checkCancelState(state: *CancelState) std.Io.Cancelable!void {
    if (state.cancel_protection.load(.acquire)) return;
    if (state.canceled.swap(false, .acq_rel)) return error.Canceled;
}

/// The current time in nanoseconds, from `vexSystemHighResTimeGet`
/// (microsecond resolution, monotonic).
fn nowNs() i96 {
    return @as(i96, @intCast(jmptbl.system.vexSystemHighResTimeGet())) * std.time.ns_per_us;
}

/// Whether `file` is one of the console streams. SD files are marked
/// non-blocking by `File.open`; the console streams are not.
fn isConsole(file: std.Io.File) bool {
    return !file.flags.nonblocking;
}

/// Claims a free task slot, or returns `null` if the pool is exhausted.
fn acquireSlot() ?*TaskSlot {
    for (&task_slots) |*slot| {
        if (slot.in_use.cmpxchgWeak(false, true, .acq_rel, .acquire) == null) {
            return slot;
        }
    }
    return null;
}

/// Returns a task slot to the pool. The task must have already set `done`.
fn releaseSlot(slot: *TaskSlot) void {
    slot.in_use.store(false, .release);
}

/// The entry point VEXos calls for every task spawned by `concurrent`. The
/// task argument (`arg`) is a `*TaskSlot`. Runs the user's `start` function
/// with the slot's copied context and result buffer, then publishes `done`.
fn taskEntry(arg: [*c]void) callconv(.c) i32 {
    const slot: *TaskSlot = @ptrCast(@alignCast(arg));
    slot.task_index = jmptbl.task.vexTaskGetIndex();
    const context: *const anyopaque = @ptrCast(&slot.context_buffer);
    const result: *anyopaque = @ptrCast(&slot.result_buffer);
    slot.start(context, result);
    slot.done.store(true, .release);
    return 0;
}

/// Constructs one of the console file descriptors.
fn consoleFile(kind: enum { stdout, stderr, stdin }) std.Io.File {
    const handle: std.posix.fd_t = if (std.posix.fd_t != void)
        switch (kind) {
            .stdout => std.posix.STDOUT_FILENO,
            .stderr => std.posix.STDERR_FILENO,
            .stdin => std.posix.STDIN_FILENO,
        }
    else {};
    return .{
        .handle = handle,
        .flags = .{ .nonblocking = false },
    };
}

fn makeStat(size: u64) std.Io.File.Stat {
    const inode: std.posix.ino_t = if (std.posix.ino_t != void) 0 else {};
    const nlink: std.posix.nlink_t = if (std.posix.nlink_t != u0) 0 else 0;
    return .{
        .inode = inode,
        .nlink = nlink,
        .size = size,
        .permissions = .default_file,
        .kind = .file,
        .atime = null,
        .mtime = .zero,
        .ctime = .zero,
        .block_size = 1,
    };
}

/// VEXos drains the console ring buffer to USB roughly every millisecond,
/// when the scheduler runs. Sleeping lets the scheduler flush; once the free
/// space stops growing the buffer is empty.
fn serialFlush() void {
    var prev_free: i32 = -1;
    var stable_samples: u32 = 0;
    while (stable_samples < 2) {
        jmptbl.task.vexTaskSleep(1);
        const free = jmptbl.serial.vexSerialWriteFree(serial_channel);
        if (free == prev_free) {
            stable_samples += 1;
        } else {
            stable_samples = 0;
        }
        prev_free = free;
    }
}

/// Writes `data` to the serial console, waiting for free space in the UART
/// ring buffer as needed, then drains the ring buffer. Returns the number of
/// bytes written.
fn serialWriteAll(data: []const u8) error{InputOutput}!usize {
    var written: usize = 0;
    while (written < data.len) {
        while (jmptbl.serial.vexSerialWriteFree(serial_channel) <= 0) {
            jmptbl.task.vexTaskYield();
        }
        const n = jmptbl.serial.vexSerialWriteBuffer(
            serial_channel,
            @ptrCast(@constCast(data.ptr + written)),
            @intCast(data.len - written),
        );
        if (n < 0) return error.InputOutput;
        if (n == 0) return written;
        written += @intCast(n);
    }
    serialFlush();
    return written;
}

/// Writes `data` to the SD file. Returns the number of bytes written.
fn fileWriteAll(fil: FilPtr, data: []const u8) error{ InputOutput, NoSpaceLeft }!usize {
    var written: usize = 0;
    while (written < data.len) {
        const n = jmptbl.file.vexFileWrite(
            @ptrCast(@constCast(data.ptr + written)),
            1,
            @intCast(data.len - written),
            fil,
        );
        if (n < 0) return error.InputOutput;
        if (n == 0) return error.NoSpaceLeft;
        written += @intCast(n);
    }
    return written;
}

/// Implements `Operation.file_read_streaming`. For console streams, blocks
/// until data is available (checking cancelation). For SD files, reads
/// sequentially, stopping at end of file.
fn fileReadStreaming(
    self: *V5Io,
    file: std.Io.File,
    data: []const []u8,
) (std.Io.Operation.FileReadStreaming.Error || std.Io.Cancelable)!usize {
    var total: usize = 0;
    if (isConsole(file)) {
        for (data) |buf| {
            for (buf) |*byte| {
                while (jmptbl.serial.vexSerialPeekChar(serial_channel) < 0) {
                    try checkCancelState(currentCancelState());
                    jmptbl.task.vexTaskSleep(1);
                }
                byte.* = @intCast(@as(u8, @intCast(jmptbl.serial.vexSerialReadChar(serial_channel))));
                total += 1;
            }
        }
        return total;
    }
    const fil = self.sd_file orelse return error.NotOpenForReading;
    for (data) |buf| {
        if (buf.len == 0) continue;
        const n = jmptbl.file.vexFileRead(buf.ptr, 1, @intCast(buf.len), fil);
        if (n < 0) return error.InputOutput;
        if (n == 0) break;
        total += @intCast(n);
        if (@as(u32, @intCast(n)) < buf.len) break;
    }
    return total;
}

/// Implements `Operation.file_write_streaming`. `header` is the buffered
/// bytes, `data` the remaining slices whose last element is repeated `splat`
/// times. Writes everything and returns the number of bytes consumed from
/// `data` (the header is not counted).
fn fileWriteStreaming(
    self: *V5Io,
    file: std.Io.File,
    header: []const u8,
    data: []const []const u8,
    splat: usize,
) (std.Io.Operation.FileWriteStreaming.Error || std.Io.Cancelable)!usize {
    try checkCancelState(currentCancelState());
    if (data.len <= 0) return std.Io.Operation.FileWriteStreaming.Error.Unexpected;
    if (isConsole(file)) {
        var written: usize = 0;
        written += try serialWriteAll(header);
        for (data[0 .. data.len - 1]) |bytes| written += try serialWriteAll(bytes);
        const pattern = data[data.len - 1];
        for (0..splat) |_| written += try serialWriteAll(pattern);
        return written;
    }
    const fil = self.sd_file orelse return error.NotOpenForWriting;
    var written: usize = 0;
    written += try fileWriteAll(fil, header);
    for (data[0 .. data.len - 1]) |bytes| written += try fileWriteAll(fil, bytes);
    const pattern = data[data.len - 1];
    for (0..splat) |_| written += try fileWriteAll(fil, pattern);
    return written;
}

/// Performs a single `Operation` synchronously, returning its result.
fn performOperation(self: *V5Io, operation: std.Io.Operation) std.Io.Operation.Result {
    return switch (operation) {
        .file_read_streaming => |op| .{
            .file_read_streaming = fileReadStreaming(self, op.file, op.data) catch |err| switch (err) {
                error.Canceled => unreachable,
                else => |e| e,
            },
        },
        .file_write_streaming => |op| .{
            .file_write_streaming = fileWriteStreaming(self, op.file, op.header, op.data, op.splat) catch |err| switch (err) {
                error.Canceled => unreachable,
                else => |e| e,
            },
        },
        .device_io_control => .{ .device_io_control = -1 },
        .net_receive => .{ .net_receive = .{ error.NetworkDown, 0 } },
    };
}

/// The synchronous fallback used by both batch await functions: every
/// submitted operation is performed immediately and moved to the completed
/// list. This mirrors `Threaded.batchAwaitAsync`.
fn batchAwaitFallback(self: *V5Io, b: *std.Io.Batch) void {
    var tail_index = b.completed.tail;
    defer b.completed.tail = tail_index;
    var index = b.submitted.head;
    while (index != .none) {
        const storage = &b.storage[index.toIndex()];
        const submission = &storage.submission;
        const next_index = submission.node.next;
        const result = performOperation(self, submission.operation);

        switch (tail_index) {
            .none => b.completed.head = index,
            else => b.storage[tail_index.toIndex()].completion.node.next = index,
        }
        storage.* = .{ .completion = .{ .node = .{ .next = .none }, .result = result } };
        tail_index = index;
        index = next_index;
    }
    b.submitted = .{ .head = .none, .tail = .none };
}

/// A [`std.Io`] implementation for the VEX V5 Brain.
///
/// This type adapts the VEXos firmware jumptable to Zig's standard I/O
/// interface. It provides:
///
/// - **Console I/O** — `stdout`, `stderr`, and `stdin` over serial channel 1.
///   `stdout` and `stderr` are the same underlying stream.
/// - **SD-card file I/O** — a single file handle at a time, opened via
///   [`File.open`]. The VEXos jumptable only exposes one `FIL` handle, so
///   attempting to open a second file returns `error.DeviceBusy`.
/// - **Cooperative concurrency** — tasks are spawned through VEXos
///   (`vexTaskAddWithArg`) using a fixed pool of 16 task slots. There is no
///   heap on the V5, so all slots are statically allocated.
/// - **Cancellation** — cooperative: a cancel request is observed at the next
///   cancellation point (any I/O call that may return `error.Canceled`).
///   Tasks are never forcibly stopped.
/// - **Clocks** — `.awake` and `.boot` clocks, derived from
///   `vexSystemHighResTimeGet` with microsecond resolution. The `.real` and
///   CPU clocks are unsupported and return the epoch.
/// - **PRNG** — a shared `xoshiro256**` generator, seeded from hardware
///   timers on first use. `randomSecure` returns
///   `error.EntropyUnavailable`.
///
/// Everything else is stubbed to `std.Io.failing*` (directories, networking,
/// processes, memory maps, etc.).
///
/// ## Example
///
/// ```zig
/// var app = velox_sdk.Init(MyDevices){};
///
/// // Console output
/// var stdout = app.io.stdout();
/// _ = try stdout.writeAll("hello from V5\n");
///
/// // SD-card file
/// var file = try velox_sdk.V5Io.File.open(&app.io, "log.txt", .{});
/// defer velox_sdk.V5Io.File.close(&app.io);
/// _ = try file.writeAll("data\n");
/// ```
pub const V5Io = struct {
    /// Whether the SD card has been mounted with `vexFileMountSD`.
    sd_mounted: bool = false,
    /// The currently open SD file, if any. The jumptable exposes one `FIL`
    /// handle at a time.
    sd_file: FilPtr = null,

    /// Provides access to console streams and SD-card file operations.
    ///
    /// The V5 Brain exposes a single serial console (channel 1) that serves
    /// as `stdout`, `stderr`, and `stdin`. For SD-card files, only one file
    /// handle may be open at a time.
    pub const File = struct {
        /// Returns the console output stream.
        ///
        /// On the V5, `stdout` and `stderr` are the same serial channel.
        /// Data written here is drained to USB by VEXos roughly every
        /// millisecond.
        ///
        /// ```zig
        /// var stdout = velox_sdk.V5Io.File.stdout();
        /// _ = try stdout.writeAll("booting...\n");
        /// ```
        pub fn stdout() std.Io.File {
            return consoleFile(.stdout);
        }

        /// Returns the console error stream.
        ///
        /// This is an alias for [`stdout`] — the V5 has a single serial
        /// console channel shared by both.
        pub fn stderr() std.Io.File {
            return consoleFile(.stderr);
        }

        /// Returns the console input stream.
        ///
        /// Reads from this stream block until data is available over the
        /// serial connection (e.g. from a VEXcode terminal over USB).
        ///
        /// ```zig
        /// var stdin = velox_sdk.V5Io.File.stdin();
        /// var buf: [128]u8 = undefined;
        /// const n = try stdin.read(&buf);
        /// ```
        pub fn stdin() std.Io.File {
            return consoleFile(.stdin);
        }

        /// Opens a file on the SD card.
        ///
        /// The SD card is mounted automatically on first use. Only one file
        /// may be open at a time — calling this while a file is already open
        /// returns `error.DeviceBusy`.
        ///
        /// The returned `std.Io.File` handle is suitable for use with any
        /// `std.Io` file operation (read, write, seek, stat, etc.).
        ///
        /// ```zig
        /// const file = try velox_sdk.V5Io.File.open(
        ///     &app.io,
        ///     "data/log.txt",
        ///     .{ .mode = .read_write },
        /// );
        /// defer velox_sdk.V5Io.File.close(&app.io);
        /// ```
        ///
        /// **Errors:**
        /// - `error.DeviceBusy` — a file is already open.
        /// - `error.FileNotFound` — the file does not exist (for read modes).
        /// - `error.NameTooLong` — path exceeds 255 bytes.
        pub fn open(self: *V5Io, path: []const u8, options: std.Io.Dir.OpenFileOptions) std.Io.File.OpenError!std.Io.File {
            if (self.sd_file != null) return error.DeviceBusy;

            var path_buf: [256]u8 = undefined;
            if (path.len >= path_buf.len) return error.NameTooLong;
            @memcpy(path_buf[0..path.len], path);
            path_buf[path.len] = 0;

            if (!self.sd_mounted) {
                _ = jmptbl.file.vexFileMountSD();
                self.sd_mounted = true;
            }

            const mode: [*:0]const u8 = switch (options.mode) {
                .read_only => "r",
                .write_only => "w",
                .read_write => "r+",
            };
            const fil = jmptbl.file.vexFileOpen(@ptrCast(&path_buf), mode) orelse return error.FileNotFound;
            self.sd_file = fil;
            return .{
                .handle = {},
                .flags = .{ .nonblocking = true },
            };
        }

        /// Closes the currently open SD-card file, if any.
        ///
        /// After calling this, the file handle stored internally is cleared,
        /// allowing a subsequent call to [`open`] to succeed.
        ///
        /// This is a no-op if no file is currently open.
        pub fn close(self: *V5Io) void {
            if (self.sd_file) |fil| {
                jmptbl.file.vexFileClose(fil);
                self.sd_file = null;
            }
        }
    };

    /// Creates a new `V5Io` instance with default state (no SD file open).
    ///
    /// ```zig
    /// var v5io = velox_sdk.V5Io.init();
    /// ```
    pub fn init() V5Io {
        return .{};
    }

    /// Returns a `std.Io` interface backed by this `V5Io` instance.
    ///
    /// The returned value can be passed to any function that accepts
    /// `std.Io`, including the Zig standard library's async I/O facilities.
    ///
    /// ```zig
    /// var v5io = velox_sdk.V5Io.init();
    /// const stdio = v5io.io();
    /// var stdout = stdio.stdout();
    /// _ = try stdout.writeAll("hello\n");
    /// ```
    pub fn io(self: *V5Io) std.Io {
        return .{
            .userdata = self,
            .vtable = &vtableImpl,
        };
    }

    const vtableImpl: std.Io.VTable = .{
        .crashHandler = crashHandler,

        .async = std.Io.noAsync,
        .concurrent = concurrent,
        .await = awaitFuture,
        .cancel = cancelFuture,

        .groupAsync = std.Io.noGroupAsync,
        .groupConcurrent = groupConcurrent,
        .groupAwait = std.Io.unreachableGroupAwait,
        .groupCancel = std.Io.unreachableGroupCancel,

        .recancel = recancel,
        .swapCancelProtection = swapCancelProtection,
        .checkCancel = checkCancel,

        .futexWait = futexWait,
        .futexWaitUncancelable = futexWaitUncancelable,
        .futexWake = std.Io.noFutexWake,

        .operate = operate,
        .batchAwaitAsync = batchAwaitAsync,
        .batchAwaitConcurrent = batchAwaitConcurrent,
        .batchCancel = batchCancel,

        .dirCreateDir = std.Io.failingDirCreateDir,
        .dirCreateDirPath = std.Io.failingDirCreateDirPath,
        .dirCreateDirPathOpen = std.Io.failingDirCreateDirPathOpen,
        .dirOpenDir = std.Io.failingDirOpenDir,
        .dirStat = std.Io.failingDirStat,
        .dirStatFile = std.Io.failingDirStatFile,
        .dirAccess = std.Io.failingDirAccess,
        .dirCreateFile = std.Io.failingDirCreateFile,
        .dirCreateFileAtomic = std.Io.failingDirCreateFileAtomic,
        .dirOpenFile = std.Io.failingDirOpenFile,
        .dirClose = std.Io.unreachableDirClose,
        .dirRead = std.Io.noDirRead,
        .dirRealPath = std.Io.failingDirRealPath,
        .dirRealPathFile = std.Io.failingDirRealPathFile,
        .dirDeleteFile = std.Io.failingDirDeleteFile,
        .dirDeleteDir = std.Io.failingDirDeleteDir,
        .dirRename = std.Io.failingDirRename,
        .dirRenamePreserve = std.Io.failingDirRenamePreserve,
        .dirSymLink = std.Io.failingDirSymLink,
        .dirReadLink = std.Io.failingDirReadLink,
        .dirSetOwner = std.Io.failingDirSetOwner,
        .dirSetFileOwner = std.Io.failingDirSetFileOwner,
        .dirSetPermissions = std.Io.failingDirSetPermissions,
        .dirSetFilePermissions = std.Io.failingDirSetFilePermissions,
        .dirSetTimestamps = std.Io.noDirSetTimestamps,
        .dirHardLink = std.Io.failingDirHardLink,

        .fileStat = fileStat,
        .fileLength = fileLength,
        .fileClose = fileClose,
        .fileWritePositional = fileWritePositional,
        .fileWriteFileStreaming = std.Io.noFileWriteFileStreaming,
        .fileWriteFilePositional = std.Io.noFileWriteFilePositional,
        .fileReadPositional = fileReadPositional,
        .fileSeekBy = fileSeekBy,
        .fileSeekTo = fileSeekTo,
        .fileSync = fileSync,
        .fileIsTty = fileIsTty,
        .fileEnableAnsiEscapeCodes = fileEnableAnsiEscapeCodes,
        .fileSupportsAnsiEscapeCodes = fileSupportsAnsiEscapeCodes,
        .fileSetLength = fileSetLength,
        .fileSetOwner = std.Io.failingFileSetOwner,
        .fileSetPermissions = std.Io.failingFileSetPermissions,
        .fileSetTimestamps = std.Io.noFileSetTimestamps,
        .fileLock = std.Io.failingFileLock,
        .fileTryLock = std.Io.failingFileTryLock,
        .fileUnlock = std.Io.unreachableFileUnlock,
        .fileDowngradeLock = std.Io.failingFileDowngradeLock,
        .fileRealPath = std.Io.failingFileRealPath,
        .fileHardLink = std.Io.failingFileHardLink,

        .fileMemoryMapCreate = std.Io.failingFileMemoryMapCreate,
        .fileMemoryMapDestroy = std.Io.unreachableFileMemoryMapDestroy,
        .fileMemoryMapSetLength = std.Io.unreachableFileMemoryMapSetLength,
        .fileMemoryMapRead = std.Io.unreachableFileMemoryMapRead,
        .fileMemoryMapWrite = std.Io.unreachableFileMemoryMapWrite,

        .processExecutableOpen = std.Io.failingProcessExecutableOpen,
        .processExecutablePath = std.Io.failingProcessExecutablePath,
        .lockStderr = std.Io.unreachableLockStderr,
        .tryLockStderr = std.Io.noTryLockStderr,
        .unlockStderr = std.Io.unreachableUnlockStderr,
        .processCurrentPath = std.Io.failingProcessCurrentPath,
        .processSetCurrentDir = std.Io.failingProcessSetCurrentDir,
        .processSetCurrentPath = std.Io.failingProcessSetCurrentPath,
        .processReplace = std.Io.failingProcessReplace,
        .processReplacePath = std.Io.failingProcessReplacePath,
        .processSpawn = std.Io.failingProcessSpawn,
        .processSpawnPath = std.Io.failingProcessSpawnPath,
        .childWait = std.Io.unreachableChildWait,
        .childKill = std.Io.unreachableChildKill,

        .progressParentFile = std.Io.failingProgressParentFile,

        .now = now,
        .clockResolution = clockResolution,
        .sleep = sleep,

        .random = random,
        .randomSecure = randomSecure,

        .netListenIp = std.Io.failingNetListenIp,
        .netAccept = std.Io.failingNetAccept,
        .netBindIp = std.Io.failingNetBindIp,
        .netConnectIp = std.Io.failingNetConnectIp,
        .netListenUnix = std.Io.failingNetListenUnix,
        .netConnectUnix = std.Io.failingNetConnectUnix,
        .netSocketCreatePair = std.Io.failingNetSocketCreatePair,
        .netSend = std.Io.failingNetSend,
        .netRead = std.Io.failingNetRead,
        .netWrite = std.Io.failingNetWrite,
        .netWriteFile = std.Io.failingNetWriteFile,
        .netClose = std.Io.unreachableNetClose,
        .netShutdown = std.Io.failingNetShutdown,
        .netInterfaceNameResolve = std.Io.failingNetInterfaceNameResolve,
        .netInterfaceName = std.Io.unreachableNetInterfaceName,
        .netLookup = std.Io.failingNetLookup,
    };
};

fn crashHandler(userdata: ?*anyopaque) void {
    _ = userdata;
    const state = currentCancelState();
    state.canceled.store(true, .monotonic);
    state.cancel_protection.store(true, .monotonic);
}

fn concurrent(
    userdata: ?*anyopaque,
    result_len: usize,
    result_alignment: std.mem.Alignment,
    context: []const u8,
    context_alignment: std.mem.Alignment,
    start: *const fn (context: *const anyopaque, result: *anyopaque) void,
) std.Io.ConcurrentError!*std.Io.AnyFuture {
    _ = userdata;
    _ = context_alignment;
    std.debug.assert(result_alignment.toByteUnits() <= task_buffer_alignment);
    if (context.len > task_context_buffer_size or result_len > task_result_buffer_size)
        return error.ConcurrencyUnavailable;

    const slot = acquireSlot() orelse return error.ConcurrencyUnavailable;
    errdefer releaseSlot(slot);

    @memcpy(slot.context_buffer[0..context.len], context);
    slot.context_len = context.len;
    slot.result_len = result_len;
    slot.start = start;
    slot.done.store(false, .monotonic);
    slot.cancel_state.canceled.store(false, .monotonic);
    slot.cancel_state.cancel_protection.store(false, .monotonic);

    _ = jmptbl.task.vexTaskAddWithArg(@ptrCast(&taskEntry), 2, @ptrCast(slot), "V5Io.task");
    return @ptrCast(slot);
}

fn awaitFuture(
    userdata: ?*anyopaque,
    any_future: *std.Io.AnyFuture,
    result: []u8,
    result_alignment: std.mem.Alignment,
) void {
    _ = userdata;
    _ = result_alignment;
    const slot: *TaskSlot = @ptrCast(@alignCast(any_future));
    while (!slot.done.load(.acquire)) {
        jmptbl.task.vexTaskSleep(1);
    }
    @memcpy(result[0..slot.result_len], slot.result_buffer[0..slot.result_len]);
    releaseSlot(slot);
}

fn cancelFuture(
    userdata: ?*anyopaque,
    any_future: *std.Io.AnyFuture,
    result: []u8,
    result_alignment: std.mem.Alignment,
) void {
    _ = userdata;
    _ = result_alignment;
    const slot: *TaskSlot = @ptrCast(@alignCast(any_future));
    slot.cancel_state.canceled.store(true, .release);
    while (!slot.done.load(.acquire)) {
        jmptbl.task.vexTaskSleep(1);
    }
    @memcpy(result[0..slot.result_len], slot.result_buffer[0..slot.result_len]);
    releaseSlot(slot);
}

fn groupConcurrent(
    userdata: ?*anyopaque,
    group: *std.Io.Group,
    context: []const u8,
    context_alignment: std.mem.Alignment,
    start: *const fn (context: *const anyopaque) void,
) std.Io.ConcurrentError!void {
    _ = userdata;
    _ = group;
    _ = context_alignment;
    // Run eagerly; the group is left with no pending token, so `Group.await`
    // and `Group.cancel` return immediately.
    start(context.ptr);
}

fn recancel(userdata: ?*anyopaque) void {
    _ = userdata;
    const state = currentCancelState();
    std.debug.assert(!state.canceled.load(.monotonic)); // prior cancelation point must have returned error.Canceled
    state.canceled.store(true, .monotonic);
}

fn swapCancelProtection(userdata: ?*anyopaque, new: std.Io.CancelProtection) std.Io.CancelProtection {
    _ = userdata;
    const state = currentCancelState();
    const old = state.cancel_protection.swap(new == .blocked, .monotonic);
    return if (old) .blocked else .unblocked;
}

fn checkCancel(userdata: ?*anyopaque) std.Io.Cancelable!void {
    _ = userdata;
    return checkCancelState(currentCancelState());
}

fn futexWait(
    userdata: ?*anyopaque,
    ptr: *const u32,
    expected: u32,
    timeout: std.Io.Timeout,
) std.Io.Cancelable!void {
    _ = userdata;
    const state = currentCancelState();
    // Convert the timeout into a deadline on the awake clock. Relative
    // durations are clock-independent.
    const deadline_ns: ?i96 = switch (timeout) {
        .none => null,
        .duration => |d| d.raw.nanoseconds + nowNs(),
        .deadline => |d| switch (d.clock) {
            .awake, .boot => d.raw.nanoseconds,
            else => null, // unsupported clock: wait until canceled
        },
    };
    while (true) {
        if (ptr.* != expected) return;
        try checkCancelState(state);
        if (deadline_ns) |dl| {
            if (dl - nowNs() <= 0) return; // timeout expired: unblock
        }
        jmptbl.task.vexTaskSleep(1);
    }
}

fn futexWaitUncancelable(userdata: ?*anyopaque, ptr: *const u32, expected: u32) void {
    _ = userdata;
    while (ptr.* == expected) {
        jmptbl.task.vexTaskSleep(1);
    }
}

fn operate(
    userdata: ?*anyopaque,
    operation: std.Io.Operation,
) std.Io.Cancelable!std.Io.Operation.Result {
    const self: *V5Io = @ptrCast(@alignCast(userdata));
    return switch (operation) {
        .file_read_streaming => |op| .{
            .file_read_streaming = fileReadStreaming(self, op.file, op.data) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| e,
            },
        },
        .file_write_streaming => |op| .{
            .file_write_streaming = fileWriteStreaming(self, op.file, op.header, op.data, op.splat) catch |err| switch (err) {
                error.Canceled => |e| return e,
                else => |e| e,
            },
        },
        .device_io_control => .{ .device_io_control = -1 },
        .net_receive => .{ .net_receive = .{ error.NetworkDown, 0 } },
    };
}

fn batchAwaitAsync(userdata: ?*anyopaque, b: *std.Io.Batch) std.Io.Cancelable!void {
    const self: *V5Io = @ptrCast(@alignCast(userdata));
    batchAwaitFallback(self, b);
}

fn batchAwaitConcurrent(
    userdata: ?*anyopaque,
    b: *std.Io.Batch,
    timeout: std.Io.Timeout,
) std.Io.Batch.AwaitConcurrentError!void {
    const self: *V5Io = @ptrCast(@alignCast(userdata));
    _ = timeout;
    // Operations are performed synchronously, so they always complete before
    // the timeout expires.
    batchAwaitFallback(self, b);
}

fn batchCancel(userdata: ?*anyopaque, b: *std.Io.Batch) void {
    _ = userdata;
    // No operation is ever left pending: `Batch.cancel` has already moved the
    // submitted operations back to the unused list before calling us.
    std.debug.assert(b.pending.head == .none and b.pending.tail == .none);
    b.userdata = null;
}

fn fileStat(userdata: ?*anyopaque, file: std.Io.File) std.Io.File.StatError!std.Io.File.Stat {
    const self: *V5Io = @ptrCast(@alignCast(userdata));
    if (isConsole(file)) return error.Streaming;
    const fil = self.sd_file orelse return error.AccessDenied;
    return makeStat(@intCast(@max(0, jmptbl.file.vexFileSize(fil))));
}

fn fileLength(userdata: ?*anyopaque, file: std.Io.File) std.Io.File.LengthError!u64 {
    const self: *V5Io = @ptrCast(@alignCast(userdata));
    if (isConsole(file)) return error.Streaming;
    const fil = self.sd_file orelse return error.AccessDenied;
    return @intCast(@max(0, jmptbl.file.vexFileSize(fil)));
}

fn fileClose(userdata: ?*anyopaque, files: []const std.Io.File) void {
    const self: *V5Io = @ptrCast(@alignCast(userdata));
    for (files) |file| {
        if (isConsole(file)) continue;
        if (self.sd_file) |fil| {
            jmptbl.file.vexFileClose(fil);
            self.sd_file = null;
        }
    }
}

fn fileWritePositional(
    userdata: ?*anyopaque,
    file: std.Io.File,
    header: []const u8,
    data: []const []const u8,
    splat: usize,
    offset: u64,
) std.Io.File.WritePositionalError!usize {
    const self: *V5Io = @ptrCast(@alignCast(userdata));
    if (isConsole(file)) {
        // The console has no position; write the data regardless of `offset`.
        var written: usize = 0;
        written += serialWriteAll(header) catch |err| switch (err) {
            error.InputOutput => return error.InputOutput,
        };
        for (data[0 .. data.len - 1]) |bytes| written += serialWriteAll(bytes) catch return error.InputOutput;
        const pattern = data[data.len - 1];
        for (0..splat) |_| written += serialWriteAll(pattern) catch return error.InputOutput;
        return written;
    }
    const fil = self.sd_file orelse return error.NotOpenForWriting;
    if (offset > std.math.maxInt(u32)) return error.FileTooBig;
    const old_pos = jmptbl.file.vexFileTell(fil);
    _ = jmptbl.file.vexFileSeek(fil, @intCast(offset), 0); // SEEK_SET
    defer _ = jmptbl.file.vexFileSeek(fil, @intCast(@max(0, old_pos)), 0); // SEEK_SET
    var written: usize = 0;
    written += fileWriteAll(fil, header) catch |err| switch (err) {
        error.InputOutput => return error.InputOutput,
        error.NoSpaceLeft => return error.NoSpaceLeft,
    };
    for (data[0 .. data.len - 1]) |bytes| written += fileWriteAll(fil, bytes) catch |err| switch (err) {
        error.InputOutput => return error.InputOutput,
        error.NoSpaceLeft => return error.NoSpaceLeft,
    };
    const pattern = data[data.len - 1];
    for (0..splat) |_| written += fileWriteAll(fil, pattern) catch |err| switch (err) {
        error.InputOutput => return error.InputOutput,
        error.NoSpaceLeft => return error.NoSpaceLeft,
    };
    return written;
}

fn fileReadPositional(
    userdata: ?*anyopaque,
    file: std.Io.File,
    data: []const []u8,
    offset: u64,
) std.Io.File.ReadPositionalError!usize {
    const self: *V5Io = @ptrCast(@alignCast(userdata));
    if (isConsole(file)) return error.Unseekable;
    const fil = self.sd_file orelse return error.NotOpenForReading;
    if (offset > std.math.maxInt(u32)) return error.Unseekable;
    const old_pos = jmptbl.file.vexFileTell(fil);
    _ = jmptbl.file.vexFileSeek(fil, @intCast(offset), 0); // SEEK_SET
    defer _ = jmptbl.file.vexFileSeek(fil, @intCast(@max(0, old_pos)), 0); // SEEK_SET
    var total: usize = 0;
    for (data) |buf| {
        if (buf.len == 0) continue;
        const n = jmptbl.file.vexFileRead(buf.ptr, 1, @intCast(buf.len), fil);
        if (n < 0) return error.InputOutput;
        if (n == 0) break;
        total += @intCast(n);
        if (@as(u32, @intCast(n)) < buf.len) break;
    }
    return total;
}

fn fileSeekBy(userdata: ?*anyopaque, file: std.Io.File, relative_offset: i64) std.Io.File.SeekError!void {
    const self: *V5Io = @ptrCast(@alignCast(userdata));
    if (isConsole(file)) return error.Unseekable;
    const fil = self.sd_file orelse return error.Unseekable;
    const cur = jmptbl.file.vexFileTell(fil);
    if (cur < 0) return error.AccessDenied;
    const new_pos = @as(i64, cur) + relative_offset;
    if (new_pos < 0 or new_pos > std.math.maxInt(u32)) return error.AccessDenied;
    _ = jmptbl.file.vexFileSeek(fil, @intCast(new_pos), 0); // SEEK_SET
}

fn fileSeekTo(userdata: ?*anyopaque, file: std.Io.File, absolute_offset: u64) std.Io.File.SeekError!void {
    const self: *V5Io = @ptrCast(@alignCast(userdata));
    if (isConsole(file)) return error.Unseekable;
    const fil = self.sd_file orelse return error.Unseekable;
    if (absolute_offset > std.math.maxInt(u32)) return error.AccessDenied;
    _ = jmptbl.file.vexFileSeek(fil, @intCast(absolute_offset), 0); // SEEK_SET
}

fn fileSync(userdata: ?*anyopaque, file: std.Io.File) std.Io.File.SyncError!void {
    const self: *V5Io = @ptrCast(@alignCast(userdata));
    if (isConsole(file)) return;
    const fil = self.sd_file orelse return error.AccessDenied;
    jmptbl.file.vexFileSync(fil);
}

fn fileIsTty(userdata: ?*anyopaque, file: std.Io.File) std.Io.Cancelable!bool {
    _ = userdata;
    return isConsole(file);
}

fn fileEnableAnsiEscapeCodes(userdata: ?*anyopaque, file: std.Io.File) std.Io.File.EnableAnsiEscapeCodesError!void {
    _ = userdata;
    if (isConsole(file)) return;
    return error.NotTerminalDevice;
}

fn fileSupportsAnsiEscapeCodes(userdata: ?*anyopaque, file: std.Io.File) std.Io.Cancelable!bool {
    _ = userdata;
    return isConsole(file);
}

fn fileSetLength(userdata: ?*anyopaque, file: std.Io.File, length: u64) std.Io.File.SetLengthError!void {
    _ = userdata;
    _ = file;
    _ = length;
    return error.NonResizable;
}

fn now(userdata: ?*anyopaque, clock: std.Io.Clock) std.Io.Timestamp {
    _ = userdata;
    return switch (clock) {
        .awake, .boot => .{ .nanoseconds = nowNs() },
        // No wall-clock is available on the V5, and CPU clocks cannot be
        // measured. Report the epoch.
        .real, .cpu_process, .cpu_thread => .zero,
    };
}

fn clockResolution(userdata: ?*anyopaque, clock: std.Io.Clock) std.Io.Clock.ResolutionError!std.Io.Duration {
    _ = userdata;
    return switch (clock) {
        .awake, .boot => .{ .nanoseconds = std.time.ns_per_us },
        .real, .cpu_process, .cpu_thread => error.ClockUnavailable,
    };
}

fn sleep(userdata: ?*anyopaque, timeout: std.Io.Timeout) std.Io.Cancelable!void {
    _ = userdata;
    const state = currentCancelState();
    // Convert the timeout into a deadline on the awake clock. Relative
    // durations are clock-independent; deadlines on unsupported clocks never
    // expire and simply wait until canceled.
    const deadline_ns: ?i96 = switch (timeout) {
        .none => null,
        .duration => |d| d.raw.nanoseconds + nowNs(),
        .deadline => |d| switch (d.clock) {
            .awake, .boot => d.raw.nanoseconds,
            else => null,
        },
    };
    while (true) {
        try checkCancelState(state);
        if (deadline_ns) |dl| {
            const remaining_ns = dl - nowNs();
            if (remaining_ns <= 0) return;
            const remaining_ms: u32 = @intCast(@min(
                @divTrunc(remaining_ns, std.time.ns_per_ms),
                sleep_chunk_ms,
            ));
            jmptbl.task.vexTaskSleep(@max(1, remaining_ms));
        } else {
            jmptbl.task.vexTaskSleep(sleep_chunk_ms);
        }
    }
}

/// Seeds the shared PRNG from hardware timers and the stack pointer, which
/// vary across power cycles. Must be called while holding `prng_lock`.
fn seedPrng() void {
    if (prng_seeded) return;
    prng_seeded = true;
    var stack_probe: [32]u8 = undefined;
    var seed: u64 = jmptbl.system.vexSystemHighResTimeGet();
    seed ^= @as(u64, jmptbl.system.vexSystemTimeGet()) *% 0x9E3779B97F4A7C15;
    seed ^= jmptbl.system.vexSystemPowerupTimeGet();
    seed ^= @intFromPtr(&stack_probe);
    prng = .init(seed);
}

fn random(userdata: ?*anyopaque, buffer: []u8) void {
    _ = userdata;
    while (prng_lock.cmpxchgWeak(false, true, .acq_rel, .acquire) != null) {
        jmptbl.task.vexTaskYield();
    }
    defer prng_lock.store(false, .release);
    seedPrng();
    prng.random().bytes(buffer);
}

fn randomSecure(userdata: ?*anyopaque, buffer: []u8) std.Io.RandomSecureError!void {
    _ = userdata;
    _ = buffer;
    // The jumptable exposes no secure entropy source.
    return error.EntropyUnavailable;
}
