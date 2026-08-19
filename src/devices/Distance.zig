const jmptbl = @import("velox_jumptable");
const units = @import("../units.zig");
const errors = @import("../error.zig");

/// # V5 Distance Sensor
///
/// This struct represents a V5 Distance Sensor (276-4852).
pub const Distance = struct {
    _handle: ?*anyopaque,
    /// Instantiate a new Distance Sensor
    pub fn init(
        /// The port number
        port: u32,
    ) errors.DeviceInitError!Distance {
        if (!errors.portIsValid(port))
            return errors.DeviceInitError.InvalidPortError;
        return Distance{
            ._handle = jmptbl.devices.vexDeviceGetByIndex(port - 1),
        };
    }

    /// Get the distance between the distance sensor and the object which it is detecting
    ///
    /// **Return type**: The distance in the specified units
    pub fn distance(
        self: *Distance,
        /// The unit in which the response should be returned
        unit: units.LengthUnit,
    ) f32 {
        const mm = jmptbl.distance.vexDeviceDistanceDistanceGet(self._handle);
        return switch (unit) {
            // metric
            .millimeter => mm,
            .centimeter => mm / 10,
            // imperial
            .inch => mm / 25.4,
            .feet => (mm / 25.4) / 12,
        };
    }

    pub fn confidence(
        self: *Distance,
    ) u32 {
        return jmptbl.distance.vexDeviceDistanceConfidenceGet(self._handle);
    }

    pub fn objectSize(
        self: *Distance,
    ) i32 {
        // The 400 scale which it returns is not very useful
        // I should replace this with an actual size approximation function
        return jmptbl.distance.vexDeviceDistanceObjectSizeGet(self._handle);
    }

    pub fn objectVelocity(
        self: *Distance,
    ) f64 {
        return jmptbl.distance.vexDeviceDistanceObjectVelocityGet(self._handle);
    }

    //pub fn status(self: *Distance) u32 {
    //    return jmptbl.distance.vexDeviceDistanceStatusGet(self._handle);
    //}
};
