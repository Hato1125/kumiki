const std = @import("std");
const ui = @import("katagi");

const Fake = @import("Fake.zig");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const gpa = std.testing.allocator;
const options: Fake.Options = .{ .font = "assets/NotoSansJP-Regular.otf" };

fn Scene(comptime Root: type) type {
    return ui.Scene(Fake, Root);
}

fn frame(s: anytype) !void {
    try expect(try s.frame());
}

fn centerOf(node: anytype) ui.Point {
    const at = ui.offsetOf(node);
    return .{ .x = at.x + node.size.width / 2, .y = at.y + node.size.height / 2 };
}

fn press(s: anytype, key: u32, mod: u16) !void {
    s.impl.push(.{ .key = .{ .key = key, .mod = mod, .down = true } });
    s.impl.push(.{ .key = .{ .key = key, .mod = mod, .down = false } });
    try frame(s);
}

fn button(s: anytype, down: bool, at: ui.Point) void {
    s.impl.push(.{ .button = .{ .button = .left, .down = down, .x = at.x, .y = at.y } });
}

fn click(s: anytype, at: ui.Point) !void {
    button(s, true, at);
    button(s, false, at);
    try frame(s);
}

// What the views below did, one letter per step.
var trace_buf: [16]u8 = undefined;
var trace: []const u8 = "";

fn note(step: u8) void {
    trace_buf[trace.len] = step;
    trace = trace_buf[0 .. trace.len + 1];
}

fn Button(comptime action: anytype) type {
    return struct {
        title: []const u8,

        const Self = @This();

        pub const view = ui.show(label).padding(8).tap(action);

        fn label(self: *const Self) ui.Text {
            return ui.text(self.title);
        }
    };
}

const Counter = struct {
    count: i32 = 0,

    pub const view = ui.row(.{
        Button(decrement){ .title = "-1" },
        Button(increment){ .title = "+1" },
    }).gap(8);

    fn increment(self: *Counter) void {
        self.count += 1;
    }

    fn decrement(self: *Counter) void {
        self.count -= 1;
    }
};

test "keys press the focused button" {
    var s: Scene(Counter) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    const row = &s.root.children[0];
    const dec = &row.children[0].children[0];
    const inc = &row.children[1].children[0];

    try press(&s, ui.keys.tab, 0);
    try expectEqual(dec.id, s.state.focus.id());
    try press(&s, ui.keys.enter, 0);
    try press(&s, ui.keys.enter, 0);
    try expectEqual(-2, s.root.widget.count);

    try press(&s, ui.keys.tab, 0x0001);
    try expectEqual(inc.id, s.state.focus.id());
    try press(&s, ui.keys.space, 0);
    try expectEqual(-1, s.root.widget.count);
}

test "a tap fires only when released on the tap it was pressed on" {
    var s: Scene(Counter) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    const row = &s.root.children[0];
    const dec = &row.children[0].children[0];
    const inc = &row.children[1].children[0];
    const on_dec = centerOf(dec);
    const on_inc = centerOf(inc);

    button(&s, true, on_dec);
    try frame(&s);
    try expectEqual(dec.id, s.state.press.id());
    try expectEqual(dec.id, s.state.focus.id());
    s.impl.push(.{ .pointer_move = on_inc });
    button(&s, false, on_inc);
    try frame(&s);
    try expectEqual(0, s.state.press.id());
    try expectEqual(0, s.root.widget.count);

    try click(&s, on_inc);
    try expectEqual(1, s.root.widget.count);
    try expectEqual(inc.id, s.state.focus.id());

    // Clicking empty space keeps the focus.
    try click(&s, .{ .x = s.size.width - 1, .y = s.size.height - 1 });
    try expectEqual(inc.id, s.state.focus.id());

    try press(&s, ui.keys.escape, 0);
    try expectEqual(0, s.state.focus.id());
}

var builds: [2]u32 = .{ 0, 0 };

fn Probe(comptime index: usize) type {
    return struct {
        pub const view = ui.show(label).padding(8);

        fn label(cx: ui.Context) ui.Text {
            builds[index] += 1;
            return ui.text(if (cx.hovered()) "over" else "away");
        }
    };
}

const Probes = struct {
    pub const view = ui.row(.{ Probe(0){}, Probe(1){} });
};

test "hovering builds only the components the pointer enters or leaves" {
    var s: Scene(Probes) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    builds = .{ 0, 0 };

    const first = &s.root.children[0].children[0];
    const second = &s.root.children[0].children[1];
    const label = &first.children[0].children[0];
    s.impl.push(.{ .pointer_move = centerOf(first) });
    try frame(&s);
    try expectEqual([2]u32{ 1, 0 }, builds);
    try expectEqualStrings("over", label.widget.content);

    s.impl.push(.{ .pointer_move = centerOf(second) });
    try frame(&s);
    try expectEqual([2]u32{ 2, 1 }, builds);
    try expectEqualStrings("away", label.widget.content);
    try expect(!s.busy());
}

const Item = struct {
    id: u32,
    done: bool = false,
};

const Row = struct {
    item: Item,

    pub const view = ui.show(label).padding(4).tap(App.toggle);

    fn label(self: *const Row, cx: ui.Context) ui.Text {
        return ui.text(cx.print("{d}{s}", .{ self.item.id, if (self.item.done) " done" else "" }));
    }
};

const App = struct {
    items: std.ArrayList(Item) = .empty,

    pub const view = ui.list(rows, row);

    fn rows(self: *const App) []const Item {
        return self.items.items;
    }

    fn row(item: Item) Row {
        return .{ .item = item };
    }

    // Given to the tap of a row, so `self` is the App around the row and `r`
    // is the row itself.
    fn toggle(self: *App, r: *const Row) void {
        for (self.items.items) |*item| {
            if (item.id == r.item.id) item.done = !item.done;
        }
    }
};

test "keyed rows keep their node, focus and position through changes" {
    var items: std.ArrayList(Item) = .empty;
    defer items.deinit(gpa);
    try items.appendSlice(gpa, &.{ .{ .id = 1 }, .{ .id = 2 }, .{ .id = 3 } });

    var s: Scene(App) = try .init(gpa, options, .{ .items = items });
    defer s.deinit();
    try frame(&s);

    const list = &s.root.children[0];
    const second = list.children.items[1].children[0].id;

    try press(&s, ui.keys.tab, 0);
    try press(&s, ui.keys.tab, 0);
    try expectEqual(second, s.state.focus.id());
    try press(&s, ui.keys.enter, 0);
    try expect(s.root.widget.items.items[1].done);
    const label = &list.children.items[1].children[0].children[0].children[0];
    try expectEqualStrings("2 done", label.widget.content);

    // Reverse the rows: the focused row moves but stays the same node.
    std.mem.reverse(Item, s.root.widget.items.items);
    s.root.dirty = true;
    try frame(&s);
    try expectEqual(second, list.children.items[1].children[0].id);
    try expectEqual(second, s.state.focus.id());

    const first = list.children.items[2].children[0].id;
    _ = s.root.widget.items.orderedRemove(1);
    s.root.dirty = true;
    try frame(&s);
    try expectEqual(2, list.children.items.len);
    try expectEqual(first, list.children.items[1].children[0].id);
    try expectEqual(0, s.state.focus.id());
}

const Toggle = struct {
    on: bool = false,

    pub const view = ui.show(knob)
        .animation(.{ .duration = 1, .curve = .linear })
        .tap(flip);

    fn knob(self: *const Toggle) ui.Rect {
        return ui.rect().fill(if (self.on) .{ .r = 200 } else .{ .r = 0 });
    }

    fn flip(self: *Toggle) void {
        self.on = !self.on;
    }
};

test "animation moves to the new value over its duration" {
    var s: Scene(Toggle) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    const knob = &s.root.children[0].children[0].children[0];
    try press(&s, ui.keys.tab, 0);
    s.impl.push(.{ .key = .{ .key = ui.keys.enter, .down = true } });
    s.impl.seconds = 10;
    try frame(&s);
    try expectEqual(0, knob.widget.fill_color.r);
    try expect(s.busy());
    s.impl.seconds = 10.5;
    try frame(&s);
    try expectEqual(100, knob.widget.fill_color.r);
    s.impl.seconds = 11;
    try frame(&s);
    try expectEqual(200, knob.widget.fill_color.r);
    try expect(!s.busy());
}

const Switch = struct {
    on: bool = false,

    pub const view = ui.text("switch").padding(8).tap(flip);

    fn flip(self: *Switch) void {
        self.on = !self.on;
    }
};

const Panel = struct {
    pub const view = ui.row(.{Switch{}});
};

test "a component written in a view keeps its state when its parent is built again" {
    var s: Scene(Panel) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    const switch_node = &s.root.children[0].children[0];
    // The press path enters and leaves Panel, so the click builds it again.
    try click(&s, centerOf(&switch_node.children[0]));
    try expect(switch_node.widget.on);
}

const Notes = struct {
    lines: std.ArrayList(u32) = .empty,

    pub const view = ui.text("add").padding(8).tap(add);

    pub fn mount(self: *Notes, cx: ui.Context) void {
        self.lines.append(cx.gpa, 0) catch @panic("out of memory");
    }

    pub fn unmount(self: *Notes, cx: ui.Context) void {
        self.lines.deinit(cx.gpa);
    }

    fn add(self: *Notes, cx: ui.Context) void {
        self.lines.append(cx.gpa, 1) catch @panic("out of memory");
    }
};

