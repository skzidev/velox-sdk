const jmptbl = @import("velox_jumptable");
const units = @import("../units.zig");
const errors = @import("../error.zig");
const std = @import("std");
const pi = std.math.pi;

/// A VEX V5 Inertial Sensor (IMU) — provides orientation, heading,
/// and quaternion data for tracking robot rotation.
///
/// The Inertial Sensor contains a gyroscope and accelerometer that are
/// fused to provide accurate rotation tracking. After [`reset`], the
/// sensor calibrates for approximately 2 seconds before providing
/// stable readings.
///
/// ## Example
///
/// ```zig
/// var imu = velox_sdk.Inertial.init(6);
/// imu.reset();  // calibrate (~2 seconds)
///
/// const heading_deg = imu.heading(.degree);
/// const heading_rad = imu.heading(.radian);
/// ```
///
/// **Note:** Port validation is not currently performed. Ensure the port
/// number is in the valid range (1–20).
pub const Inertial = struct {
    _handle: ?*anyopaque,

    /// A quaternion representing the sensor's orientation in 3D space.
    ///
    /// The quaternion components are:
    /// - `x`, `y`, `z` — the vector part
    /// - `w` — the scalar part
    ///
    /// A unit quaternion (magnitude 1.0) represents a valid rotation.
    pub const InertialQuaternion = struct {
        /// The X component of the quaternion.
        x: f64,
        /// The Y component of the quaternion.
        y: f64,
        /// The Z component of the quaternion.
        z: f64,
        /// The W (scalar) component of the quaternion.
        w: f64,
    };

    /// Initializes an Inertial Sensor on the given port.
    ///
    /// After initialization, call [`reset`] to calibrate the sensor.
    /// Calibration takes approximately 2 seconds.
    ///
    /// ## Example
    ///
    /// ```zig
    /// var imu = velox_sdk.Inertial.init(6);
    /// imu.reset();  // block until calibration completes
    /// ```
    pub fn init(
        /// The smart port number (1–20).
        port: u32,
    ) errors.DeviceInitError!Inertial {
        if (!errors.portIsValid(port))
            return errors.DeviceInitError.InvalidPortError;
        return Inertial{
            ._handle = jmptbl.devices.vexDeviceGetByIndex(port - 1),
        };
    }

    /// Resets and calibrates the inertial sensor.
    ///
    /// This blocks the current task for approximately 2 seconds while
    /// the sensor calibrates. During calibration, the sensor should
    /// remain stationary.
    ///
    /// ```zig
    /// imu.reset();  // blocks for ~2 seconds
    /// ```
    pub fn reset(self: *Inertial) void {
        jmptbl.imu.vexDeviceImuReset(self._handle);
    }

    /// Returns the sensor's orientation as a quaternion.
    ///
    /// The quaternion represents the rotation from the sensor's
    /// reference frame to its current orientation. A unit quaternion
    /// (magnitude ≈ 1.0) indicates a valid rotation.
    ///
    /// This method requires an allocator because the underlying
    /// jumptable API expects a pointer to a single quaternion. The
    /// allocation is immediately freed after the value is copied.
    ///
    /// ```zig
    /// const q = try imu.quat(allocator);
    /// // q.x, q.y, q.z, q.w
    /// ```
    ///
    /// **Errors:**
    /// - Returns an allocation error if the allocator fails.
    pub fn quat(self: *Inertial, alloc: std.mem.Allocator) !InertialQuaternion {
        const quatPtr = try alloc.alloc(InertialQuaternion, 1);
        defer alloc.destroy(quatPtr);
        jmptbl.imu.vexDeviceImuQuaternionGet(self._handle, quatPtr);
        return quatPtr[0];
    }

    /// Returns the sensor's heading (cumulative rotation) in the
    /// specified units.
    ///
    /// Heading tracks total rotation from the last [`reset`]. It can
    /// exceed 360° / 2π if the sensor rotates multiple times.
    ///
    /// ## Units
    ///
    /// - `.degree` — degrees (cumulative, can exceed 360).
    /// - `.turn` — turns / revolutions (cumulative, can exceed 1.0).
    /// - `.radian` — radians (cumulative, can exceed 2π).
    ///
    /// ```zig
    /// const deg = imu.heading(.degree);
    /// const rad = imu.heading(.radian);
    /// ```
    pub fn heading(self: *Inertial, unit: units.RotationalUnit) f64 {
        const deg = jmptbl.imu.vexDeviceImuHeadingGet(self._handle);
        return switch (unit) {
            .degree => deg,
            .radian => deg * (pi / 180),
            .turn => deg / 360,
        };
    }
};
