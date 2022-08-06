const std = @import("std");
const traits = @import("./traits.zig");

pub const CommandSerializer = struct {
    // 序列号commands
    pub fn serializeCommand(msg: anytype, command: anytype) !void {
        // Serializes an entire command.
        // Callers can expect this function to:
        // 1. Write the number of arguments in the command
        //    (optionally using the Redis.Arguments trait)
        // 2. Write each argument
        //    (optionally using the Redis.Arguments trait)
        //
        // `command` can be:
        // 1. RedisCommand trait
        // 2. RedisArguments trait
        // 3. Zig Tuple
        // 4. Array / Slice
        //
        // Redis.Command types can call this function
        // in order to delegate simple serialization
        // scenarios, the only requirement being that they
        // pass a Zig Tuple or an Array/Slice, and not another
        // reference to themselves (as that would loop forever).
        //
        // As an example, the `commands.GET` command calls this
        // function passing `.{"GET", self.key}` as
        // argument.
        const CmdT = @TypeOf(command);
        // command 类型是command
        // 实现来RedisCommand
        if (comptime traits.isCommand(CmdT)) {
            // 用来序列化
            return CmdT.RedisCommand.serialize(command, CommandSerializer, msg);
        }

        // TODO: decide if this should be removed.
        // Why would someone use Arguments directly?
        if (comptime traits.isArguments(CmdT)) {
            // 可以打印的类型
            try msg.print("*{}\r\n", CmdT.RedisArguments.count(command));
            return CmdT.RedisArguments.serialize(command, CommandSerializer, msg);
        }

        switch (@typeInfo(CmdT)) {
            // 编译错误
            else => {
                @compileLog(CmdT);
                @compileError("unsupported");
            },
            .Struct => {
                // Since we already handled structs that implement the
                // Command trait, the expectation here is that this struct
                // is in fact a Zig Tuple.
                // 不是tuple
                if (!(comptime std.meta.trait.isTuple(CmdT))) {
                    @compileError("Only Zig tuples and Redis.Command types are allowed as argument to send.");
                }

                // Count the number of arguments
                var argNum: usize = 0;
                inline for (std.meta.fields(CmdT)) |field| {
                    // 获取name
                    const arg = @field(command, field.name);
                    // 获取形参
                    const ArgT = @TypeOf(arg);
                    if (comptime traits.isArguments(ArgT)) {
                        // 计算参数个数
                        argNum += ArgT.RedisArguments.count(arg);
                    } else {
                        argNum += switch (@typeInfo(ArgT)) {
                            .Array => |arr| if (arr.child != u8) arg.len else 1,
                            .Pointer => |ptr| switch (ptr.size) {
                                .Slice => if (ptr.child != u8) arg.len else 1,
                                .One => switch (@typeInfo(ptr.child)) {
                                    .Array => |arr| if (arr.child != u8) arg.len else 1,
                                    else => @compileError("unsupported"),
                                },
                                else => @compileError("unsupported"),
                            },
                            // 默认是一
                            else => 1,
                        };
                    }
                }

                // Write the number of arguments
                // std.debug.warn("*{}\r\n", argNum);
                try msg.print("*{}\r\n", .{argNum});

                // Serialize each argument
                inline for (std.meta.fields(CmdT)) |field| {
                    const arg = @field(command, field.name);
                    const ArgT = @TypeOf(arg);
                    if (comptime traits.isArguments(ArgT)) {
                        try ArgT.RedisArguments.serialize(arg, CommandSerializer, msg);
                    } else {
                        // array类型
                        switch (@typeInfo(ArgT)) {
                            .Array => |arr| if (arr.child != u8) {
                                for (arg) |elem| {
                                    if (comptime traits.isArguments(arr.child)) {
                                        try arr.child.RedisArguments.serialize(elem, CommandSerializer, msg);
                                    } else {
                                        try serializeArgument(msg, arr.child, elem);
                                    }
                                }
                            } else {
                                try serializeArgument(msg, ArgT, arg);
                            },
                            .Pointer => |ptr| switch (ptr.size) {
                                .Slice => {
                                    if (ptr.child != u8) {
                                        for (arg) |elem| {
                                            if (comptime traits.isArguments(ptr.child)) {
                                                try ptr.child.RedisArguments.serialize(elem, CommandSerializer, msg);
                                            } else {
                                                try serializeArgument(msg, ptr.child, elem);
                                            }
                                        }
                                    } else {
                                        try serializeArgument(msg, ArgT, arg);
                                    }
                                },
                                .One => switch (@typeInfo(ptr.child)) {
                                    .Array => |arr| {
                                        if (arr.child != u8) {
                                            for (arg) |elem| {
                                                if (comptime traits.isArguments(arr.child)) {
                                                    try arr.child.RedisArguments.serialize(elem, CommandSerializer, msg);
                                                } else {
                                                    try serializeArgument(msg, arr.child, elem);
                                                }
                                            }
                                        } else {
                                            try serializeArgument(msg, ptr.child, arg.*);
                                        }
                                    },
                                    else => @compileError("unsupported"),
                                },
                                else => @compileError("unsupported"),
                            },
                            else => try serializeArgument(msg, ArgT, arg),
                        }
                    }
                }
            },
        }
    }

    // 用来序列化命令
    pub fn serializeArgument(msg: anytype, comptime T: type, val: T) !void {
        // Serializes a single argument.
        // Supports the following types:
        // 1. Strings
        // 2. Numbers
        //
        // Redis.Argument types can use this function
        // in their implementation.
        // Similarly to what happens with Redis.Command types
        // and serializeCommand(), Redis.Argument types
        // can call this function and pass a basic type.
        switch (@typeInfo(T)) {
            .Int,
            .Float,
            .ComptimeInt,
            => {
                // TODO: write a better method
                var buf: [100]u8 = undefined;
                var res = try std.fmt.bufPrint(buf[0..], "{}", .{val});
                // std.debug.warn("${}\r\n{s}\r\n", res.len, res);
                try msg.print("${}\r\n{s}\r\n", .{ res.len, res });
            },
            .ComptimeFloat => {
                // TODO: write a better method, avoid duplication?
                var buf: [100]u8 = undefined;
                var res = try std.fmt.bufPrint(buf[0..], "{}", .{@as(f64, val)});
                // std.debug.warn("${}\r\n{s}\r\n", res.len, res);
                try msg.print("${}\r\n{s}\r\n", .{ res.len, res });
            },
            .Array => {
                // std.debug.warn("${}\r\n{s}\r\n", val.len, val);
                try msg.print("${}\r\n{s}\r\n", .{ val.len, val });
            },
            .Pointer => |ptr| {
                switch (ptr.size) {
                    // .One => {
                    //     switch (@typeInfo(ptr.child)) {
                    //         .Array => {
                    //             const arr = val.*;
                    //             try msg.print("${}\r\n{s}\r\n", .{ arr.len, arr });
                    //             return;
                    //         },
                    //         else => @compileError("unsupported"),
                    //     }
                    // },
                    .Slice => {
                        try msg.print("${}\r\n{s}\r\n", .{ val.len, val });
                    },
                    else => {
                        if ((ptr.size != .Slice or ptr.size != .One) or ptr.child != u8) {
                            @compileLog(ptr.size);
                            @compileLog(ptr.child);
                            @compileError("Type " ++ T ++ " is not supported.");
                        }
                    },
                }
            },
            // 编译错误
            else => @compileError("Type " ++ @typeName(T) ++ " is not supported."),
        }
    }
};