const Desk = struct {
    pub const view = ui.row(.{Notes{}});
};

// std.testing.allocator fails these tests when `unmount` does not run.
test "a nested component allocates in mount and frees in unmount" {
    var s: Scene(Desk) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    const notes = &s.root.children[0].children[0];
    try expectEqual(1, notes.widget.lines.items.len);
    for (0..40) |_| try click(&s, centerOf(&notes.children[0]));
    try expectEqual(41, notes.widget.lines.items.len);
}

test "the scene frees what the root allocates" {
    var s: Scene(Notes) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    for (0..40) |_| try click(&s, centerOf(&s.root.children[0]));
    try expectEqual(41, s.root.widget.lines.items.len);
}

const Ring = struct {
    pub const view = ui.show(label).padding(8).tap(ignore);

    fn label(cx: ui.Context) ui.Text {
        return ui.text(if (cx.focusVisible()) "ring" else "plain");
    }

    fn ignore() void {}
};

test "the focus is visible after the keyboard was used and hidden after a click" {
    var s: Scene(Ring) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    const label = &s.root.children[0].children[0].children[0];

    try click(&s, centerOf(label));
    try expect(s.state.focus.id() != 0);
    try expectEqualStrings("plain", label.widget.content);

    // Shift alone is no keyboard use.
    try press(&s, 0x400000e1, 0x0001);
    try expectEqualStrings("plain", label.widget.content);

    try press(&s, ui.keys.space, 0);
    try expectEqualStrings("ring", label.widget.content);

    try click(&s, centerOf(label));
    try expectEqualStrings("plain", label.widget.content);

    try press(&s, ui.keys.tab, 0);
    try expectEqualStrings("ring", label.widget.content);
}

const Palette = struct { ink: u8 };

const Swatch = struct {
    pub const view = ui.show(chip).frame(.{ .width = 20, .height = 20 }).tap(darken);

    fn chip(palette: *const Palette) ui.Rect {
        return ui.rect().fill(.{ .r = palette.ink });
    }

    fn darken(palette: *Palette) void {
        palette.ink = 0;
    }
};

const Shelf = struct {
    pub const view = ui.row(.{Swatch{}});
};

const Studio = struct {
    palette: Palette = .{ .ink = 200 },

    pub const view = ui.row(.{Shelf{}});
};

test "a parameter that is no component receives the field of that type from the nearest component holding one" {
    var s: Scene(Studio) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    const swatch = &s.root.children[0].children[0].children[0].children[0];
    const chip = &swatch.children[0].children[0].children[0];
    try expectEqual(200, chip.widget.fill_color.r);

    // Changing the field builds its holder and everything inside again.
    try click(&s, centerOf(chip));
    try expectEqual(0, s.root.widget.palette.ink);
    try expectEqual(0, chip.widget.fill_color.r);
}

test "text takes its line height from the style and grows with tracking" {
    try ui.startup(options.font);
    defer ui.shutdown();

    const plain = ui.text("katagi");
    const natural = plain.measure(.{});
    try expectEqual(40, plain.lineHeight(40).measure(.{}).height);
    try std.testing.expectApproxEqAbs(natural.width + 6 * 2, plain.tracking(2).measure(.{}).width, 2.5);

    const narrow: ui.Constraint = .{ .max = .{ .width = 30, .height = ui.inf } };
    const lines = plain.measure(narrow).height / natural.height;
    try expect(lines >= 2);
    try expectEqual(40 * lines, plain.lineHeight(40).measure(narrow).height);
}

const Layout = struct {
    pub const view = ui.column(.{
        ui.row(.{
            ui.rect().frame(.{ .width = 40, .height = 10 }),
            ui.rect().flex(1),
            ui.rect().flex(3),
        }).gap(10).frame(.{ .height = 10 }),
        ui.text("a line of text that is much too long to fit").frame(.{ .width = 60 }),
        ui.text("x").padding(.{ .x = 5, .top = 2 }),
    });
};

test "layout" {
    var s: Scene(Layout) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    const column = &s.root.children[0];
    const row = &column.children[0].children[0];
    // 400 - 40 - 2 * 10 = 340 is shared 1 : 3.
    try expectEqual(85, row.children[1].size.width);
    try expectEqual(255, row.children[2].size.width);
    try expectEqual(40 + 10 + 85 + 10, ui.offsetOf(&row.children[2]).x);

    const line_height = ui.text("x").measure(.{}).height;
    const wrapped = &column.children[1];
    try expect(wrapped.children[0].size.width <= 60);
    try expect(wrapped.size.height >= line_height * 3);

    const padded = &column.children[2];
    try expectEqual(padded.children[0].size.width + 10, padded.size.width);
    try expectEqual(padded.offset.y + 2, padded.children[0].offset.y);
}

const Tone = struct { level: u8 };

var tone_builds: u32 = 0;

const ToneLabel = struct {
    pub const view = ui.show(label);

    fn label(tone: Tone, cx: ui.Context) ui.Text {
        tone_builds += 1;
        return ui.text(cx.print("{d}", .{tone.level}));
    }
};

// Provides one more while the pointer is over it, when it reacts at all.
fn Toned(comptime reacts: bool) type {
    return struct {
        base: u8,

        const Self = @This();

        pub const view = ui.row(.{ ui.show(own).padding(8), ToneLabel{} });

        pub fn provide(self: *const Self, cx: ui.Context) Tone {
            return .{ .level = self.base + @intFromBool(reacts and cx.hovered()) };
        }

        fn own(tone: *const Tone, cx: ui.Context) ui.Text {
            return ui.text(cx.print("own {d}", .{tone.level}));
        }
    };
}

const Tones = struct {
    // The nearest component that holds or provides the type wins, so this
    // one reaches neither label.
    tone: Tone = .{ .level = 9 },

    pub const view = ui.column(.{ Toned(true){ .base = 1 }, Toned(false){ .base = 5 } });
};

test "a component provides a value to the functions inside it, and what is inside is built again only when the value changes" {
    var s: Scene(Tones) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    tone_builds = 0;

    const first = &s.root.children[0].children[0];
    const second = &s.root.children[0].children[1];
    const own = &first.children[0].children[0];
    const label = &first.children[0].children[1].children[0];
    try expectEqualStrings("own 1", own.children[0].widget.content);
    try expectEqualStrings("1", label.widget.content);
    try expectEqualStrings("5", second.children[0].children[1].children[0].widget.content);

    // The pointer is over the first component, but not over the label in it.
    s.impl.push(.{ .pointer_move = centerOf(own) });
    try frame(&s);
    try expectEqualStrings("own 2", own.children[0].widget.content);
    try expectEqualStrings("2", label.widget.content);
    try expectEqual(1, tone_builds);

    // The second one is built again and provides what it did before.
    s.impl.push(.{ .pointer_move = centerOf(&second.children[0].children[0]) });
    try frame(&s);
    try expectEqualStrings("1", label.widget.content);
    try expectEqual(2, tone_builds);
    try expect(!s.busy());
}

const Minimums = struct {
    pub const view = ui.column(.{
        ui.text("x").frame(.{ .min_width = 120, .min_height = 40 }),
        ui.text("x").frame(.{ .width = 60, .min_width = 60 }),
        ui.text("x").frame(.{ .width = 60, .min_width = 500 }),
    });
};

test "a frame tells its child to be no smaller than its minimum, as far as the space goes" {
    var s: Scene(Minimums) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    const rows = &s.root.children[0].children;
    try expectEqual(ui.Extent{ .width = 120, .height = 40 }, rows[0].children[0].size);
    try expectEqual(ui.Extent{ .width = 120, .height = 40 }, rows[0].size);
    // With the same width it is fixed.
    try expectEqual(60, rows[1].children[0].size.width);
    try expectEqual(60, rows[2].children[0].size.width);
}

// Overwrites memory before it is freed, so that a test notices a string that
// is read after its arena is gone.
const poisoning: std.mem.Allocator = .{ .ptr = &trace_buf, .vtable = &.{
    .alloc = Poison.alloc,
    .resize = Poison.resize,
    .remap = Poison.remap,
    .free = Poison.free,
} };

const Poison = struct {
    const Alignment = std.mem.Alignment;

    fn alloc(_: *anyopaque, len: usize, alignment: Alignment, ret_addr: usize) ?[*]u8 {
        return gpa.rawAlloc(len, alignment, ret_addr);
    }

    fn resize(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) bool {
        return gpa.rawResize(memory, alignment, new_len, ret_addr);
    }

    fn remap(_: *anyopaque, memory: []u8, alignment: Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        return gpa.rawRemap(memory, alignment, new_len, ret_addr);
    }

    fn free(_: *anyopaque, memory: []u8, alignment: Alignment, ret_addr: usize) void {
        @memset(memory, 0xaa);
        gpa.rawFree(memory, alignment, ret_addr);
    }
};

const Tag = struct {
    name: []const u8,

    pub const view = ui.show(shade);

    fn shade(self: *const Tag) ui.Rect {
        return ui.rect().fill(if (self.name[0] == 'h') .white else .black);
    }
};

const Host = struct {
    pub const view = ui.show(tag).frame(.{ .width = 50, .height = 50 });

    // Both strings have the same length, so the new one lands where the old
    // one was if the old one is given up too early.
    fn tag(cx: ui.Context) Tag {
        return .{ .name = cx.print("{s}", .{if (cx.hovered()) "hot!" else "cold"}) };
    }
};

