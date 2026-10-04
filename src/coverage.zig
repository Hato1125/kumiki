const std = @import("std");

// The code points a font has glyphs for.
pub const Coverage = struct {
    // Sorted, with both ends inside. No ranges at all stand for a font that
    // is taken to have every glyph.
    ranges: []const [2]u32 = &.{},

    pub fn deinit(coverage: Coverage, gpa: std.mem.Allocator) void {
        gpa.free(coverage.ranges);
    }

    pub fn has(coverage: Coverage, code_point: u21) bool {
        if (coverage.ranges.len == 0) return true;
        var low: usize = 0;
        var high = coverage.ranges.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            const range = coverage.ranges[middle];
            if (code_point > range[1]) {
                low = middle + 1;
            } else if (code_point < range[0]) {
                high = middle;
            } else {
                return true;
            }
        }
        return false;
    }

    // Reads the cmap table of a TTF or OTF file. The table of the formats
    // that ThorVG draws from is taken: 12 before 4.
    pub fn parse(gpa: std.mem.Allocator, file: []const u8) !Coverage {
        const cmap = try table(file, "cmap");
        var chosen: ?[]const u8 = null;
        for (0..try int(u16, cmap, 2)) |i| {
            const record = 4 + i * 8;
            const platform = try int(u16, cmap, record);
            if (platform != unicode_platform and platform != windows_platform) continue;
            const offset = try int(u32, cmap, record + 4);
            if (offset > cmap.len) return error.Truncated;
            const subtable = cmap[offset..];
            switch (try int(u16, subtable, 0)) {
                12 => {
                    chosen = subtable;
                    break;
                },
                4 => chosen = chosen orelse subtable,
                else => {},
            }
        }
        const subtable = chosen orelse return error.NoUnicodeTable;

        var ranges: std.ArrayList([2]u32) = .empty;
        errdefer ranges.deinit(gpa);
        if (try int(u16, subtable, 0) == 12) {
            for (0..try int(u32, subtable, 12)) |i| {
                const group = 16 + i * 12;
                try ranges.append(gpa, .{ try int(u32, subtable, group), try int(u32, subtable, group + 4) });
            }
        } else {
            const count = try int(u16, subtable, 6) / 2;
            const ends = 14;
            const starts = ends + count * 2 + 2;
            for (0..count) |i| {
                const last = try int(u16, subtable, ends + i * 2);
                // The table closes with a segment for this code alone.
                if (last == 0xffff) break;
                try ranges.append(gpa, .{ try int(u16, subtable, starts + i * 2), last });
            }
        }
        return .{ .ranges = try ranges.toOwnedSlice(gpa) };
    }

    const unicode_platform = 0;
    const windows_platform = 3;

    fn table(file: []const u8, tag: *const [4]u8) ![]const u8 {
        for (0..try int(u16, file, 4)) |i| {
            const record = 12 + i * 16;
            if (record + 4 > file.len) return error.Truncated;
            if (!std.mem.eql(u8, file[record..][0..4], tag)) continue;
            const offset = try int(u32, file, record + 8);
            const length = try int(u32, file, record + 12);
            if (@as(u64, offset) + length > file.len) return error.Truncated;
            return file[offset..][0..length];
        }
        return error.NoTable;
    }

    fn int(comptime T: type, bytes: []const u8, offset: usize) !T {
        if (offset + @sizeOf(T) > bytes.len) return error.Truncated;
        return std.mem.readInt(T, bytes[offset..][0..@sizeOf(T)], .big);
    }
};
