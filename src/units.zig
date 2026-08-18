/// Possible Motor Rotational Units
pub const MotorUnit = enum {
    rpm,
    volts,
    percent,
};

pub const TempUnit = enum {
    celsius,
    farenheit,
};

pub const LengthUnit = enum {
    inch,
    millimeter,
    centimeter,
};