test "a component returned by a function is built again when its string changes" {
    var s: Scene(Host) = try .init(poisoning, options, .{});
    defer s.deinit();
    try frame(&s);

    const tag = &s.root.children[0].children[0];
    try expectEqual(0, tag.children[0].widget.fill_color.r);
    s.impl.push(.{ .pointer_move = centerOf(tag) });
    try frame(&s);
    try frame(&s);
    try expectEqualStrings("hot!", tag.widget.name);
    try expectEqual(255, tag.children[0].widget.fill_color.r);
}

const Badge = struct {
    label: []const u8,

    pub const view = ui.show(text).animation(.{});

    fn text(self: *const Badge) ui.Text {
        return ui.text(self.label);
    }
};

const Board = struct {
    pub const view = ui.show(badge).padding(8);

    fn badge(cx: ui.Context) Badge {
        return .{ .label = cx.print("{d}", .{42}) };
    }
};

test "a child shows the newer string of its parent and does not animate when the content is the same" {
    var s: Scene(Board) = try .init(poisoning, options, .{});
    defer s.deinit();
    try frame(&s);

    const badge = &s.root.children[0].children[0];
    const text = &badge.children[0].children[0];
    // Over the padding, so that the pointer enters Board alone.
    s.impl.push(.{ .pointer_move = .{ .x = 2, .y = 2 } });
    try frame(&s);
    try frame(&s);
    try expect(badge.widget.label.ptr == text.widget.content.ptr);
    try expectEqualStrings("42", text.widget.content);
    try expect(!s.busy());
}

const Caption = struct {
    taps: u32 = 0,

    pub const view = ui.show(label).animation(.{}).tap(count);

    fn label(cx: ui.Context) ui.Text {
        return ui.text(cx.print("{s}", .{"same"}));
    }

    fn count(self: *Caption) void {
        self.taps += 1;
    }
};

test "an animated view keeps a string that is formatted again with the same content" {
    var s: Scene(Caption) = try .init(poisoning, options, .{});
    defer s.deinit();
    try frame(&s);

    const label = &s.root.children[0].children[0].children[0];
    for (0..3) |_| try click(&s, centerOf(label));
    try expectEqual(3, s.root.widget.taps);
    try expectEqualStrings("same", label.widget.content);
}

const Vanish = struct {
    presses: u32 = 0,

    pub const view = ui.when(unpressed, ui.text("go").padding(8).tap(go), ui.text("gone"));

    fn unpressed(self: *const Vanish) bool {
        return self.presses == 0;
    }

    fn go(self: *Vanish) void {
        self.presses += 1;
    }
};

test "a tap that when hides loses the focus and takes no more keys" {
    var s: Scene(Vanish) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    try press(&s, ui.keys.tab, 0);
    try expect(s.state.focus.id() != 0);
    try press(&s, ui.keys.enter, 0);
    try expectEqual(1, s.root.widget.presses);
    try expectEqual(0, s.state.focus.id());

    try press(&s, ui.keys.enter, 0);
    try expectEqual(1, s.root.widget.presses);
}

const Spread = struct {
    wide: bool = false,
    values: [2]u8 = .{ 1, 2 },

    pub const view = ui.column(.{ ui.show(rows), ui.text("wide").tap(widen) });

    const Rows = @TypeOf(ui.list(source, row));

    fn rows(self: *const Spread) Rows {
        return ui.list(source, row).gap(if (self.wide) 20 else 2);
    }

    fn source(self: *const Spread) []const u8 {
        return &self.values;
    }

    fn row(_: u8) ui.Text {
        return ui.text("row");
    }

    fn widen(self: *Spread) void {
        self.wide = true;
    }
};

test "a list returned by a function takes its new settings and keeps its rows" {
    var s: Scene(Spread) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    const list = &s.root.children[0].children[0];
    const rows = list.children.items;
    const second = rows[1].id;
    const height = rows[0].size.height;
    try expectEqual(rows[0].offset.y + height + 2, rows[1].offset.y);

    try press(&s, ui.keys.tab, 0);
    try press(&s, ui.keys.enter, 0);
    try expect(s.root.widget.wide);
    try expectEqual(second, list.children.items[1].id);
    try expectEqual(rows[0].offset.y + height + 20, list.children.items[1].offset.y);
}

// A primitive of the test's own, without modifiers until it is wrapped.
const Ink = struct {
    pub fn measure(_: Ink, c: ui.Constraint) ui.Extent {
        return c.constrain(.{ .width = 30, .height = 10 });
    }

    pub fn paint(_: Ink, _: ui.Painter) void {
        note('i');
    }
};

const Outline = struct {
    pub fn beginPaint(_: Outline, _: ui.Painter) void {
        note('<');
    }

    pub fn endPaint(_: Outline, _: ui.Painter) void {
        note('>');
    }
};

const Sketch = struct {
    pub const view = ui.column(.{ui.wrap(Ink{}).with(Outline{})});
};

test "a config that only paints draws around its child and keeps its layout" {
    var s: Scene(Sketch) = try .init(gpa, options, .{});
    defer s.deinit();

    // Nothing here draws with the canvas, so it needs no OpenGL.
    var blank: ui.Canvas = undefined;
    s.impl.canvas = &blank;
    trace = "";
    try frame(&s);
    try expectEqualStrings("<i>", trace);

    const outlined = &s.root.children[0].children[0];
    const ink = &outlined.children[0].children[0];
    try expectEqual(ui.Extent{ .width = 30, .height = 10 }, outlined.size);
    try expectEqual(ink.offset, ui.offsetOf(outlined));
}

var marked: ui.Bounds = .{};

const Mark = struct {
    pub fn beginPaint(_: Mark, p: ui.Painter) void {
        marked = p.bounds;
    }
};

const Moved = struct {
    taps: u32 = 0,

    pub const view = ui.column(.{
        ui.wrap(Ink{}).with(Mark{}).tap(count).padding(.{ .left = 7, .top = 9 }),
    });

    fn count(self: *Moved) void {
        self.taps += 1;
    }
};

test "a node that keeps no offset is painted and hit where its child is" {
    var s: Scene(Moved) = try .init(gpa, options, .{});
    defer s.deinit();

    // Nothing here draws with the canvas, so it needs no OpenGL.
    var blank: ui.Canvas = undefined;
    s.impl.canvas = &blank;
    trace = "";
    try frame(&s);
    try expectEqual(ui.Bounds{ .x = 7, .y = 9, .w = 30, .h = 10 }, marked);

    try click(&s, .{ .x = 3, .y = 3 });
    try expectEqual(0, s.root.widget.taps);
    try click(&s, .{ .x = 8, .y = 10 });
    try expectEqual(1, s.root.widget.taps);
}

const Inset = struct {
    by: f32,

    pub fn measure(inset: Inset, child: anytype, c: ui.Constraint) ui.Extent {
        const size = ui.measure(child, c.deflate(inset.by, inset.by));
        return .{ .width = size.width + inset.by, .height = size.height + inset.by };
    }

    pub fn layout(inset: Inset, child: anytype, at: ui.Point, size: ui.Extent) void {
        std.debug.assert(size.width == child.size.width + inset.by);
        ui.layout(child, .{ .x = at.x + inset.by, .y = at.y + inset.by });
    }
};

const Shifted = struct {
    taps: u32 = 0,

    pub const view = ui.column(.{
        ui.rect().frame(.{ .width = 20, .height = 10 }).with(Inset{ .by = 5 }).padding(2).tap(count),
    });

    fn count(self: *Shifted) void {
        self.taps += 1;
    }
};

test "a config that measures and places its child takes further modifiers" {
    var s: Scene(Shifted) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    const padded = &s.root.children[0].children[0].children[0];
    const inset = &padded.children[0];
    const framed = &inset.children[0];
    try expectEqual(ui.Extent{ .width = 25, .height = 15 }, inset.size);
    try expectEqual(ui.Extent{ .width = 29, .height = 19 }, padded.size);
    try expectEqual(inset.offset.x + 5, framed.offset.x);
    try expectEqual(inset.offset.y + 5, framed.offset.y);

    try click(&s, centerOf(framed));
    try expectEqual(1, s.root.widget.taps);
}

const Slide = struct {
    far: bool = false,

    pub const view = ui.show(shifted)
        .animation(.{ .duration = 1, .curve = .linear })
        .tap(leave);

    const Face = @TypeOf(ui.rect().frame(.{}).with(Inset{ .by = 0 }));

    fn shifted(self: *const Slide) Face {
        return ui.rect().frame(.{ .width = 10, .height = 10 }).with(Inset{ .by = if (self.far) 20 else 0 });
    }

    fn leave(self: *Slide) void {
        self.far = true;
    }
};

test "animation interpolates the values of a config" {
    var s: Scene(Slide) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    const inset = &s.root.children[0].children[0].children[0];
    try click(&s, centerOf(inset));
    s.impl.seconds = 0.5;
    try frame(&s);
    try expectEqual(10, inset.widget.by);
    try expectEqual(inset.offset.x + 10, inset.children[0].offset.x);
}

const Inner = struct {
    pub const view = ui.show(label);

    pub fn mount() void {
        note('m');
    }

    pub fn unmount() void {
        note('u');
    }

    fn label() ui.Text {
        note('b');
        return ui.text("inner");
    }
};

const Outer = struct {
    pub const view = ui.column(.{ ui.show(title), Inner{} });

    pub fn mount() void {
        note('M');
    }

    pub fn unmount() void {
        note('U');
    }

    fn title() ui.Text {
        note('B');
        return ui.text("outer");
    }
};

