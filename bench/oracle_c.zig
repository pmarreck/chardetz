//! The uchardet C ABI of the test-only C++ oracle library, declared for the
//! benchmark (imported as "c"). Never part of chardetz itself.
const Handle = opaque {};

const raw = struct {
    extern fn uchardet_new() ?*Handle;
    extern fn uchardet_delete(ud: *Handle) void;
    extern fn uchardet_handle_data(ud: *Handle, data: [*c]const u8, len: usize) c_int;
    extern fn uchardet_data_end(ud: *Handle) void;
    extern fn uchardet_get_charset(ud: *Handle) [*:0]const u8;
};

pub fn uchardet_new() *Handle {
    return raw.uchardet_new() orelse @panic("uchardet_new: out of memory");
}
pub const uchardet_delete = raw.uchardet_delete;
pub const uchardet_handle_data = raw.uchardet_handle_data;
pub const uchardet_data_end = raw.uchardet_data_end;
pub const uchardet_get_charset = raw.uchardet_get_charset;
