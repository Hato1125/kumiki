//! Functions that run on threads of their own and hand what they return back
//! to the thread that started them, and calls that wait for their time.

const std = @import("std");

/// Stands for a type or a function at run time: the address of a byte that
/// exists once for each.
pub fn keyOf(comptime what: anytype) *const anyopaque {
    return &struct {
        const of = what;
        var byte: u8 = 0;
    }.byte;
}

/// A function on its way. Its thread sets `done`; everything else belongs to
/// the thread that started it. `tag` is what the starter wants back with the
/// result, `key` stands for the function to hand it to and `kind` for its
/// type. A call that waits has no thread and no result, and is made after
/// `due`.
pub const Task = struct {
    next: ?*Task,
    tag: u32,
    key: *const anyopaque,
    kind: *const anyopaque,
    result: *const anyopaque = undefined,
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

    /// Runs `work(args...)` on a new thread, for `key` to be handed what it
    /// returns.
    pub fn spawn(
        tasks: *Tasks,
        tag: u32,
        comptime work: anytype,
        args: std.meta.ArgsTuple(@TypeOf(work)),
        key: *const anyopaque,
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
                .key = key,
                .kind = keyOf(@TypeOf(job.result)),
                .result = @ptrCast(&job.result),
                .destroy = Job.destroy,
            },
        };
        job.task.thread = std.Thread.spawn(.{}, Job.run, .{job}) catch @panic("cannot start a thread");
        tasks.first = &job.task;
    }

    /// Has `key` called for `tag` at the time `at`. A call of it that still
    /// waits for the same tag gives way.
    pub fn after(
        tasks: *Tasks,
        tag: u32,
        at: f64,
        key: *const anyopaque,
    ) void {
        var link = &tasks.first;
        while (link.*) |task| {
            if (task.thread == null and task.tag == tag and task.key == key) {
                link.* = task.next;
                task.destroy(task, tasks.gpa);
            } else {
                link = &task.next;
            }
        }
        const task = tasks.gpa.create(Task) catch @panic("out of memory");
        task.* = .{
            .next = tasks.first,
            .tag = tag,
            .key = key,
            .kind = keyOf(void),
            .due = at,
            .destroy = destroyCall,
        };
        tasks.first = task;
    }

    fn destroyCall(task: *Task, gpa: std.mem.Allocator) void {
        gpa.destroy(task);
    }

    /// When the first of the calls that wait is made, or infinity.
    pub fn due(tasks: *const Tasks) f64 {
        var first = std.math.inf(f64);
        var next = tasks.first;
        while (next) |task| : (next = task.next) {
            if (task.thread == null) first = @min(first, task.due);
        }
        return first;
    }

    /// Takes out a function that has ended, or a call that was due before
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
    /// and the calls that wait.
    pub fn deinit(tasks: *Tasks) void {
        tasks.waker.store(null, .release);
        while (tasks.first) |task| {
            tasks.first = task.next;
            if (task.thread) |thread| thread.join();
            task.destroy(task, tasks.gpa);
        }
    }
};