test "mount runs before the view is built and unmount after that of the components inside" {
    trace = "";
    var s: Scene(Outer) = try .init(gpa, options, .{});
    try expectEqualStrings("MBmb", trace);
    s.deinit();
    try expectEqualStrings("MBmbuU", trace);
}

const Sum = struct { value: u32 };

fn sum(a: u32, b: u32) Sum {
    return .{ .value = a + b };
}

// Lets a test decide when a function in the background ends.
var gate: std.atomic.Value(bool) = .init(false);

fn sumLater(a: u32, b: u32) Sum {
    while (!gate.load(.acquire)) std.atomic.spinLoopHint();
    return sum(a, b);
}

// Advances frames until no function is left in the background.
fn settle(s: anytype) !void {
    for (0..10_000_000) |_| {
        if (s.state.tasks.first == null) return;
        try frame(s);
        std.Thread.yield() catch {};
    }
    return error.StillRunning;
}

const Adder = struct {
    total: u32 = 0,
    waiting: bool = false,

    pub const view = ui.show(label).padding(8).tap(start);

    fn label(self: *const Adder, cx: ui.Context) ui.Text {
        return ui.text(cx.print("{d}", .{self.total}));
    }

    fn start(self: *Adder, cx: ui.Context) void {
        self.waiting = true;
        cx.spawn(sum, .{ 20, 22 });
    }

    pub fn receive(self: *Adder, result: Sum) void {
        self.waiting = false;
        self.total = result.value;
    }
};

test "a function spawned in the background hands its result to receive, which builds the component again" {
    var s: Scene(Adder) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    const label = &s.root.children[0].children[0].children[0];
    try click(&s, centerOf(label));
    try settle(&s);
    try expect(!s.root.widget.waiting);
    try expectEqual(42, s.root.widget.total);
    try expectEqualStrings("42", label.widget.content);
}

const Eager = struct {
    total: u32 = 0,

    pub const view = ui.text("eager");

    pub fn mount(cx: ui.Context) void {
        cx.spawn(sum, .{ 2, 3 });
    }

    pub fn receive(self: *Eager, result: Sum) void {
        self.total = result.value;
    }
};

test "a function spawned in mount, before the scene is in its place, is received" {
    var s: Scene(Eager) = try .init(gpa, options, .{});
    defer s.deinit();
    try settle(&s);
    try expectEqual(5, s.root.widget.total);
}

const Hand = struct {
    pub const view = ui.text("work").padding(8).tap(start);

    fn start(cx: ui.Context) void {
        cx.spawn(sum, .{ 1, 2 });
    }
};

const Foreman = struct {
    total: u32 = 0,

    pub const view = ui.row(.{Hand{}});

    pub fn receive(self: *Foreman, result: Sum) void {
        self.total = result.value;
    }
};

test "a result goes to the nearest component around the spawning one that receives its type" {
    var s: Scene(Foreman) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    try click(&s, centerOf(&s.root.children[0].children[0]));
    try settle(&s);
    try expectEqual(3, s.root.widget.total);
}

var chores_done: u32 = 0;

const Chore = struct {
    pub const view = ui.text("chore").padding(4).tap(start);

    fn start(cx: ui.Context) void {
        cx.spawn(sumLater, .{ 3, 4 });
    }

    pub fn receive(_: *Chore, _: Sum) void {
        chores_done += 1;
    }
};

const Chores = struct {
    count: usize = 1,

    pub const view = ui.list(numbers, chore);

    const all = [_]u32{ 1, 2 };

    fn numbers(self: *const Chores) []const u32 {
        return all[0..self.count];
    }

    fn chore(_: u32) Chore {
        return .{};
    }
};

test "the result for a component that is gone is dropped" {
    gate.store(false, .release);
    chores_done = 0;
    var s: Scene(Chores) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    try click(&s, centerOf(&s.root.children[0].children.items[0]));
    try expect(s.state.tasks.first != null);
    s.root.widget.count = 0;
    s.root.dirty = true;
    try frame(&s);
    try expectEqual(0, s.root.children[0].children.items.len);

    gate.store(true, .release);
    try settle(&s);
    try expectEqual(0, chores_done);
}

test "the scene waits for the functions that still run when it ends" {
    gate.store(false, .release);
    var s: Scene(Chores) = try .init(gpa, options, .{});
    try frame(&s);
    try click(&s, centerOf(&s.root.children[0].children.items[0]));
    gate.store(true, .release);
    s.deinit();
}

const Parting = struct {
    pub const view = ui.text("parting");

    pub fn unmount(cx: ui.Context) void {
        cx.spawn(sum, .{ 1, 1 });
    }
};

// std.testing.allocator fails this test when the function outlives the scene.
test "the scene also waits for a function spawned in unmount" {
    var s: Scene(Parting) = try .init(gpa, options, .{});
    try frame(&s);
    s.deinit();
}

var lent: Sum = .{ .value = 9 };

fn lend() *Sum {
    return &lent;
}

const Borrower = struct {
    total: u32 = 0,

    pub const view = ui.text("borrow");

    pub fn mount(cx: ui.Context) void {
        cx.spawn(lend, .{});
    }

    pub fn receive(self: *Borrower, result: *Sum) void {
        self.total = result.value;
    }
};

test "a function in the background may return a pointer" {
    var s: Scene(Borrower) = try .init(gpa, options, .{});
    defer s.deinit();
    try settle(&s);
    try expectEqual(9, s.root.widget.total);
}

const Entry = struct {
    text: std.ArrayList(u8) = .empty,
    composing: usize = 0,

    pub const view = ui.show(label).padding(4).input(typed).key(edit);

    pub fn unmount(self: *Entry, cx: ui.Context) void {
        self.text.deinit(cx.gpa);
    }

    fn label(self: *const Entry, cx: ui.Context) ui.Text {
        return ui.text(cx.print("{s}", .{self.text.items}));
    }

    fn typed(self: *Entry, input: ui.TextInput, cx: ui.Context) void {
        self.composing = if (input.composing) input.text.len else 0;
        if (input.composing) return;
        self.text.appendSlice(cx.gpa, input.text) catch @panic("out of memory");
    }

    fn edit(self: *Entry, key: ui.KeyPress) bool {
        if (!key.down or key.key != ui.keys.backspace or self.text.items.len == 0) return false;
        _ = self.text.pop();
        return true;
    }
};

test "typed text reaches the focused input, which asks the implementation for it while it has the focus" {
    var s: Scene(Entry) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    try expectEqual(null, s.impl.typing);

    // The key handler around the input shares its stop.
    const field = &s.root.children[0].children[0];
    const label = &field.children[0].children[0];
    try press(&s, ui.keys.tab, 0);
    try expectEqual(field.id, s.state.focus.id());
    try press(&s, ui.keys.tab, 0);
    try expectEqual(field.id, s.state.focus.id());
    try expectEqual(ui.Bounds{ .x = 0, .y = 0, .w = 400, .h = 300 }, s.impl.typing.?);

    s.impl.push(.{ .text = .{ .text = "か", .composing = true } });
    try frame(&s);
    try expectEqual(3, s.root.widget.composing);
    try expectEqualStrings("", label.widget.content);

    s.impl.push(.{ .text = .{ .text = "ab" } });
    try frame(&s);
    try expectEqual(0, s.root.widget.composing);
    try expectEqualStrings("ab", label.widget.content);

    try press(&s, ui.keys.backspace, 0);
    try expectEqualStrings("a", label.widget.content);

    try press(&s, ui.keys.escape, 0);
    try expectEqual(null, s.impl.typing);
    s.impl.push(.{ .text = .{ .text = "c" } });
    try frame(&s);
    try expectEqualStrings("a", s.root.widget.text.items);
}

const Form = struct {
    notes: u32 = 0,
    sent: u32 = 0,

    pub const view = ui.text("field").padding(4).input(jot).padding(4).tap(send);

    fn jot(self: *Form, _: ui.TextInput) void {
        self.notes += 1;
    }

    fn send(self: *Form) void {
        self.sent += 1;
    }
};

test "while text is typed, Enter and Space do not activate the tap around the input" {
    var s: Scene(Form) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    const field = &s.root.children[0].children[0].children[0];
    try press(&s, ui.keys.tab, 0);
    try expectEqual(field.id, s.state.focus.id());
    try press(&s, ui.keys.space, 0);
    try press(&s, ui.keys.enter, 0);
    s.impl.push(.{ .text = .{ .text = " " } });
    try frame(&s);
    try expectEqual(0, s.root.widget.sent);
    try expectEqual(1, s.root.widget.notes);

    try click(&s, centerOf(field));
    try expectEqual(1, s.root.widget.sent);
}

test "the advance of text counts the spaces at its end, and text without ink has no width" {
    try ui.startup(options.font);
    defer ui.shutdown();

    const word = ui.text("ab");
    try expectEqual(word.measure(.{}).width, ui.text("ab  ").measure(.{}).width);
    try expectEqual(0, ui.text("  ").measure(.{}).width);
    try expectEqual(0, ui.text("").advance());

    const space = ui.text(" ").advance();
    try expect(space > 0);
    try std.testing.expectApproxEqAbs(word.advance() + 2 * space, ui.text("ab  ").advance(), 0.01);
    try std.testing.expectApproxEqAbs(word.measure(.{}).width, word.advance(), 2);
    try std.testing.expectApproxEqAbs(word.advance() + 2 * 3, word.tracking(3).advance(), 0.01);

    // Asking for the advance of a space must not spoil the text that starts
    // with one.
    try expect(ui.text(" ab").measure(.{}).width > word.measure(.{}).width);
}

