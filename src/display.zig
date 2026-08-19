const jmptbl = @import("velox_jumptable");
const std = @import("std");

/// An abstraction over the V5 Brain's built-in LCD display.
///
/// The V5 LCD supports line-based text output. Lines are numbered starting
/// at 0, with a maximum of 8 lines (0–7). Each call to [`printOnLine`]
/// overwrites the content of the specified line.
///
/// ## Example
///
/// ```zig
/// const velox = @import("velox_sdk");
///
/// velox_sdk.Display.printOnLine("Velox SDK v0.1", 0);
/// velox_sdk.Display.printOnLine("Motor temp: 42C", 1);
/// velox_sdk.Display.printOnLine("Battery: 100%", 2);
/// ```
///
/// **Note:** This is a static API — no instance is required.
pub const Display = struct {
    /// A position on the V5 Brain's LCD screen, specified in pixel coordinates.
    pub const ScreenPos = struct {
        /// The horizontal pixel coordinate.
        x: i32,
        /// The vertical pixel coordinate.
        y: i32,
    };

    /// Errors that can occur when interacting with the V5 display.
    pub const DisplayError = error{
        /// The specified line number is invalid (less than 0).
        InvalidLineError,
    };

    /// Prints a string to the LCD on the specified line.
    ///
    /// The string is displayed immediately on the given line. Previous
    /// content on that line is replaced. Lines are numbered starting at 0;
    /// the V5 LCD supports up to 8 lines (0–7).
    ///
    /// `str` must be a valid UTF-8 string. Non-ASCII characters may not
    /// render correctly on the LCD.
    ///
    /// ## Example
    ///
    /// ```zig
    /// velox_sdk.Display.printOnLine("Status: OK", 0);
    /// velox_sdk.Display.printOnLine("RPM: 200", 3);
    /// ```
    ///
    /// **Errors:**
    /// - `InvalidLineError` — `line` is negative.
    pub fn printOnLine(
        allocator: std.mem.Allocator,
        /// The text to display on the line.
        str: []const u8,
        /// The line number (0–7). Negative values return an error.
        line: i32,
    ) DisplayError.InvalidLineError!void {
        if (line < 0) return DisplayError.InvalidLineError;

        const c_string = try allocator.dupeZ(u8, str);
        defer allocator.free(c_string);

        const c_ptr: [*:0]const u8 = @ptrCast(c_string.ptr);
        jmptbl.display.vexDisplayString(line, c_ptr);
    }
};
