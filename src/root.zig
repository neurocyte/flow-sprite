const adapter = @import("sprite_adapter.zig");

pub const renderSprite = adapter.renderSprite;
pub const hasCodepoint = adapter.hasCodepoint;

test {
    @import("std").testing.refAllDecls(@This());
}