test "the position in a text nearest to a distance lies between two code points" {
    try ui.startup(options.font);
    defer ui.shutdown();

    const text = ui.text("a日本 b");
    const first = ui.text("a").advance();
    const second = ui.text("a日").advance();
    try expectEqual(0, text.indexAt(-5));
    try expectEqual(0, text.indexAt(first * 0.4));
    try expectEqual(1, text.indexAt(first * 0.6));
    try expectEqual(1, text.indexAt(first + (second - first) * 0.4));
    try expectEqual(4, text.indexAt(first + (second - first) * 0.6));
    try expectEqual(8, text.indexAt(ui.text("a日本 ").advance() + 1));
    try expectEqual(9, text.indexAt(1000));
    try expectEqual(0, ui.text("").indexAt(10));
}

test "the characters that a font lacks are measured in its fallback, on the lines of the font" {
    try ui.startup(options.font);
    defer ui.shutdown();
    try ui.addFont("assets/Roboto-Regular.ttf");

    const latin = ui.text("ab").font("Roboto-Regular");
    const japanese = ui.text("日本").font("NotoSansJP-Regular");
    const mixed = ui.text("ab日本").font("Roboto-Regular").fallback("NotoSansJP-Regular");
    try std.testing.expectApproxEqAbs(latin.advance() + japanese.advance(), mixed.advance(), 0.01);
    try std.testing.expectApproxEqAbs(mixed.advance(), mixed.measure(.{}).width, 2);
    try expectEqual(latin.measure(.{}).height, mixed.measure(.{}).height);
    try expectEqual(latin.measure(.{}), latin.fallback("NotoSansJP-Regular").measure(.{}));

    try expectEqual(2, mixed.indexAt(latin.advance() + japanese.advance() * 0.2));
    try expectEqual(5, mixed.indexAt(latin.advance() + japanese.advance() * 0.4));

    // The text wraps between the words and after any Japanese character.
    const line = latin.measure(.{}).height;
    const words = ui.text("ab ab 日本").font("Roboto-Regular").fallback("NotoSansJP-Regular");
    const narrow: ui.Constraint = .{ .max = .{ .width = japanese.advance() * 0.75, .height = ui.inf } };
    const wrapped = words.measure(narrow);
    try expectEqual(4 * line, wrapped.height);
    try expect(wrapped.width <= narrow.max.width);
}

const Dial = struct {
    turned: f32 = 0,

    pub const view = ui.rect().frame(.{ .width = 40, .height = 40 }).wheel(turn);

    fn turn(self: *Dial, wheel: ui.Wheel) bool {
        if (wheel.y == 0) return false;
        self.turned += wheel.y;
        return true;
    }
};

const Panes = struct {
    slid: f32 = 0,

    pub const view = ui.row(.{ Dial{}, ui.rect().frame(.{ .width = 40, .height = 40 }) }).wheel(slide);

    fn slide(self: *Panes, wheel: ui.Wheel) bool {
        self.slid += wheel.x + wheel.y;
        return true;
    }
};

test "the wheel reaches the view under the pointer, and the views around it when it is not used there" {
    var s: Scene(Panes) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    const dial = &s.root.children[0].children[0].children[0];
    const over_dial = centerOf(dial);
    s.impl.push(.{ .wheel = .{ .y = 3, .at = over_dial } });
    try frame(&s);
    try expectEqual(3, dial.widget.turned);
    try expectEqual(0, s.root.widget.slid);
    try expectEqual(dial.children[0].children[0].children[0].id, s.state.hover.id());

    // The dial has no use for a turn sideways.
    s.impl.push(.{ .wheel = .{ .x = 2, .at = over_dial } });
    try frame(&s);
    try expectEqual(3, dial.widget.turned);
    try expectEqual(2, s.root.widget.slid);

    s.impl.push(.{ .wheel = .{ .y = 5, .at = .{ .x = 60, .y = 20 } } });
    try frame(&s);
    try expectEqual(3, dial.widget.turned);
    try expectEqual(7, s.root.widget.slid);
}

test "an image is measured at its own size, smaller where space is short, and at the space offered with a fit" {
    try ui.startup(null);
    defer ui.shutdown();

    const wide = try ui.Image.load("tests/wide.png");
    defer wide.deinit();
    const tall = try ui.Image.load("tests/tall.jpg");
    defer tall.deinit();
    try expectEqual(ui.Extent{ .width = 8, .height = 4 }, wide.size());
    try expectEqual(ui.Extent{ .width = 6, .height = 10 }, tall.size());
    try std.testing.expectError(error.ImageLoad, ui.Image.load("tests/missing.png"));

    const picture = ui.image(wide);
    const narrow: ui.Constraint = .{ .max = .{ .width = 4, .height = ui.inf } };
    const box: ui.Constraint = .{ .max = .{ .width = 20, .height = 30 } };
    try expectEqual(ui.Extent{ .width = 8, .height = 4 }, picture.measure(.{}));
    try expectEqual(ui.Extent{ .width = 4, .height = 2 }, picture.measure(narrow));
    try expectEqual(ui.Extent{ .width = 8, .height = 4 }, picture.measure(box));
    try expectEqual(ui.Extent{ .width = 20, .height = 30 }, picture.fit(.cover).measure(box));
    try expectEqual(ui.Extent{ .width = 4, .height = 4 }, picture.fit(.contain).measure(narrow));
    try expectEqual(ui.Extent{}, ui.image(null).measure(box));
}

const Scrap = struct {
    text: std.ArrayList(u8) = .empty,
    found: bool = false,

    pub const view = ui.text("scrap").padding(4).key(shortcut);

    // Nothing was copied yet when the scene is built.
    pub fn mount(self: *Scrap, cx: ui.Context) void {
        self.found = cx.paste() != null;
    }

    pub fn unmount(self: *Scrap, cx: ui.Context) void {
        self.text.deinit(cx.gpa);
    }

    fn shortcut(self: *Scrap, key: ui.KeyPress, cx: ui.Context) bool {
        if (!key.down or !key.ctrl()) return false;
        switch (key.key) {
            'c' => _ = cx.copy(self.text.items),
            'v' => self.text.appendSlice(cx.gpa, cx.paste() orelse return false) catch @panic("out of memory"),
            else => return false,
        }
        return true;
    }
};

test "a key handler copies to the clipboard of the implementation and pastes from it" {
    var s: Scene(Scrap) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    try expect(!s.root.widget.found);

    const ctrl = 0x0040;
    try press(&s, ui.keys.tab, 0);
    try press(&s, 'v', ctrl);
    try expectEqualStrings("", s.root.widget.text.items);

    _ = s.impl.copy("ab");
    try press(&s, 'v', ctrl);
    try press(&s, 'v', ctrl);
    try expectEqualStrings("abab", s.root.widget.text.items);

    // Without Ctrl the key is not a shortcut.
    try press(&s, 'v', 0);
    try expectEqualStrings("abab", s.root.widget.text.items);

    try press(&s, 'c', ctrl);
    try expectEqualStrings("abab", s.impl.clipboard.items);
}

const Knob = struct {
    x: f32 = 0,
    y: f32 = 0,
    size: ui.Extent = .{},
    taps: u32 = 0,

    pub const view = ui.column(.{
        ui.rect().frame(.{ .width = 100, .height = 20 }).pointer(grabbed).tap(tapped),
        ui.rect().frame(.{ .width = 100, .height = 20 }).tap(tapped),
    }).padding(20);

    fn grabbed(self: *Knob, pointer: ui.Pointer, cx: ui.Context) bool {
        note(switch (pointer.phase) {
            .down => 'd',
            .move => 'm',
            .up => 'u',
            .cancel => 'c',
        });
        self.x = pointer.x;
        self.y = pointer.y;
        self.size = cx.size;
        return true;
    }

    fn tapped(self: *Knob) void {
        self.taps += 1;
    }
};

test "a view that uses a press holds the pointer until the release, and is told again while the pointer rests outside it" {
    var s: Scene(Knob) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    const knob = &s.root.widget;

    // The position counts from the corner of the view, and the tap around
    // the view is not pressed.
    trace = "";
    button(&s, true, .{ .x = 50, .y = 30 });
    try frame(&s);
    try expectEqualStrings("d", trace);
    try expectEqual(30, knob.x);
    try expectEqual(10, knob.y);
    try expectEqual(s.root.size, knob.size);

    s.impl.push(.{ .pointer_move = .{ .x = 500, .y = 30 } });
    try frame(&s);
    try expectEqualStrings("dmm", trace);
    try expectEqual(480, knob.x);
    try expect(s.busy());
    try frame(&s);
    try expectEqualStrings("dmmm", trace);

    s.impl.push(.{ .pointer_move = .{ .x = 60, .y = 30 } });
    try frame(&s);
    try expectEqualStrings("dmmmm", trace);
    try expect(!s.busy());

    button(&s, false, .{ .x = 60, .y = 30 });
    s.impl.push(.{ .pointer_move = .{ .x = 70, .y = 30 } });
    try frame(&s);
    try expectEqualStrings("dmmmmu", trace);
    try expectEqual(0, knob.taps);

    try click(&s, .{ .x = 50, .y = 50 });
    try expectEqual(1, knob.taps);

    // A window that loses the keyboard may never see the release.
    trace = "";
    button(&s, true, .{ .x = 50, .y = 30 });
    s.impl.push(.{ .active = false });
    s.impl.push(.{ .pointer_move = .{ .x = 60, .y = 30 } });
    try frame(&s);
    try expectEqualStrings("dc", trace);
}

