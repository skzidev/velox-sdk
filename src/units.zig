/// Possible Motor Rotational Units
pub const MotorUnit = enum {
    rpm,
    volts,
    percent,
};

/// Units of Temperature
pub const TempUnit = enum {
    celsius,
    fahrenheit,
};

/// Units of length/distance
pub const LengthUnit = enum {
    inch,
    foot,
    millimeter,
    centimeter,
};

// Units of rotation
pub const RotationalUnit = enum {
    degree,
    turn,
    radian,
};
