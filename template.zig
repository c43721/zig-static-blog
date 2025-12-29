const std = @import("std");
const log = std.log.scoped(.template);

pub const Template = @This();

arena: std.mem.Allocator,
buffer: std.ArrayList(u8),
writer: std.ArrayList(u8).Writer,

pub fn create(arena: std.mem.Allocator) !*Template {
    var html = try arena.create(Template);

    html.* = .{
        .arena = arena,
        .buffer = .empty,
        .writer = undefined,
    };

    html.writer = html.buffer.writer(arena);

    return html;
}

fn write_template(template: *Template, source_template: []const u8, replacements: anytype) !void {
    const ReplacementsType = @TypeOf(replacements);
    const replacements_type_info = @typeInfo(ReplacementsType);
    if (replacements_type_info != .@"struct") @compileError("expected struct");

    var unused = std.StringHashMap(void).init(template.arena);
    inline for (replacements_type_info.@"struct".fields) |field| {
        try unused.put(field.name, {});
    }

    var it = std.mem.tokenizeScalar(u8, source_template, '$');
    if (source_template[0] != '$') if (it.next()) |prefix| try template.writer.writeAll(prefix);
    while (it.next()) |chunk| {
        const identifier_len = for (chunk, 0..) |c, index| {
            switch (c) {
                'a'...'z', '_' => {},
                else => break index,
            }
        } else chunk.len;

        const identifier = chunk[0..identifier_len];
        const found = inline for (replacements_type_info.@"struct".fields) |field| {
            if (std.mem.eql(u8, field.name, identifier)) {
                try template.writer.writeAll(switch (field.type) {
                    *Template => @field(replacements, field.name).string(),
                    else => @field(replacements, field.name),
                });
                _ = unused.remove(field.name);
                break true;
            }
        } else false;
        if (!found) {
            log.err("Html.write: identifier '{s}' not found in replacements", .{identifier});
            return error.IdentifierNotFound;
        }

        try template.writer.writeAll(chunk[identifier_len..]);
    }

    if (unused.count() > 0) {
        var unused_it = unused.keyIterator();
        while (unused_it.next()) |unused_identifier| {
            log.err("Html.write: identifier '{s}' not found in template", .{unused_identifier.*});
        }
        return error.UnusedIdentifiers;
    }
}

pub fn to_string(self: *Template) []const u8 {
    return self.buffer.items;
}

pub fn write(arena: std.mem.Allocator, html: []const u8) ![]const u8 {
    const tmpl = @embedFile("template.html");
    var instance = try Template.create(arena);
    try instance.write_template(tmpl, .{ .content = html });
    return instance.to_string();
}