const Menu = struct {
    taps: u32 = 0,

    pub const view = ui.column(.{
        ui.rect().frame(.{ .width = 100, .height = 20 }).pointer(opened),
        ui.rect().frame(.{ .width = 100, .height = 20 }).tap(tapped),
    }).padding(20);

    fn opened(pointer: ui.Pointer) bool {
        if (pointer.button != .right) return false;
        note(switch (pointer.phase) {
            .down => 'd',
            .move => 'm',
            .up => 'u',
            .cancel => 'c',
        });
        return true;
    }

    fn tapped(self: *Menu) void {
        self.taps += 1;
    }
};

fn buttonOf(s: anytype, which: ui.MouseButton, down: bool, at: ui.Point) void {
    s.impl.push(.{ .button = .{ .button = which, .down = down, .x = at.x, .y = at.y } });
}

test "a view holds the pointer with the button it took, and the other buttons do nothing meanwhile" {
    var s: Scene(Menu) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    const over_view: ui.Point = .{ .x = 50, .y = 30 };
    const over_tap: ui.Point = .{ .x = 50, .y = 50 };

    // The view has no use for the left button, and holds nothing.
    trace = "";
    button(&s, true, over_view);
    button(&s, false, over_view);
    try frame(&s);
    try expectEqualStrings("", trace);
    try expectEqual(0, s.held);

    buttonOf(&s, .right, true, over_view);
    button(&s, true, over_tap);
    button(&s, false, over_tap);
    s.impl.push(.{ .pointer_move = over_view });
    try frame(&s);
    try expectEqualStrings("dm", trace);
    try expectEqual(0, s.root.widget.taps);

    buttonOf(&s, .right, false, over_view);
    try frame(&s);
    try expectEqualStrings("dmu", trace);
    try expectEqual(0, s.held);

    // The right button neither presses a tap nor moves the focus.
    buttonOf(&s, .right, true, over_tap);
    try frame(&s);
    try expectEqual(0, s.state.press.id());
    try expectEqual(0, s.state.focus.id());
    buttonOf(&s, .right, false, over_tap);
    try frame(&s);
    try expectEqual(0, s.root.widget.taps);

    // A tap that is pressed is let go when a view takes another button.
    button(&s, true, over_tap);
    try frame(&s);
    try expect(s.state.press.id() != 0);
    buttonOf(&s, .right, true, over_view);
    button(&s, false, over_tap);
    buttonOf(&s, .right, false, over_tap);
    try frame(&s);
    try expectEqual(0, s.state.press.id());
    try expectEqual(0, s.root.widget.taps);
}

const Spot = struct {
    x: f32 = 0,
    y: f32 = 0,

    pub const view = ui.rect().frame(.{ .width = 40, .height = 40 }).hover(watched);

    fn watched(self: *Spot, hover: ui.Hover) void {
        note(switch (hover.phase) {
            .enter => 'e',
            .move => 'm',
            .leave => 'l',
        });
        self.x = hover.x;
        self.y = hover.y;
    }
};

const Lawn = struct {
    shown: bool = true,

    pub const view = ui.row(.{
        ui.when(shows, Spot{}, ui.spacer()),
        ui.rect().frame(.{ .width = 40, .height = 40 }),
    }).padding(10).hover(around);

    fn shows(self: *const Lawn) bool {
        return self.shown;
    }

    fn around(hover: ui.Hover) void {
        note(switch (hover.phase) {
            .enter => 'E',
            .move => 'M',
            .leave => 'L',
        });
    }
};

test "the views under the pointer are told when it comes, moves and leaves" {
    var s: Scene(Lawn) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    const spot = &s.root.children[0].children[0].children[0].children[0].children[0];

    // The position counts from the corner of the view.
    trace = "";
    s.impl.push(.{ .pointer_move = .{ .x = 20, .y = 30 } });
    try frame(&s);
    try expectEqualStrings("eE", trace);
    try expectEqual(10, spot.widget.x);
    try expectEqual(20, spot.widget.y);

    s.impl.push(.{ .pointer_move = .{ .x = 25, .y = 30 } });
    try frame(&s);
    try expectEqualStrings("eEmM", trace);
    try expectEqual(15, spot.widget.x);

    // A press where the pointer already is moves nothing.
    try click(&s, .{ .x = 25, .y = 30 });
    try expectEqualStrings("eEmM", trace);

    s.impl.push(.{ .pointer_move = .{ .x = 70, .y = 30 } });
    try frame(&s);
    try expectEqualStrings("eEmMlM", trace);
    try expectEqual(60, spot.widget.x);

    s.impl.push(.pointer_leave);
    try frame(&s);
    try expectEqualStrings("eEmMlML", trace);

    // A view that is hidden under the pointer is told that the pointer
    // left it.
    trace = "";
    s.impl.push(.{ .pointer_move = .{ .x = 20, .y = 30 } });
    try frame(&s);
    try expectEqualStrings("eE", trace);
    s.root.widget.shown = false;
    s.root.dirty = true;
    s.pending = true;
    try frame(&s);
    try expectEqualStrings("eEl", trace);
}

const Tray = struct {
    path: [32]u8 = undefined,
    len: usize = 0,
    x: f32 = 0,
    texts: u32 = 0,

    pub const view = ui.row(.{
        ui.rect().frame(.{ .width = 40, .height = 40 }).drop(filed),
        ui.rect().frame(.{ .width = 40, .height = 40 }),
    }).padding(10).drop(texted);

    fn filed(self: *Tray, drop: ui.Drop) bool {
        if (drop.kind != .file) return false;
        @memcpy(self.path[0..drop.data.len], drop.data);
        self.len = drop.data.len;
        self.x = drop.x;
        return true;
    }

    fn texted(self: *Tray, drop: ui.Drop) bool {
        if (drop.kind != .text) return false;
        self.texts += 1;
        return true;
    }
};

test "a drop reaches the view under the pointer, and the views around it when it is not taken there" {
    var s: Scene(Tray) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    const tray = &s.root.widget;

    s.impl.push(.{ .drop = .{ .kind = .file, .data = "/tmp/a.txt", .x = 30, .y = 20 } });
    try frame(&s);
    try expectEqualStrings("/tmp/a.txt", tray.path[0..tray.len]);
    try expectEqual(20, tray.x);
    try expectEqual(0, tray.texts);

    s.impl.push(.{ .drop = .{ .kind = .text, .data = "a", .x = 30, .y = 20 } });
    try frame(&s);
    try expectEqual(1, tray.texts);

    // Nothing takes a file beside the view.
    tray.len = 0;
    s.impl.push(.{ .drop = .{ .kind = .file, .data = "/tmp/b.txt", .x = 70, .y = 20 } });
    try frame(&s);
    try expectEqual(0, tray.len);
}

fn Stepper(comptime on_step: anytype) type {
    return struct {
        pub const view = ui.text("+").tap(step);

        fn step(stepped: ui.Callback(on_step)) void {
            stepped.call();
        }
    };
}

const Tally = struct {
    count: u32 = 0,
    asked: u32 = 0,

    pub const view = ui.column(.{ ui.show(label), Stepper(add){}, Stepper({}){} });

    fn label(self: *const Tally, cx: ui.Context) ui.Text {
        return ui.text(cx.print("{d}", .{self.count}));
    }

    fn add(self: *Tally, cx: ui.Context) void {
        self.count += 1;
        self.asked = cx.id;
    }
};

test "a callback given to a component runs as if written where the component is, and builds what it changes again" {
    var s: Scene(Tally) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    const column = &s.root.children[0];
    try click(&s, centerOf(&column.children[1]));
    try expectEqualStrings("1", column.children[0].widget.content);
    try expectEqual(s.root.id, s.root.widget.asked);

    // A component that was given no function calls nothing.
    try click(&s, centerOf(&column.children[2]));
    try expectEqual(1, s.root.widget.count);
}

var drawn_at: f64 = 0;

const Needle = struct {
    pub fn measure(_: Needle, c: ui.Constraint) ui.Extent {
        return c.constrain(.{ .width = 10, .height = 10 });
    }

    pub fn paint(_: Needle, p: ui.Painter) void {
        drawn_at = p.now();
        p.again(p.now() + 2);
        p.again(p.now() + 5);
    }
};

const Watch = struct {
    pub const view = ui.column(.{ui.wrap(Needle{})});
};

test "a painter that asks for another frame is given it at that time without anything being built" {
    var s: Scene(Watch) = try .init(gpa, options, .{});
    defer s.deinit();

    // Nothing here draws with the canvas, so it needs no OpenGL.
    var blank: ui.Canvas = undefined;
    s.impl.canvas = &blank;
    s.impl.seconds = 5;
    try frame(&s);
    try expectEqual(5, drawn_at);

    // The scene waits for an event until the earliest time asked for.
    try frame(&s);
    try expectEqual(2, s.impl.waited);
    s.impl.seconds = 7;
    try frame(&s);
    try expectEqual(7, drawn_at);
    try expect(!s.state.built);
}

const Twin = struct {
    pub const view = ui.column(.{ Entry{}, Entry{} });
};

