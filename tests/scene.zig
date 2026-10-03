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
    return .{ .x = node.offset.x + node.size.width / 2, .y = node.offset.y + node.size.height / 2 };
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
    try expectEqual(40 + 10 + 85 + 10, row.children[2].offset.x);

    const line_height = ui.text("x").measure(.{}).height;
    const wrapped = &column.children[1];
    try expect(wrapped.children[0].size.width <= 60);
    try expect(wrapped.size.height >= line_height * 3);

    const padded = &column.children[2];
    try expectEqual(padded.children[0].size.width + 10, padded.size.width);
    try expectEqual(padded.offset.y + 2, padded.children[0].offset.y);
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
    try expectEqual(ink.offset, outlined.offset);
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
}
