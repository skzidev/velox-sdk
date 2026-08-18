const jmptbl = @import("velox_jumptable");

pub const ScreenPos = struct { x: i32, y: i32 };

pub const DisplayError = error{
    /// The specified line was invalid.
    InvalidLineError,
};

pub const Display = struct {
    /// Prints a string to the screen on the specified line.
    ///
    /// **Parameters**:
    /// - `str` ([]const u8) - _The string which should be printed to the screen._
    /// - `line` (i32) - _The line which the string should be printed on_
    ///
    /// **Return Value**: Void
    ///
    /// **Errors**:
    /// - `InvalidLineError`: The line which the user tried to print on does not exist _(this means it is less than 0)_
    ///
    /// For instance:
    /// ```zig
    /// robot.display.print("Hello, World!", 1);
    /// ```
    pub fn print(str: []const u8, line: i32) DisplayError.InvalidLineError!void {
        if (line < 0) return DisplayError.InvalidLineError;
        const c_ptr: [*:0]const u8 = @ptrCast(str.ptr);
        jmptbl.display.vexDisplayString(line, c_ptr);
    }
};