test "a composition ends when the typing moves to another input or the window loses the keyboard" {
    var s: Scene(Twin) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    const first = &s.root.children[0].children[0];
    const second = &s.root.children[0].children[1];

    try press(&s, ui.keys.tab, 0);
    s.impl.push(.{ .text = .{ .text = "か", .composing = true } });
    try frame(&s);
    try expectEqual(3, first.widget.composing);

    // The implementation is stopped in between, so that its input method
    // starts afresh in the second input.
    try press(&s, ui.keys.tab, 0);
    try expectEqual(0, first.widget.composing);
    try expectEqual(1, s.impl.stops);
    try expect(s.impl.typing != null);

    s.impl.push(.{ .text = .{ .text = "な", .composing = true } });
    try frame(&s);
    try expectEqual(3, second.widget.composing);
    s.impl.push(.{ .active = false });
    try frame(&s);
    try frame(&s);
    try expectEqual(0, second.widget.composing);
    try expectEqual(null, s.impl.typing);

    s.impl.push(.{ .active = true });
    try frame(&s);
    try expect(s.impl.typing != null);
}

test "a color fades without taking the tint of a transparent one" {
    const violet: ui.Color = .{ .r = 100, .g = 80, .b = 160 };
    const clear_gray: ui.Color = .{ .r = 70, .g = 70, .b = 70, .a = 0 };

    const appearing = ui.Color.lerp(clear_gray, violet, 0.5);
    try std.testing.expectEqual(ui.Color{ .r = 100, .g = 80, .b = 160, .a = 128 }, appearing);
    const leaving = ui.Color.lerp(violet, clear_gray, 0.75);
    try std.testing.expectEqual(ui.Color{ .r = 100, .g = 80, .b = 160, .a = 64 }, leaving);

    try std.testing.expectEqual(violet, ui.Color.lerp(clear_gray, violet, 1));
    try std.testing.expectEqual(clear_gray, ui.Color.lerp(violet, clear_gray, 1));
}

test "a color mixes opaque colors evenly and by alpha otherwise" {
    const black: ui.Color = .black;
    const white: ui.Color = .white;
    try std.testing.expectEqual(ui.Color{ .r = 128, .g = 128, .b = 128 }, ui.Color.lerp(black, white, 0.5));

    // The faint white weighs a quarter of the black beside it.
    const faint_white: ui.Color = .{ .r = 255, .g = 255, .b = 255, .a = 64 };
    const mixed = ui.Color.lerp(black, faint_white, 0.5);
    try std.testing.expectEqual(ui.Color{ .r = 51, .g = 51, .b = 51, .a = 160 }, mixed);
}

test "a color does not overshoot" {
    const from: ui.Color = .{ .r = 100, .g = 100, .b = 100 };
    const to: ui.Color = .{ .r = 200, .g = 50, .b = 100, .a = 200 };
    try std.testing.expectEqual(to, ui.Color.lerp(from, to, 1.2));
    try std.testing.expectEqual(from, ui.Color.lerp(from, to, -0.2));
}

// A view that opens two choices in a popup, above a tap that the popup
// covers.
const Chooser = struct {
    open: bool = false,
    chosen: u8 = 0,
    others: u32 = 0,

    const side = 40;

    pub const view = ui.column(.{
        ui.rect().frame(.{ .width = 100, .height = side }).tap(toggle).popup(isOpen, close, ui.column(.{
            ui.rect().frame(.{ .width = 100, .height = side }).tap(first),
            ui.rect().frame(.{ .width = 100, .height = side }).tap(second),
        }), .{}, .{}),
        ui.rect().frame(.{ .width = 300, .height = side }).tap(other),
    }).cross(.start);

    fn isOpen(self: *const Chooser) bool {
        return self.open;
    }

    fn toggle(self: *Chooser) void {
        self.open = !self.open;
    }

    fn close(self: *Chooser) void {
        self.open = false;
    }

    fn first(self: *Chooser) void {
        self.chosen = 1;
    }

    fn second(self: *Chooser) void {
        self.chosen = 2;
    }

    fn other(self: *Chooser) void {
        self.others += 1;
    }
};

const over_opener: ui.Point = .{ .x = 50, .y = 20 };
const over_first: ui.Point = .{ .x = 50, .y = 60 };
const beside_popup: ui.Point = .{ .x = 200, .y = 60 };

test "a popup shows below its view, in front of what lies there" {
    var s: Scene(Chooser) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    const column = &s.root.children[0];
    const opener = &column.children[0];
    try expectEqual(ui.Extent{ .width = 100, .height = 40 }, opener.size);

    // While closed, the place below the view belongs to what lies there.
    try click(&s, over_first);
    try expectEqual(0, s.root.widget.chosen);
    try expectEqual(1, s.root.widget.others);

    try click(&s, over_opener);
    try frame(&s);
    try expect(s.root.widget.open);
    const content = &opener.children[1];
    try expectEqual(ui.Point{ .x = 0, .y = 40 }, ui.offsetOf(content));
    try expectEqual(ui.Extent{ .width = 100, .height = 80 }, content.size);
    // The popup takes no room: what follows the view stays where it was.
    try expectEqual(ui.Point{ .x = 0, .y = 40 }, ui.offsetOf(&column.children[1]));

    try click(&s, over_first);
    try expectEqual(1, s.root.widget.chosen);
    try expectEqual(1, s.root.widget.others);
}

test "a press outside the open popups dismisses them and does nothing else" {
    var s: Scene(Chooser) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);

    try click(&s, over_opener);
    try frame(&s);
    try click(&s, beside_popup);
    try expect(!s.root.widget.open);
    try expectEqual(0, s.root.widget.others);

    // The view of the popup is outside it too, so a press there closes the
    // popup instead of opening it again.
    try click(&s, over_opener);
    try frame(&s);
    try click(&s, over_opener);
    try expect(!s.root.widget.open);

    try frame(&s);
    try click(&s, beside_popup);
    try expectEqual(1, s.root.widget.others);
}

test "while a popup is open, the focus moves inside it, and Escape dismisses it" {
    var s: Scene(Chooser) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    const opener = &s.root.children[0].children[0];
    const choices = &opener.children[1].children;

    // Without a popup the arrows move nothing.
    try press(&s, ui.keys.down, 0);
    try expectEqual(0, s.state.focus.id());

    try click(&s, over_opener);
    try frame(&s);
    try press(&s, ui.keys.down, 0);
    try expectEqual(choices[0].id, s.state.focus.id());
    try press(&s, ui.keys.down, 0);
    try expectEqual(choices[1].id, s.state.focus.id());
    try press(&s, ui.keys.tab, 0);
    try expectEqual(choices[0].id, s.state.focus.id());
    try press(&s, ui.keys.up, 0);
    try expectEqual(choices[1].id, s.state.focus.id());

    try press(&s, ui.keys.enter, 0);
    try expectEqual(2, s.root.widget.chosen);

    // The focus goes back to the view of the popup.
    try press(&s, ui.keys.escape, 0);
    try expect(!s.root.widget.open);
    try frame(&s);
    try expectEqual(opener.children[0].id, s.state.focus.id());
}

// A popup at the bottom right corner of a window that has no room below or
// beside it, and comes over a quarter of a second.
const Cornered = struct {
    open: bool = true,

    pub const view = ui.rect().frame(.{ .width = 40, .height = 40 })
        .popup(isOpen, close, ui.rect().frame(.{ .width = 120, .height = 90 }), .{ .offset = .{ .y = 4 } }, .{
            .scale = 0.5,
            .grow = .{ .duration = 0.25, .curve = .linear },
            .fade = .{ .duration = 0.25, .curve = .linear },
        })
        .frame(.{ .max_width = ui.inf, .max_height = ui.inf, .alignment = .bottom_right });

    fn isOpen(self: *const Cornered) bool {
        return self.open;
    }

    fn close(self: *Cornered) void {
        self.open = false;
    }
};

test "a popup without room on its side of the view opens on the opposite side" {
    var s: Scene(Cornered) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    const anchored = &s.root.children[0].children[0];
    try expectEqual(ui.Point{ .x = 360, .y = 260 }, ui.offsetOf(anchored));
    // Its right edge is on that of the view, and its bottom 4 above the view.
    try expectEqual(ui.Point{ .x = 280, .y = 166 }, ui.offsetOf(&anchored.children[1]));
    try expectEqual(ui.Alignment.bottom_right, anchored.widget.origin);
}

test "a popup comes and goes over time, and takes no input while it goes" {
    var s: Scene(Cornered) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    const popup = &s.root.children[0].children[0].widget;
    try expect(popup.visible);
    try expect(s.busy());
    s.impl.seconds = 0.3;
    try frame(&s);
    try expect(!s.busy());

    try press(&s, ui.keys.escape, 0);
    try frame(&s);
    try expect(!s.root.widget.open);
    try expect(popup.visible);
    try expectEqual(0, s.state.hover.id());
    s.impl.push(.{ .pointer_move = .{ .x = 300, .y = 200 } });
    s.impl.seconds = 0.4;
    try frame(&s);
    try expect(popup.visible);
    try expect(s.state.hover.id() != 0);
    try expect(!node_contains(s.state.hover.slice(), s.root.children[0].children[0].children[1].id));

    s.impl.seconds = 0.6;
    try frame(&s);
    try expect(!popup.visible);
    try expect(!s.busy());
}

fn node_contains(path: anytype, id: u32) bool {
    return std.mem.indexOfScalar(u32, path, id) != null;
}

