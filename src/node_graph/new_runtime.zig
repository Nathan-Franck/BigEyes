const std = @import("std");
const utils = @import("utils");
const zmath = @import("zmath");
const utils_node = @import("../node_graph.zig").utils_node;
const types = @import("resources").types;
const config = @import("resources").config;
const builtin = std.builtin;

fn isAllocatorFirstParam(t: type) bool {
    const params = fnParams(t);
    return switch (params.len) {
        1 => false,
        2 => true,
        else => @compileError("Unsupported node function parameters"),
    };
}

fn fnParams(t: type) []const std.builtin.Type.Fn.Param {
    return @typeInfo(t).@"fn".params;
}

fn ParamsToNodeProps(@"fn": type) type {
    const params = fnParams(@"fn");
    return params[if (isAllocatorFirstParam(@"fn")) 1 else 0].type.?;
}

fn NodeInputs(@"fn": anytype) type {
    const raw_props = ParamsToNodeProps(@TypeOf(@"fn"));
    var new_field: []const std.builtin.Type.StructField = &.{};
    for (@typeInfo(raw_props).@"struct".fields) |field| {
        const default = .{ field.type, @alignOf(field.type) };
        const new_t: type, const alignment: comptime_int = switch (@typeInfo(field.type)) {
            .@"struct" => blk: {
                if (utils_node.queryable.getSourceOrNull(field.type)) |t| {
                    break :blk .{ t, @alignOf(t) };
                } else {
                    break :blk default;
                }
            },
            .pointer => |pointer| if (!pointer.is_const) switch (pointer.size) {
                else => default,
                .One => .{ pointer.child, @alignOf(field.type) },
                .Slice => .{ []const pointer.child, @alignOf(field.type) },
            } else default,
            else => default,
        };
        new_field = new_field ++ .{std.builtin.Type.StructField{
            .name = field.name,
            .type = Dirtyable(new_t),
            .default_value = null,
            .is_comptime = false,
            .alignment = alignment,
        }};
    }
    return @Type(std.builtin.Type{ .@"struct" = .{
        .layout = .auto,
        .fields = new_field,
        .decls = &.{},
        .is_tuple = false,
    } });
}

fn MutableProps(@"fn": anytype) type {
    const raw_props = ParamsToNodeProps(@TypeOf(@"fn"));
    var new_field: []const std.builtin.Type.StructField = &.{};
    for (@typeInfo(raw_props).@"struct".fields) |field| {
        const new_t: type, const alignment: comptime_int = switch (@typeInfo(field.type)) {
            .pointer => |pointer| if (!pointer.is_const) switch (pointer.size) {
                else => continue,
                .One => .{ pointer.child, @alignOf(pointer.child) },
                .Slice => .{ []const pointer.child, @alignOf(pointer.child) },
            } else continue,
            else => continue,
        };
        new_field = new_field ++ .{std.builtin.Type.StructField{
            .name = field.name,
            .type = new_t,
            .default_value = null,
            .is_comptime = false,
            .alignment = alignment,
        }};
    }
    return @Type(std.builtin.Type{ .@"struct" = .{
        .layout = .auto,
        .fields = new_field,
        .decls = &.{},
        .is_tuple = false,
    } });
}

fn NodeOutputs(@"fn": anytype) type {
    const MP = MutableProps(@"fn");
    const fn_return = @typeInfo(@TypeOf(@"fn")).@"fn".return_type.?;
    const raw_return = switch (@typeInfo(fn_return)) {
        else => fn_return,
        .error_union => |e| e.payload,
    };
    var new_fields = @typeInfo(raw_return).@"struct".fields;
    for (@typeInfo(MP).@"struct".fields) |mutable_field| {
        new_fields = new_fields ++ .{mutable_field};
    }
    return DirtyableFields(@Type(std.builtin.Type{ .@"struct" = .{
        .layout = .auto,
        .fields = new_fields,
        .decls = &.{},
        .is_tuple = false,
    } }));
}

