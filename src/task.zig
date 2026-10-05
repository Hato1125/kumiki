//! Functions that run on threads of their own and hand what they return back
//! to the thread that started them, and values that are handed back after a
//! while.

const std = @import("std");

/// Stands for a type at run time: the address of a byte that exists once per
/// type.
pub fn keyOf(comptime T: type) *const anyopaque {
    return &struct {
        const Of = T;
        var byte: u8 = 0;
    }.byte;
}

/// A function on its way. Its thread sets `done`; everything else belongs to
/// the thread that started it. `tag` is what the starter wants back with the
/// result. A value that waits has no thread, and is handed over after `due`.
pub const Task = struct {
    next: ?*Task,
    tag: u32,
    key: *const anyopaque,
    result: *const anyopaque,
    thread: ?std.Thread = null,
    done: std.atomic.Value(bool) = .init(false),
    due: f64 = 0,
    destroy: *const fn (*Task, std.mem.Allocator) void,
};

/// `waker` is whom `wake` tells that a function has ended, and null while
/// nobody waits. It is set again and again by its owner, who may have moved.
pub const Tasks = struct {
    gpa: std.mem.Allocator,
    first: ?*Task = null,
    waker: std.atomic.Value(?*anyopaque) = .init(null),
    wake: *const fn (*anyopaque) void,

    /// Runs `work(args...)` on a new thread.
    pub fn spawn(
        tasks: *Tasks,
        tag: u32,
        comptime work: anytype,
        args: std.meta.ArgsTuple(@TypeOf(work)),
    ) void {
        const Job = struct {
            task: Task,
            tasks: *Tasks,
            args: std.meta.ArgsTuple(@TypeOf(work)),
            result: @typeInfo(@TypeOf(work)).@"fn".return_type.? = undefined,

            fn run(job: *@This()) void {
                job.result = @call(.auto, work, job.args);
                job.task.done.store(true, .release);
                if (job.tasks.waker.load(.acquire)) |waker| {
                    job.tasks.wake(waker);
                }
            }

            fn destroy(task: *Task, gpa: std.mem.Allocator) void {
                gpa.destroy(@as(*@This(), @fieldParentPtr("task", task)));
            }
        };
        const job = tasks.gpa.create(Job) catch @panic("out of memory");
        job.* = .{
            .tasks = tasks,
            .args = args,
            .task = .{
                .next = tasks.first,
                .tag = tag,
                .key = keyOf(@TypeOf(job.result)),
                .result = @ptrCast(&job.result),
                .destroy = Job.destroy,
            },
        };
        job.task.thread = std.Thread.spawn(.{}, Job.run, .{job}) catch @panic("cannot start a thread");
        tasks.first = &job.task;
    }

    /// Keeps `value` for `tag` until the time `at`. An equal value that waits
    /// for the same tag gives way to it.
    pub fn after(
        tasks: *Tasks,
        tag: u32,
        at: f64,
        value: anytype,
    ) void {
        const Value = @TypeOf(value);
        const Job = struct {
            task: Task,
            value: Value,

            fn destroy(task: *Task, gpa: std.mem.Allocator) void {
                gpa.destroy(@as(*@This(), @fieldParentPtr("task", task)));
            }
        };
        var link = &tasks.first;
        while (link.*) |task| {
            const waiting: *const Value = @ptrCast(@alignCast(task.result));
            if (task.thread == null and
                task.tag == tag and
                task.key == keyOf(Value) and
                std.meta.eql(waiting.*, value))
            {
                link.* = task.next;
                task.destroy(task, tasks.gpa);
            } else {
                link = &task.next;
            }
        }
        const job = tasks.gpa.create(Job) catch @panic("out of memory");
        job.* = .{
            .value = value,
            .task = .{
                .next = tasks.first,
                .tag = tag,
                .key = keyOf(Value),
                .result = @ptrCast(&job.value),
                .due = at,
                .destroy = Job.destroy,
            },
        };
        tasks.first = &job.task;
    }

    /// When the first of the values that wait is handed over, or infinity.
    pub fn due(tasks: *const Tasks) f64 {
        var first = std.math.inf(f64);
        var next = tasks.first;
        while (next) |task| : (next = task.next) {
            if (task.thread == null) first = @min(first, task.due);
        }
        return first;
    }

    /// Takes out a function that has ended, or a value that was due before
    /// `now`. A thread is joined first, because it still reads the task after
    /// it set `done`. The caller reads the result and then calls `destroy`.
    pub fn take(tasks: *Tasks, now: f64) ?*Task {
        var link = &tasks.first;
        while (link.*) |task| : (link = &task.next) {
            const ready = if (task.thread == null) task.due < now else task.done.load(.acquire);
            if (!ready) continue;
            link.* = task.next;
            if (task.thread) |thread| thread.join();
            return task;
        }
        return null;
    }

    /// Waits for the functions that still run and drops what they return,
    /// and the values that wait.
    pub fn deinit(tasks: *Tasks) void {
        tasks.waker.store(null, .release);
        while (tasks.first) |task| {
            tasks.first = task.next;
            if (task.thread) |thread| thread.join();
            task.destroy(task, tasks.gpa);
        }
    }
};