// An area that opens a popup where the right button is pressed.
const Easel = struct {
    open: bool = false,
    at: ui.Point = .{},

    pub const view = ui.stack(.{
        ui.rect().frame(.{ .width = 400, .height = 300 }).pointer(pressed),
        ui.show(mark),
    }).alignment(.top_left);

    fn mark(self: *const Easel) @TypeOf(ui.rect().frame(.{}).popup(isOpen, close, ui.rect().frame(.{}), .{}, .{})) {
        return ui.rect().frame(.{ .width = 0, .height = 0 }).popup(
            isOpen,
            close,
            ui.rect().frame(.{ .width = 80, .height = 60 }),
            .{ .from = .top_left, .offset = self.at },
            .{},
        );
    }

    fn isOpen(self: *const Easel) bool {
        return self.open;
    }

    fn close(self: *Easel) void {
        self.open = false;
    }

    fn pressed(self: *Easel, pointer: ui.Pointer) bool {
        if (pointer.button != .right) return false;
        if (pointer.phase == .down) {
            self.at = .{ .x = pointer.x, .y = pointer.y };
            self.open = true;
        }
        return true;
    }
};

fn rightClick(s: anytype, at: ui.Point) !void {
    buttonOf(s, .right, true, at);
    buttonOf(s, .right, false, at);
    try frame(s);
    try frame(s);
}

test "a popup opens where it is asked for, and again where another button is pressed outside it" {
    var s: Scene(Easel) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    const content = &s.root.children[0].children[1].children[1];

    try rightClick(&s, .{ .x = 50, .y = 40 });
    try expect(s.root.widget.open);
    try expectEqual(ui.Point{ .x = 50, .y = 40 }, ui.offsetOf(content));

    try rightClick(&s, .{ .x = 200, .y = 150 });
    try expect(s.root.widget.open);
    try expectEqual(ui.Point{ .x = 200, .y = 150 }, ui.offsetOf(content));

    // Near the corner of the window the popup is moved back inside.
    try rightClick(&s, .{ .x = 380, .y = 290 });
    try expectEqual(ui.Point{ .x = 320, .y = 240 }, ui.offsetOf(content));

    try click(&s, .{ .x = 100, .y = 100 });
    try expect(!s.root.widget.open);
}

const command_mod: u16 = if (@import("builtin").os.tag.isDarwin()) 0x0400 else 0x0040;
const shift_mod: u16 = 0x0001;

// A view that saves with keys that can be set, beside a button.
const Saver = struct {
    saves: u32 = 0,
    bound: ?ui.Chord = .{ .key = 's', .command = true },

    pub const view = ui.row(.{
        ui.rect().frame(.{ .width = 40, .height = 40 }).tap(nothing),
        ui.rect().frame(.{ .width = 40, .height = 40 }).shortcut(saveKeys, save),
    });

    fn saveKeys(self: *const Saver) ?ui.Chord {
        return self.bound;
    }

    fn save(self: *Saver, key: ui.KeyPress) void {
        if (key.key == self.bound.?.key) self.saves += 1;
    }

    fn nothing() void {}
};

test "a shortcut runs wherever the focus is, with the keys that its function returns" {
    var s: Scene(Saver) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    const saver = &s.root.widget;

    try press(&s, 's', command_mod);
    try expectEqual(1, saver.saves);
    try press(&s, ui.keys.tab, 0);
    try expect(s.state.focus.id() != 0);
    try press(&s, 's', command_mod);
    try expectEqual(2, saver.saves);

    // The modifier keys are those of the chord and no others.
    try press(&s, 's', 0);
    try press(&s, 's', command_mod | shift_mod);
    try expectEqual(2, saver.saves);

    saver.bound = .{ .key = 'w', .shift = true };
    try press(&s, 's', command_mod);
    try expectEqual(2, saver.saves);
    try press(&s, 'w', shift_mod);
    try expectEqual(3, saver.saves);

    saver.bound = null;
    try press(&s, 'w', shift_mod);
    try expectEqual(3, saver.saves);
}

// Three views with the same shortcut, one around the other two, and a view
// that takes keys.
const Rivals = struct {
    greedy: bool = false,

    pub const view = ui.row(.{
        ui.rect().frame(.{ .width = 40, .height = 40 }).tap(nothing).shortcut(keys, back),
        ui.rect().frame(.{ .width = 40, .height = 40 }).tap(nothing).shortcut(keys, front),
        ui.rect().frame(.{ .width = 40, .height = 40 }).key(take),
    }).shortcut(keys, around);

    fn keys() ui.Chord {
        return .{ .key = 'k', .command = true };
    }

    fn back() void {
        note('b');
    }

    fn front() void {
        note('f');
    }

    fn around() void {
        note('a');
    }

    fn take(self: *const Rivals, key: ui.KeyPress) bool {
        return self.greedy and key.key == 'k';
    }

    fn nothing() void {}
};

test "a key goes to the focus before the shortcuts, of which the nearest around the focus runs, or else the one in front" {
    var s: Scene(Rivals) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    trace = "";

    try press(&s, 'k', command_mod);
    try expectEqualStrings("f", trace);

    try press(&s, ui.keys.tab, 0);
    try press(&s, 'k', command_mod);
    try expectEqualStrings("fb", trace);

    try press(&s, ui.keys.tab, 0);
    try press(&s, ui.keys.tab, 0);
    try press(&s, 'k', command_mod);
    try expectEqualStrings("fba", trace);

    s.root.widget.greedy = true;
    try press(&s, 'k', command_mod);
    try expectEqualStrings("fba", trace);
}

// An input with a shortcut of one key alone and one with the command key.
const Jotter = struct {
    pub const view = ui.text("field").padding(4).input(jot)
        .shortcut(alone, plain)
        .shortcut(held, commanded);

    fn jot() void {}

    fn alone() ui.Chord {
        return .{ .key = 'a' };
    }

    fn held() ui.Chord {
        return .{ .key = 'a', .command = true };
    }

    fn plain() void {
        note('p');
    }

    fn commanded() void {
        note('c');
    }
};

test "while text is typed, a shortcut without Ctrl, Alt or the command key does not run" {
    var s: Scene(Jotter) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    trace = "";

    try press(&s, ui.keys.tab, 0);
    try expect(s.impl.typing != null);
    try press(&s, 'a', 0);
    try expectEqualStrings("", trace);
    try press(&s, 'a', command_mod);
    try expectEqualStrings("c", trace);

    try press(&s, ui.keys.escape, 0);
    try expectEqual(null, s.impl.typing);
    try press(&s, 'a', 0);
    try expectEqualStrings("cp", trace);
}

// A view that shows a popup with a shortcut that the view has too, and with
// one that only the view has.
const Commands = struct {
    open: bool = false,

    pub const view = ui.rect().frame(.{ .width = 100, .height = 40 }).tap(toggle)
        .popup(isOpen, close, ui.rect().frame(.{ .width = 100, .height = 40 }).shortcut(pick, inside), .{}, .{})
        .shortcut(pick, outside)
        .shortcut(quit, leave);

    fn isOpen(self: *const Commands) bool {
        return self.open;
    }

    fn toggle(self: *Commands) void {
        self.open = !self.open;
    }

    fn close(self: *Commands) void {
        self.open = false;
    }

    fn pick() ui.Chord {
        return .{ .key = 'p', .command = true };
    }

    fn quit() ui.Chord {
        return .{ .key = 'q', .command = true };
    }

    fn inside() void {
        note('i');
    }

    fn outside() void {
        note('o');
    }

    fn leave() void {
        note('q');
    }
};

test "while a popup is open, only the shortcuts in it run" {
    var s: Scene(Commands) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    trace = "";

    try press(&s, 'p', command_mod);
    try press(&s, 'q', command_mod);
    try expectEqualStrings("oq", trace);

    try click(&s, .{ .x = 50, .y = 20 });
    try frame(&s);
    try expect(s.root.widget.open);
    try press(&s, 'p', command_mod);
    try press(&s, 'q', command_mod);
    try expectEqualStrings("oqi", trace);

    try press(&s, ui.keys.escape, 0);
    try expect(!s.root.widget.open);
    try frame(&s);
    try press(&s, 'p', command_mod);
    try expectEqualStrings("oqio", trace);
}

// A bar that shows its input on a shortcut, inside a view with a button
// before it.
const Finder = struct {
    pub const view = ui.column(.{
        ui.rect().frame(.{ .width = 40, .height = 40 }).tap(nothing),
        Bar{},
    });

    fn nothing() void {}

    const Bar = struct {
        open: bool = false,

        pub const view = ui.when(isOpen, ui.text("field").padding(4).input(jot), ui.rect())
            .shortcut(keys, show);

        fn isOpen(self: *const Bar) bool {
            return self.open;
        }

        fn keys() ui.Chord {
            return .{ .key = 'f', .command = true };
        }

        fn show(self: *Bar, cx: ui.Context) void {
            self.open = true;
            cx.focus();
        }

        fn jot() void {}
    };
};

test "a component that asks for the focus has it on the first view that takes it, one that the same function brings up too" {
    var s: Scene(Finder) = try .init(gpa, options, .{});
    defer s.deinit();
    try frame(&s);
    const bar = &s.root.children[0].children[1];
    const field = &bar.children[0].children[0].children[0];

    try press(&s, 'f', command_mod);
    try expect(bar.widget.open);
    try expectEqual(field.id, s.state.focus.id());
    try expect(s.impl.typing != null);
}
