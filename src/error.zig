/// Errors that can result from device initalization
pub const DeviceInitError = error{
    InvalidPortError,
};

pub fn portIsValid(port: u32) bool {
    return (port < 21 and port != 0);
}
