pub fn Each(
    comptime n: usize,
    comptime F: anytype,
    comptime args: anytype,
) type {
    var element_types: [n]type = undefined;
    for (0..n) |i| element_types[i] = @call(.auto, F, args ++ .{i});
    return @Tuple(&element_types);
}

/// Places `n` components as the children of a container. `F` is a function
/// that returns the type of a component: it is called once for each child
/// with `args` followed by the index of the child, whose fields start at
/// their default values.
pub fn each(
    comptime n: usize,
    comptime F: anytype,
    comptime args: anytype,
) Each(n, F, args) {
    var components: Each(n, F, args) = undefined;
    inline for (0..n) |i| components[i] = .{};
    return components;
}
