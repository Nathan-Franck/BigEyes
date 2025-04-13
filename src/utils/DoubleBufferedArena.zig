const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;

backing_allocator: Allocator,
arenas: [2]ArenaAllocator,
active_index: u1,

/// Initializes the DoubleBufferedArena using the provided backing allocator.
/// The DoubleBufferedArena does NOT take ownership of the backing_allocator;
/// it must be deinitialized separately after the DoubleBufferedArena.
pub fn init(backing_allocator: Allocator) @This() {
    return @This(){
        .backing_allocator = backing_allocator,
        .arenas = .{
            ArenaAllocator.init(backing_allocator),
            ArenaAllocator.init(backing_allocator),
        },
        .active_index = 0, // Start with the first arena
    };
}

/// Deinitializes both internal ArenaAllocators.
/// Does NOT deinitialize the backing allocator provided during init.
pub fn deinit(self: *@This()) void {
    // Deinitialize both arenas using the original backing allocator
    self.arenas[0].deinit(self.backing_allocator);
    self.arenas[1].deinit(self.backing_allocator);
    // Reset state to prevent accidental use after deinit
    self.* = undefined;
}

/// Returns the Allocator interface for the currently active arena.
/// Use this for all allocations you want managed by the double buffer.
pub fn allocator(self: *@This()) Allocator {
    return self.arenas[self.active_index].allocator();
}

/// Swaps the active arena.
/// Data from the previous cycle can still be referenced.
pub fn swap(self: *@This()) void {
    self.active_index = 1 - self.active_index;
    _ = self.arenas[self.active_index].reset(.retain_capacity);
}
