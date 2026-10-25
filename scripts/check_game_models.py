"""Check sway adaptation and rest geometry for vanilla content or an author's models."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tempfile
import zipfile


@dataclass(frozen=True)
class Mod:
    namespace: str
    content: Path

    def resource(self, path: Path) -> str:
        return f"{self.namespace}::/{path.relative_to(self.content).as_posix()}"


def lua_string(value: str) -> str:
    escaped: list[str] = []
    for character in value:
        if character in ('"', "\\"):
            escaped.append("\\" + character)
        elif ord(character) < 32 or ord(character) == 127:
            escaped.append(f"\\{ord(character):03d}")
        else:
            escaped.append(character)
    return '"' + "".join(escaped) + '"'


def read_mod(path: Path, namespace: str | None = None) -> Mod:
    folder = path.parent if path.is_file() else path
    for parent in (folder, *folder.parents):
        manifest = parent / "mod.json"
        if manifest.is_file():
            metadata = json.loads(manifest.read_text(encoding="utf-8-sig"))
            mod_id = metadata.get("modId") if isinstance(metadata, dict) else None
            if not isinstance(mod_id, str) or not re.fullmatch(r"[\w.-]+", mod_id):
                raise ValueError(f"Invalid modId in {manifest}")
            if namespace is not None and namespace != mod_id:
                raise ValueError(f"--namespace conflicts with {manifest}: {mod_id}")
            content = parent / "content"
            return Mod(mod_id, content if content.is_dir() else parent)
    if not path.is_file() or path.suffix != ".mdl":
        raise ValueError(f"No mod.json found for {path}; a standalone target must be a .mdl file")
    mod_id = namespace or "author_model"
    if not re.fullmatch(r"[\w.-]+", mod_id):
        raise ValueError(f"Invalid namespace: {mod_id}")
    return Mod(mod_id, folder)


def extract_base(game: Path, staging: Path, include_models: bool) -> list[str]:
    base = game / "base/content"
    resources: set[str] = set()

    def vanilla_model(path: PurePosixPath) -> bool:
        return (include_models and path.suffix == ".mdl"
                and path.parts[:2] in (("vehicle", "train"), ("vehicle", "waggon"), ("vehicle", "tram")))

    def included(path: PurePosixPath) -> bool:
        return path.suffix in (".lua", ".tl") or vanilla_model(path)

    if not base.is_dir():
        if include_models:
            raise ValueError(f"Game content not found: {base}; use --game-dir")
        return []
    for archive in sorted(base.rglob("*.zip")):
        folder = archive.parent.relative_to(base)
        with zipfile.ZipFile(archive) as zipped:
            for member in sorted(zipped.namelist()):
                relative = PurePosixPath(member)
                if relative.is_absolute() or ".." in relative.parts:
                    raise ValueError(f"Invalid archive member: {archive}: {member}")
                resource_path = PurePosixPath(folder.as_posix()) / relative
                if not included(resource_path):
                    continue
                target = staging / resource_path
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(zipped.read(member))
                if vanilla_model(resource_path):
                    resources.add("::/" + resource_path.as_posix())
    # Unpacked game content takes precedence over archived resources.
    for source in base.rglob("*"):
        relative = PurePosixPath(source.relative_to(base).as_posix())
        if not included(relative) or not source.is_file():
            continue
        target = staging / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        if vanilla_model(relative):
            resources.add("::/" + relative.as_posix())
    return sorted(resources)


def lua_environment() -> dict[str, str]:
    environment = os.environ.copy()
    compiler = shutil.which(os.environ.get("TL", "tl"))
    if compiler is None:
        candidate = Path.home() / ".luarocks/bin/tl"
        compiler = str(candidate) if candidate.is_file() else None
    if compiler:
        # Teal is pure Lua; expose its installation to a different standalone Lua version.
        share = Path(compiler).absolute().parent.parent / "share/lua"
        paths = [str(folder / pattern) for folder in sorted(share.glob("*")) for pattern in ("?.lua", "?/init.lua")]
        environment["LUA_PATH"] = ";".join([*paths, environment.get("LUA_PATH", ";;")])
    return environment


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", nargs="?", type=Path, help=".mdl file, mod directory, or content directory; omit for vanilla")
    parser.add_argument("--dependency", action="append", default=[], type=Path, help="mod directory supplying required resources; repeat as needed")
    parser.add_argument("--namespace", help="resource namespace for a standalone .mdl without mod.json")
    parser.add_argument("--strict", action="store_true", help="also fail on skipped rail models or adaptation warnings")
    parser.add_argument("--verbose", action="store_true", help="show per-LOD adaptation details and resource diagnostics")
    parser.add_argument("--game-dir", type=Path, default=Path(os.environ.get(
        "TPF3_GAME_DIR", Path.home() / ".local/share/Steam/steamapps/common/Transport Fever 3")))
    args = parser.parse_args()
    repository = Path(__file__).resolve().parent.parent
    target: Path | None = args.target.resolve() if args.target else None
    if args.namespace and target is None:
        parser.error("--namespace requires a target model")
    try:
        mods: list[Mod] = []
        for dependency in args.dependency:
            if not dependency.is_dir():
                raise ValueError(f"Dependency directory not found: {dependency}")
            mods.append(read_mod(dependency.resolve()))
        resources: list[str] = []
        if target is not None:
            if not target.exists():
                raise ValueError(f"Target not found: {target}")
            if target.is_file() and target.suffix != ".mdl":
                raise ValueError(f"Target must be a .mdl file: {target}")
            owner = read_mod(target, args.namespace)
            mods.append(owner)
            folder = owner.content if owner.content.is_relative_to(target) else target
            models = [target] if target.is_file() else sorted(folder.rglob("*.mdl"))
            resources = [owner.resource(model) for model in models]
            if not resources:
                raise ValueError("No model files found")
        roots: dict[str, Path] = {}
        for mod in mods:
            if mod.namespace == "apasz_swaying_waying":
                raise ValueError("The checker loads Swaying Waying from this checkout; do not supply it as a dependency")
            if mod.namespace in roots and roots[mod.namespace] != mod.content:
                raise ValueError(f"Conflicting resource namespace: {mod.namespace}")
            roots[mod.namespace] = mod.content
        with tempfile.TemporaryDirectory(prefix="swaying-models-") as directory:
            staging = Path(directory)
            roots[""] = staging / "base"
            vanilla_resources = extract_base(args.game_dir, roots[""], target is None)
            if target is None:
                resources = vanilla_resources
            if not resources:
                raise ValueError("No model files found")
            manifest = staging / "models.lua"
            manifest.write_text("return {\nroots = {" + ",".join(
                f"[{lua_string(namespace)}]={lua_string(str(root))}" for namespace, root in roots.items()
            ) + "},\nresources = {" + ",".join(map(lua_string, resources)) + "},\n"
                + f"strict = {str(args.strict).lower()}, verbose = {str(args.verbose).lower()}, author = {str(target is not None).lower()}\n}}\n",
                encoding="utf-8")
            completed = subprocess.run(["lua", "scripts/check_game_models.lua", str(manifest)],
                                       cwd=repository, env=lua_environment(), check=False)
            return completed.returncode
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        parser.error(str(error))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
