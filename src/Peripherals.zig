const std = @import("std");
const jmptbl = @import("velox_jumptable");

const motor = @import("devices/Motor.zig");
const distance = @import("devices/Distance.zig");
const adi = @import("devices/ADI.zig");
const inertial = @import("devices/Inertial.zig");
const rotation = @import("devices/Rotation.zig");
const bumper = @import("devices/Bumper.zig");

fn isStruct(comptime ti: std.builtin.Type) bool {
    return switch (ti) {
        .@"struct" => true,
        else => false,
    };
}

/// Supported peripheral device types.
///
/// Each variant maps to a concrete device driver type:
/// - `.motor` → [`Motor`](root.Motor)
/// - `.distance` → [`Distance`](root.Distance)
pub const DeviceType = enum {
    motor,
    distance,
    rotation,
    inertial,
    adi,
    bumper,
};

fn getPeripheralType(comptime dType: DeviceType) type {
    return switch (dType) {
        .motor => motor.Motor,
        .distance => distance.Distance,
        .inertial => inertial.Inertial,
        .bumper => bumper.Bumper,
        .rotation => rotation.Rotation,
    };
}

/// Builds a struct of typed device handles from a user-supplied
/// configuration.
///
/// `config` must be a struct where each field's name becomes the field name
/// in the resulting type, and each field must itself be a struct with a
/// `.type` field whose value is a [`DeviceType`] variant.
///
/// The resulting struct can be default-initialized (all fields start as
/// zeroed memory — you must call `.init()` on each device to make it
/// usable).
///
/// ## Supported device types
///
/// | `.type` value | Resulting device type |
/// |---|---|
/// | `.motor` | [`velox_sdk.Motor`](root.Motor) |
/// | `.distance` | [`velox_sdk.Distance`](root.Distance) |
///
/// ## Example
///
/// ```zig
/// const MyDevices = struct {
///     front_left: struct { .type = .motor },
///     front_right: struct { .type = .motor },
///     dist_front: struct { .type = .distance },
/// };
///
/// const Devices = velox_sdk.Peripherals(MyDevices);
/// // Devices has fields: .front_left (Motor), .front_right (Motor),
/// //                     .dist_front (Distance)
/// ```
///
/// **Compile errors:**
/// - `config` must be a struct.
/// - Each field must have a `.type` key that is a valid `DeviceType`.
pub fn Peripherals(comptime config: anytype) type {
    const configT = @TypeOf(config);
    const configTInfo = @typeInfo(configT);
    if (!isStruct(configTInfo)) {
        @compileError("Configuration must be a struct");
    }
    const fields = configTInfo.@"struct".fields;
    var names: [fields.len][]const u8 = undefined;
    var types: [fields.len]type = undefined;
    var attrs: [fields.len]std.builtin.Type.StructField.Attributes = undefined;
    inline for (fields, 0..) |field, idx| {
        names[idx] = field.name;
        types[idx] = getPeripheralType(@field(@field(config, field.name), "type"));
        attrs[idx] = .{
            .@"align" = @alignOf(types[idx]),
            .@"comptime" = false,
            .default_value_ptr = null,
        };
    }
    const T = @Struct(.auto, configTInfo.@"struct".backing_integer, &names, &types, &attrs);
    return T;
}
