"""Exercise the public author checker with files, dependencies and failing models."""

from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest
import zipfile


REPOSITORY = Path(__file__).resolve().parents[1]
MODEL = """
return {
    lods = {{visibleTo = 400, node = {name = "body", mesh = "body.msh"}}},
    metadata = {
        transportVehicle = {carrier = "RAIL"}, railVehicle = {},
        swayingWaying = {sections = {{group = "body", lag = 0}}},
        transformatorConfig = {transformator = {name = "dependency::/custom.trf"}},
    },
}
"""
TRANSFORMATOR = 'return {updateScript = {fileName = "callback.lua@update"}}'
CALLBACK = 'return {update = function() return {} end}'


class ModelCheckerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="sway-checker-tests-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.game = self.root / "game"
        self.mod = self.create_mod("author")
        self.dependency = self.create_mod("dependency")
        (self.dependency / "custom.trf.lua").write_text(TRANSFORMATOR)
        (self.dependency / "callback.lua").write_text(CALLBACK)
        self.model = self.mod / 'vehicle/train/author "test".mdl'
        self.model.parent.mkdir(parents=True)
        self.model.write_text('function data() return ug_require("shared.lua") end')
        (self.model.parent / "shared.lua").write_text(MODEL)

    def create_mod(self, namespace: str) -> Path:
        root = self.root / namespace
        content = root / "content"
        content.mkdir(parents=True)
        (root / "mod.json").write_text(json.dumps({"modId": namespace}))
        return content

    def run_checker(self, *arguments: str | Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, "scripts/check_game_models.py", "--game-dir", str(self.game), *map(str, arguments)],
            cwd=REPOSITORY, text=True, capture_output=True, check=False,
        )

    def test_model_and_mod_directory_with_dependency(self) -> None:
        for target in (self.model, self.mod, self.mod.parent):
            with self.subTest(target=target):
                result = self.run_checker(target, "--dependency", self.dependency, "--strict", "--verbose")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("1 adapted", result.stdout)
                self.assertIn("LOD 0: applied", result.stdout)

    def test_missing_dependency_and_invalid_author_field(self) -> None:
        missing = self.run_checker(self.model, "--strict", "--verbose")
        self.assertEqual(missing.returncode, 1, missing.stdout)
        self.assertIn("--dependency", missing.stdout)
        self.model.write_text(MODEL.replace("lag = 0", "lag = -1"))
        invalid = self.run_checker(self.model, "--strict")
        self.assertEqual(invalid.returncode, 1, invalid.stdout)
        self.assertIn("swayingWaying.sections[1].lag", invalid.stdout)

    def test_teal_callback_resource(self) -> None:
        (self.dependency / "custom.trf.lua").write_text(TRANSFORMATOR.replace("callback.lua", "callback.tl"))
        (self.dependency / "callback.tl").write_text("local function update(): {any}\n return {}\nend\nreturn {update = update}")
        result = self.run_checker(self.model, "--dependency", self.dependency, "--strict")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("1 adapted", result.stdout)

    def test_delayed_relative_import_keeps_its_resource_namespace(self) -> None:
        (self.dependency / "custom.trf.lua").write_text(
            'return {data = function() return ug_require("settings.lua") end}')
        (self.dependency / "settings.lua").write_text(TRANSFORMATOR)
        (self.dependency / "callback.lua").write_text(
            'return {data = function() return require("callbacks/update.lua") end}')
        (self.dependency / "callbacks").mkdir()
        (self.dependency / "callbacks/update.lua").write_text(CALLBACK)
        result = self.run_checker(self.model, "--dependency", self.dependency, "--strict")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("1 adapted", result.stdout)

    def test_mod_directory_ignores_models_outside_content(self) -> None:
        (self.mod.parent / "backup.mdl").write_text("error('not game content')")
        result = self.run_checker(self.mod.parent, "--dependency", self.dependency, "--strict")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("1 adapted", result.stdout)

    def test_opt_out_is_successful_in_strict_mode(self) -> None:
        self.model.write_text(MODEL.replace('carrier = "RAIL"', 'carrier = "RAIL", filterTags = {"swaying_waying_none"}'))
        result = self.run_checker(self.model, "--strict")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("1 opted out", result.stdout)

    def test_camera_tags_are_classified_in_strict_mode(self) -> None:
        cases = (
            ('"swaying_waying_only_camera"', "1 camera-only"),
            ('"swaying_waying_only_camera", "swaying_waying_no_camera"', "1 opted out"),
            ('"swaying_waying_only_camera", "swaying_waying_none"', "1 opted out"),
            ('"swaying_waying_no_camera"', "1 adapted"),
        )
        for tags, expected in cases:
            with self.subTest(tags=tags):
                self.model.write_text(MODEL.replace('carrier = "RAIL"', f'carrier = "RAIL", filterTags = {{{tags}}}'))
                result = self.run_checker(self.model, "--dependency", self.dependency, "--strict")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(expected, result.stdout)

    def test_errors_do_not_hide_other_models(self) -> None:
        (self.model.parent / "broken.mdl").write_text("error('broken model factory')")
        result = self.run_checker(self.mod, "--dependency", self.dependency)
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertIn("1 adapted", result.stdout)
        self.assertIn("broken model factory", result.stdout)
        self.assertIn("1 failed", result.stdout)

    def test_namespace_conflicts_and_missing_targets(self) -> None:
        result = self.run_checker(self.model, "--namespace", "wrong")
        self.assertEqual(result.returncode, 2)
        self.assertIn("conflicts", result.stderr)
        result = self.run_checker(self.root / "missing.mdl")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Target not found", result.stderr)

    def test_standalone_model_with_namespace(self) -> None:
        model = self.root / "standalone.mdl"
        model.write_text(MODEL)
        result = self.run_checker(model, "--namespace", "standalone", "--dependency", self.dependency, "--strict")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("Adapted: standalone::/standalone.mdl", result.stdout)

    def test_vanilla_archive_mode_remains_supported(self) -> None:
        folder = self.game / "base/content/vehicle/train"
        folder.mkdir(parents=True)
        with zipfile.ZipFile(folder / "fixture.zip", "w") as archive:
            archive.writestr("test.mdl", MODEL.replace("dependency::/custom.trf", "::/vehicle/train/custom.trf"))
            archive.writestr("custom.trf.lua", TRANSFORMATOR)
            archive.writestr("callback.lua", CALLBACK)
        result = self.run_checker("--strict")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("1 adapted", result.stdout)

    def test_unpacked_vanilla_models_override_and_deduplicate_archives(self) -> None:
        folder = self.game / "base/content/vehicle/train"
        folder.mkdir(parents=True)
        for name in ("first.zip", "second.zip"):
            with zipfile.ZipFile(folder / name, "w") as archive:
                archive.writestr("test.mdl", "error('overridden archived model')")
        for name in ("test.mdl", "unpacked.mdl"):
            (folder / name).write_text(MODEL)
        result = self.run_checker("--dependency", self.dependency, "--strict")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("2 adapted", result.stdout)


if __name__ == "__main__":
    unittest.main()
