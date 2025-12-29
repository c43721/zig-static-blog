const std = @import("std");
const builtin = @import("builtin");
const Template = @import("template.zig").Template;
const os = builtin.os;
const cpu = builtin.cpu;

pub fn build(b: *std.Build) !void {
    const pandoc_dependency = if (os.tag == .linux and cpu.arch == .x86_64)
        b.lazyDependency("pandoc_linux_amd64", .{}) orelse return
    else if (os.tag == .linux and cpu.arch == .aarch64)
        b.lazyDependency("pandoc_linux_arm64", .{}) orelse return
    else if (os.tag == .macos and cpu.arch == .aarch64)
        b.lazyDependency("pandoc_macos_arm64", .{}) orelse return
    else if (os.tag == .windows and cpu.arch == .x86_64)
        b.lazyDependency("pandoc_windows_x86_64", .{}) orelse return
    else
        return error.UnsupportedHost;

    const raw_outputs = b.addWriteFiles();

    const pandoc_exe_name = if (os.tag == .windows) "pandoc.exe" else "bin/pandoc";
    const pandoc = pandoc_dependency.path(pandoc_exe_name);

    const markdown_files = b.run(&.{ "git", "ls-files", "content/*/**.md" });
    var lines = std.mem.tokenizeScalar(u8, markdown_files, '\n');

    const clean_zigout_step = b.addRemoveDirTree(b.path("zig-out"));

    const assets = b.addWriteFiles();
    const add_assets_step = b.addInstallDirectory(.{
        .source_dir = assets.addCopyDirectory(b.path("assets"), "assets/", .{}),
        .install_dir = .prefix,
        .install_subdir = ".",
    });

    add_assets_step.step.dependOn(&clean_zigout_step.step);

    while (lines.next()) |file_path| {
        const markdown = b.path(file_path);
        const html = markdown2html(b, pandoc, markdown);

        // map `content/pure-awesomeness.md` to `pure-awesomeness.html`
        var html_path = file_path;
        html_path = cut_prefix(html_path, "content/").?;
        html_path = cut_suffix(html_path, ".md").?;
        html_path = b.fmt("{s}.html", .{html_path});

        _ = raw_outputs.addCopyFile(html, html_path);
    }

    // Add the index html to the project
    const index_page = b.path("./README.md");
    const index_html = markdown2html(b, pandoc, index_page);
    _ = raw_outputs.addCopyFile(index_html, "index.html");

    const transform_source = b.addExecutable(.{ .name = "transform", .root_module = b.createModule(.{
        .root_source_file = b.path("transform.zig"),
        .target = b.graph.host,
    }) });

    const transformed_outputs = b.addWriteFiles();

    const transform_run = b.addRunArtifact(transform_source);
    transform_run.addDirectoryArg(raw_outputs.getDirectory());
    transform_run.addDirectoryArg(transformed_outputs.getDirectory());

    const write_transformed_step = b.addInstallDirectory(.{
        .source_dir = transformed_outputs.getDirectory(),
        .install_dir = .prefix,
        .install_subdir = ".",
    });

    transform_run.step.dependOn(&add_assets_step.step);
    write_transformed_step.step.dependOn(&transform_run.step);

    b.getInstallStep().dependOn(&write_transformed_step.step);
}

fn cut_prefix(text: []const u8, prefix: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, text, prefix))
        return text[prefix.len..];
    return null;
}

fn cut_suffix(text: []const u8, suffix: []const u8) ?[]const u8 {
    if (std.mem.endsWith(u8, text, suffix))
        return text[0 .. text.len - suffix.len];
    return null;
}

fn markdown2html(
    b: *std.Build,
    pandoc: std.Build.LazyPath,
    markdown: std.Build.LazyPath,
) std.Build.LazyPath {
    const pandoc_step = std.Build.Step.Run.create(b, "run pandoc");
    pandoc_step.addFileArg(pandoc);
    pandoc_step.addArgs(&.{ "--from=gfm+gfm_auto_identifiers", "--to=html5" });
    pandoc_step.addPrefixedFileArg("--lua-filter=", b.path("pandoc/anchor-links.lua"));
    pandoc_step.addFileArg(markdown);
    return pandoc_step.captureStdOut();
}
