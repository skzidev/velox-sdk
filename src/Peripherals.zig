const std = @import("std");
const jmptbl = @import("velox_jumptable");
const motor = @import("devices/Motor.zig");

fn isStruct(comptime ti: std.builtin.Type) bool {
    return switch (ti) {
        .@"struct" => true,
        else => false,
    };
}

const DeviceType = enum {
    motor,
};

fn getPeripheralType(comptime dType: DeviceType) type {
    return switch (dType) {
        .motor => motor.Motor,
    };
}

/// Provides a "Peripherals" type that allows the user code to have named devices, defined at compile time
pub fn Peripherals(comptime config: anytype) type {
    const configT = @TypeOf(config);
    const configTInfo = @typeInfo(configT);
    if (!isStruct(configTInfo)) {
        @compileError("Configuration must be a struct");
    }
    const fields = configTInfo.@"struct".fields;
    const names: [fields.len][]const u8 = undefined;
    const types: [fields.len]type = undefined;
    const attrs: [fields.len]std.lang.Type.StructField.Attributes = undefined;
    inline for (fields, 0..) |field, idx| {
        names[idx] = field.name;
        types[idx] = getPeripheralType(@field(config, "type"));
        attrs[idx] = .{};
    }
    const T = @Struct(.auto, configTInfo.@"struct".backing_integer, &names, &types, &attrs);
    return T;
}
