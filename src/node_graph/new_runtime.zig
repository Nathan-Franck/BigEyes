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

pub const GraphStore = DirtyableFields;
pub fn GraphInputs(inputs: type) type {
    return struct {
        data: *inputs,
        polling_fn: PollFn,
        fn pollFn(
            comptime field_tag: std.meta.FieldEnum(inputs),
        ) std.meta.fieldInfo(inputs, field_tag).type {
            unreachable;
        }
        pub const PollFn = @TypeOf(pollFn);
        pub fn build(polling_fn: PollFn, data: *inputs) @This() {
            return @This(){
                .data = data,
                .polling_fn = polling_fn,
            };
        }
        pub fn init(self: @This()) void {
            inline for (@typeInfo(inputs).@"struct".fields, 0..) |field, i| {
                @field(self.data, field.name) = self.polling_fn(@enumFromInt(i));
            }
        }
        pub fn poll(
            self: @This(),
            comptime field_tag: std.meta.FieldEnum(inputs),
        ) Dirtyable(std.meta.fieldInfo(inputs, field_tag).type) {
            const previous = &@field(self.data, @tagName(field_tag));
            const current = self.polling_fn(field_tag);
            defer previous.* = current;
            return .{
                .is_dirty = !std.meta.eql(previous.*, current),
                .raw = current,
            };
        }
    };
}
pub fn GraphOutputs(outputs: type) type {
    return struct {
        fn submitFn(comptime field_tag: std.meta.FieldEnum(outputs), value: std.meta.fieldInfo(outputs, field_tag).type) void {
            _ = value;
            unreachable;
        }
        pub const SubmitFn = @TypeOf(submitFn);
        submit_fn: SubmitFn,
        pub fn init(submit_fn: SubmitFn) @This() {
            return .{ .submit_fn = submit_fn };
        }
        pub fn submit(self: @This(), partial_outputs: PartialFields(DirtyableFields(outputs))) void {
            inline for (@typeInfo(outputs).@"struct".fields, 0..) |field, i| {
                if (@field(partial_outputs, field.name)) |out| {
                    if (out.is_dirty) {
                        self.submit_fn(@enumFromInt(i), out.raw);
                    }
                }
            }
        }
    };
}

pub const Runtime = struct {
    allocator: std.mem.Allocator,
    node_states: std.StringHashMap(NodeState),

    pub fn node(
        self: *@This(),
        comptime src: std.builtin.SourceLocation,
        @"fn": anytype,
        dirtyable_props: NodeInputs(@"fn"),
    ) *NodeOutputs(@"fn") {
        const src_key = std.fmt.comptimePrint("{s}:{d}:{d}", .{ src.file, src.line, src.column });

        // Find existing state for this node.
        const state = if (self.node_states.getPtr(src_key)) |arena| arena else blk: {
            const new_state: NodeState = .{
                .arena = std.heap.ArenaAllocator.init(self.allocator),
                .queried = std.StringHashMap(bool).init(self.allocator),
                .data = null,
            };

            self.node_states.put(src_key, new_state) catch unreachable;
            break :blk self.node_states.getPtr(src_key).?;
        };

        // Discover which properties are mutable inputs - these have to be cloned so they don't affect their parent nodes.
        var mutable_props: MutableProps(@"fn") = undefined;
        inline for (@typeInfo(@TypeOf(mutable_props)).@"struct".fields) |field| {
            const dirtyable_prop = @field(dirtyable_props, field.name);
            @field(mutable_props, field.name) = utils.deepClone(
                @TypeOf(dirtyable_prop.raw),
                state.arena.allocator(),
                dirtyable_prop.raw,
            ) catch unreachable;
        }

        // Fill in the input properties, taking note of if any of them are dirty, then the node is dirty, and we need to re-run the function.
        const Props = ParamsToNodeProps(@TypeOf(@"fn"));
        var props: Props = undefined;
        var is_input_dirty = false;
        inline for (@typeInfo(Props).@"struct".fields) |prop| {
            var dirtyable_prop = @field(dirtyable_props, prop.name);
            const default = dirtyable_prop.raw;
            const input_field = switch (@typeInfo(prop.type)) {
                .@"struct" => blk: {
                    if (utils_node.queryable.getSourceOrNull(prop.type)) |t| {
                        const queried = if (state.queried.getPtr(prop.name)) |queried| queried else queried: {
                            state.queried.put(prop.name, false) catch unreachable;
                            break :queried state.queried.getPtr(prop.name).?;
                        };
                        break :blk utils_node.queryable.Value(t).initQueryable(default, &dirtyable_prop.is_dirty, queried);
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
            // The node is dirty, or there's no data, so let's run the function!
            _ = state.arena.reset(.retain_capacity);

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
            // Just use the existing data from the last time the function had ro run.
            const last_output: *NodeOutputs(@"fn") = @ptrCast(@alignCast(state.data.?));
            inline for (@typeInfo(@TypeOf(last_output.*)).@"struct".fields) |field| {
                @field(last_output, field.name).is_dirty = false;
            }
            return last_output;
        }
    }

    const NodeState = struct {
        arena: std.heap.ArenaAllocator,
        queried: std.StringHashMap(bool),
        data: ?*anyopaque,
    };

    pub fn build(graph: type) type {
        return struct {
            pub const Store = @field(graph, "Store");
            pub const Inputs = @field(graph, "Inputs");
            pub const Outputs = @field(graph, "Outputs");

            pub const InputTag = std.meta.FieldEnum(Inputs);
            pub const OutputTag = std.meta.FieldEnum(Outputs);

            pub fn withHooks(
                poll_fn: GraphInputs(Inputs).PollFn,
                submit_fn: GraphOutputs(Outputs).SubmitFn,
            ) type {
                return struct {
                    store: GraphStore(Store),
                    runtime: Runtime,
                    var data: Inputs = undefined;

                    const inputs = GraphInputs(Inputs).build(poll_fn, &data);
                    const outputs = GraphOutputs(Outputs).init(submit_fn);

                    pub fn init(
                        allocator: std.mem.Allocator,
                        store: Store,
                    ) @This() {
                        inputs.init();
                        var result = @This(){
                            .store = undefined,
                            .runtime = .{
                                .allocator = allocator,
                                .node_states = std.StringHashMap(NodeState).init(allocator),
                            },
                        };
                        inline for (@typeInfo(@TypeOf(store)).@"struct".fields) |field| {
                            @field(result.store, field.name) = .{ .raw = @field(store, field.name), .is_dirty = false };
                        }
                        return result;
                    }

                    pub fn update(self: *@This()) void {
                        self.store = graph.update(&self.runtime, inputs, outputs, self.store);
                    }
                };
            }
        };
    }
};
