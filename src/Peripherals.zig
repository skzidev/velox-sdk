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

fn Peripherals(comptime config: anytype) type {
    const configT = @TypeOf(config);
    const configTInfo = @typeInfo(configT);
    if (!isStruct(configTInfo)) {
        @compileError("Configuration must be a struct");
    }
    const fields = configTInfo.@"struct".fields;
    comptime var names = [fields.len]0;
    comptime var types = [fields.len]null;
    comptime var attrs: [fields.len]std.builtin.Type.StructField.Attributes = undefined;
    inline for (fields, 0..) |field, i| {
        names[i] = field.name;
        attrs[i] = .{ .default_ptr_value = @as(?*const anyopaque, null) };
        types[i] = field.type;
    }
    const T = @Struct(
        std.builtin.Type.ContainerLayout.auto,
        configTInfo.@"struct".backing_integer,
        &names,
        &types,
        &attrs,
    );
    return T;
}

pub fn getPeripherals(config: anytype) Peripherals(config) {}
