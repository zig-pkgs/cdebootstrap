const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const c = @import("c");

export fn download(install_maybe: ?*c.suite_packages) c_int {
    assert(install_maybe != null);
    const install = install_maybe.?;
    install.allocator = c.di_packages_allocator_alloc();
    if (install.allocator == null)
        return 1;

    //install.packages = c.download_indices(install.allocator);
    //if (install.packages == null)
    //    return 1;

    c.suite_packages_list(install);

    return 0;
}
