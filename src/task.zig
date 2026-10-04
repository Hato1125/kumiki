//! Functions that run on threads of their own and hand what they return back
//! to the thread that started them.

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
/// result.
pub const Task = struct {
    next: ?*Task,
    tag: u32,
    key: *const anyopaque,
    result: *const anyopaque,
    thread: std.Thread = undefined,
    done: std.atomic.Value(bool) = .init(false),
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

    /// Takes out a function that has ended. Its thread is joined first,
    /// because it still reads the task after it set `done`. The caller reads
    /// the result and then calls `destroy`.
    pub fn take(tasks: *Tasks) ?*Task {
        var link = &tasks.first;
        while (link.*) |task| : (link = &task.next) {
            if (!task.done.load(.acquire)) continue;
            link.* = task.next;
            task.thread.join();
            return task;
        }
        return null;
    }

    /// Waits for the functions that still run and drops what they return.
    pub fn deinit(tasks: *Tasks) void {
        tasks.waker.store(null, .release);
        while (tasks.first) |task| {
            tasks.first = task.next;
            task.thread.join();
            task.destroy(task, tasks.gpa);
        }
    }
};