fn PartialFields(t: type) type {
    var new_fields: []const std.builtin.Type.StructField = &.{};
    for (@typeInfo(t).@"struct".fields) |field| {
        new_fields = new_fields ++ .{std.builtin.Type.StructField{
            .name = field.name,
            .type = ?field.type,
            .default_value = blk: {
                const default_value: ?field.type = null;
                break :blk @ptrCast(&default_value);
            },
            .is_comptime = false,
            .alignment = @alignOf(field.type),
        }};
    }
    return @Type(std.builtin.Type{ .@"struct" = .{
        .layout = .auto,
        .fields = new_fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

fn Dirtyable(T: type) type {
    return struct {
        raw: T,
        is_dirty: bool,
        fn set(self: *@This(), value: T) void {
            self.is_dirty = true;
            self.raw = value;
        }
    };
}

pub fn DirtyableFields(T: type) type {
    var new_fields: []const std.builtin.Type.StructField = &.{};
    for (@typeInfo(T).@"struct".fields) |field| {
        new_fields = new_fields ++ .{std.builtin.Type.StructField{
            .name = field.name,
            .type = Dirtyable(field.type),
            .default_value = null,
            .is_comptime = false,
            .alignment = @alignOf(field.type),
        }};
    }
    return @Type(std.builtin.Type{ .@"struct" = .{
        .layout = .auto,
        .fields = new_fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    node_states: std.StringHashMap(NodeState),

    pub fn node(self: *@This(), comptime src: std.builtin.SourceLocation, @"fn": anytype, dirtyable_props: NodeInputs(@"fn")) *NodeOutputs(@"fn") {
        const src_key = std.fmt.comptimePrint("{s}:{d}:{d}", .{ src.file, src.line, src.column });

        const state = if (self.node_states.getPtr(src_key)) |arena| arena else blk: {
            const new_state: NodeState = .{
                .arena = std.heap.ArenaAllocator.init(self.allocator),
                .data = null,
            };

            self.node_states.put(src_key, new_state) catch unreachable;
            break :blk self.node_states.getPtr(src_key).?;
        };
        _ = state.arena.reset(.retain_capacity);

        var mutable_props: MutableProps(@"fn") = undefined;
        inline for (@typeInfo(@TypeOf(mutable_props)).@"struct".fields) |field| {
            const dirtyable_prop = @field(dirtyable_props, field.name);
            @field(mutable_props, field.name) = utils.deepClone(
                @TypeOf(dirtyable_prop.raw),
                state.arena.allocator(),
                dirtyable_prop.raw,
            ) catch unreachable;
        }

        const Props = ParamsToNodeProps(@TypeOf(@"fn"));
        var props: Props = undefined;
        var is_input_dirty = false;
        inline for (@typeInfo(Props).@"struct".fields) |prop| {
            var dirtyable_prop = @field(dirtyable_props, prop.name);
            const default = dirtyable_prop.raw;
            const input_field = switch (@typeInfo(prop.type)) {
                .@"struct" => blk: {
                    if (utils_node.queryable.getSourceOrNull(prop.type)) |t| {
                        var queried = true;
                        break :blk utils_node.queryable.Value(t).initQueryable(default, &dirtyable_prop.is_dirty, &queried);
                    } else {
                        break :blk default;
                    }
                },
                .pointer => |pointer| if (!pointer.is_const) switch (pointer.size) {
                    else => default,
                    .One => &@field(mutable_props, prop.name),
                    .Slice => &@field(dirtyable_props, prop.name),
                } else default,
                else => default,
            };
            if (dirtyable_prop.is_dirty)
                is_input_dirty = true;
            @field(props, prop.name) = input_field;
        }
        if (is_input_dirty or state.data == null) {
            const raw_fn_output = @call(.auto, @"fn", if (comptime isAllocatorFirstParam(@TypeOf(@"fn")))
                .{ state.arena.allocator(), props }
            else
                .{props});
            const fn_output = switch (@typeInfo(@TypeOf(raw_fn_output))) {
                else => raw_fn_output,
                .error_union => raw_fn_output catch @panic("Error thrown in a node call!"),
            };
            var node_output = state.arena.allocator().create(NodeOutputs(@"fn")) catch unreachable;
            inline for (@typeInfo(@TypeOf(fn_output)).@"struct".fields) |field| {
                @field(node_output, field.name) = .{ .raw = @field(fn_output, field.name), .is_dirty = true };
            }
            inline for (@typeInfo(@TypeOf(mutable_props)).@"struct".fields) |field| {
                @field(node_output, field.name) = .{ .raw = @field(mutable_props, field.name), .is_dirty = true };
            }
            state.data = @ptrCast(node_output);
            return node_output;
        } else {
            const last_output: *NodeOutputs(@"fn") = @ptrCast(@alignCast(state.data.?));
            inline for (@typeInfo(@TypeOf(last_output.*)).@"struct".fields) |field| {
                @field(last_output, field.name).is_dirty = false;
            }
            return last_output;
        }
    }

    const NodeState = struct {
        arena: std.heap.ArenaAllocator,
        data: ?*anyopaque,
    };

    pub fn build(graph: type) type {
        const Inputs = @field(graph, "Inputs");
        const Outputs = @field(graph, "Outputs");
        const Store = @field(graph, "Store");
        const PartialInputs = PartialFields(Inputs);
        return struct {
            store: DirtyableFields(Store),
            inputs: DirtyableFields(Inputs),
            runtime: Runtime,

            pub fn init(allocator: std.mem.Allocator, inputs: Inputs, store: Store) @This() {
                var result = @This(){
                    .inputs = undefined,
                    .store = undefined,
                    .runtime = .{
                        .allocator = allocator,
                        .node_states = std.StringHashMap(NodeState).init(allocator),
                    },
                };
                inline for (@typeInfo(@TypeOf(inputs)).@"struct".fields) |field| {
                    @field(result.inputs, field.name) = .{ .raw = @field(inputs, field.name), .is_dirty = true };
                }
                inline for (@typeInfo(@TypeOf(store)).@"struct".fields) |field| {
                    @field(result.store, field.name) = .{ .raw = @field(store, field.name), .is_dirty = false };
                }
                return result;
            }

            pub fn update(self: *@This(), partial_inputs: PartialInputs) Outputs {
                inline for (@typeInfo(@TypeOf(partial_inputs)).@"struct".fields) |field| {
                    if (@field(partial_inputs, field.name)) |new_input| {
                        @field(self.inputs, field.name).set(new_input);
                    }
                }
                const result = graph.update(&self.runtime, self.inputs, self.store);
                inline for (@typeInfo(@TypeOf(self.store)).@"struct".fields) |field| {
                    @field(self.store, field.name) = @field(result.store, field.name);
                }
                var outputs: Outputs = undefined;
                inline for (@typeInfo(Outputs).@"struct".fields) |field| {
                    @field(outputs, field.name) = @field(result.outputs, field.name).raw;
                }
                return outputs;
            }
        };
    }
};
