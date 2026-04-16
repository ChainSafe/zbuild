const shared = @import("shared");

pub fn get() []const u8 {
    return shared.message;
}
