/// Errors that can occur during peripheral device initialization.
pub const DeviceInitError = error{
    /// The port number is invalid. Valid smart ports are 1–20; valid ADI
    /// ports are 1–8.
    InvalidPortError,
};

/// Returns `true` if `port` is a valid VEX V5 smart port number.
///
/// Valid smart ports range from 1 to 20 (inclusive). The V5 Brain has 21
/// physical port slots (indexed 0–20), but port 0 is not user-addressable.
///
/// ## Example
///
/// ```zig
/// if (velox_sdk.error.portIsValid(5)) {
///     // port 5 is valid
/// }
/// ```
pub fn portIsValid(port: u32) bool {
    return (port < 21 and port != 0);
}
