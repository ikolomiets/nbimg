//! Shared typed-operation response ownership.

const std = @import("std");

/// Owns a completed non-success HTTP response body.
pub const ApiFailure = struct {
    status: std.http.Status,
    body: []u8,

    /// Frees the response body and invalidates the value.
    pub fn deinit(failure: *ApiFailure, allocator: std.mem.Allocator) void {
        allocator.free(failure.body);
        failure.* = undefined;
    }
};

/// Represents either a decoded operation result or a completed API failure.
pub fn Outcome(comptime T: type) type {
    return union(enum) {
        success: T,
        api_failure: ApiFailure,
    };
}

/// Separates completed responses by transport and decoding stage.
pub fn OperationOutcome(comptime T: type) type {
    return union(enum) {
        success: T,
        api_failure: ApiFailure,
        response_decoding_failure: anyerror,
    };
}
