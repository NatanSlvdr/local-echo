#!/usr/bin/env python3
"""Copy whisper-cli and its non-system dylibs into a relocatable app bundle."""

import shutil
import subprocess
import sys
from pathlib import Path


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def dependencies(binary):
    lines = run("otool", "-L", str(binary)).splitlines()[1:]
    if binary.suffix == ".dylib":
        lines = lines[1:]  # The first entry is the library's own install name.
    return [line.strip().split(" ", 1)[0] for line in lines]


def resolve(dependency, source):
    if dependency.startswith("@rpath/"):
        name = dependency.removeprefix("@rpath/")
        candidates = [source.parent / name, source.parent.parent / "lib" / name]
    elif dependency.startswith("@loader_path/"):
        candidates = [source.parent / dependency.removeprefix("@loader_path/")]
    else:
        candidates = [Path(dependency)]

    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()
    raise RuntimeError(f"Cannot resolve {dependency} required by {source}")


def is_system_library(dependency):
    return dependency.startswith(("/usr/lib/", "/System/Library/"))


def bundle(whisper_binary, app):
    macos = app / "Contents" / "MacOS"
    frameworks = app / "Contents" / "Frameworks"
    frameworks.mkdir(parents=True, exist_ok=True)

    whisper_source = whisper_binary.resolve()
    whisper_dest = macos / "whisper-cli"
    shutil.copy2(whisper_source, whisper_dest)

    pending = [(whisper_source, whisper_dest)]
    copied = {}
    signed = []
    sources = {whisper_source}
    plugins_added = False

    while pending:
        source, dest = pending.pop(0)
        for dependency in dependencies(source):
            if is_system_library(dependency):
                continue

            library_source = resolve(dependency, source)
            sources.add(library_source)
            name = Path(dependency).name
            if name in copied and copied[name] != library_source:
                raise RuntimeError(f"Conflicting library name: {name}")

            library_dest = frameworks / name
            if name not in copied:
                shutil.copy2(library_source, library_dest)
                copied[name] = library_source
                pending.append((library_source, library_dest))

            # ggml loads acceleration backends with dlopen, so otool cannot find them.
            if not plugins_added and name.startswith("libggml."):
                plugin_dir = library_source.parent.parent / "libexec"
                for plugin in plugin_dir.glob("libggml-*.so"):
                    plugin_dest = macos / plugin.name
                    shutil.copy2(plugin, plugin_dest)
                    plugin_source = plugin.resolve()
                    sources.add(plugin_source)
                    pending.append((plugin_source, plugin_dest))
                plugins_added = True

            relative = "@loader_path" if dest.parent == frameworks else "@loader_path/../Frameworks"
            subprocess.run(
                ["install_name_tool", "-change", dependency, f"{relative}/{name}", str(dest)],
                check=True,
            )

        if dest.suffix == ".dylib":
            subprocess.run(["install_name_tool", "-id", f"@rpath/{dest.name}", str(dest)], check=True)
        signed.append(dest)

    for binary in signed:
        subprocess.run(["codesign", "--force", "--sign", "-", str(binary)], check=True)

    licenses = app / "Contents" / "Resources" / "Licenses"
    for source in sources:
        package_dir = source.parents[1]
        for license_file in package_dir.glob("LICENSE*"):
            licenses.mkdir(parents=True, exist_ok=True)
            shutil.copy2(license_file, licenses / f"{package_dir.parent.name}.txt")
            break


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("Usage: bundle-whisper.py /path/to/whisper-cli /path/to/OpenWispr.app")
    bundle(Path(sys.argv[1]), Path(sys.argv[2]))
