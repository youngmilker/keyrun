"""Harmless integration tests. All resources and IDEs are temporary fixtures.

Run: python3 tests/test-unix.py
No real JARs are executed, IDEs scanned, shell profiles sourced or GUI apps opened.
"""
import functools
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time
import unittest


REPO = Path(__file__).resolve().parents[1]
CODE = ["resource-loader.sh", "keyrun.sh", "switch-source.sh",
        "scripts/platform-paths.sh", "scripts/install.sh", "scripts/install-unix.sh",
        "scripts/diagnose-idea-paths.sh", "scripts/build-server-bootstrap.sh",
        "scripts/server-bootstrap.template.sh"]
PRODUCTS = "idea clion phpstorm goland pycharm webstorm rider datagrip rubymine appcode dataspell rustrover".split()


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path == "/redirect":
            self.send_response(302)
            self.send_header("Location", "/README.md")
            self.end_headers()
        elif self.path == "/slow":
            time.sleep(2)
            try:
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"slow")
            except (BrokenPipeError, ConnectionResetError):
                pass
        else:
            super().do_GET()


class UnixTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="keyrun-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / "中文 project"
        self.repo.mkdir()
        for rel in CODE:
            dest = self.repo / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / rel, dest)
        self.home = self.root / "user home"
        self.home.mkdir()
        self.bin = self.root / "fake-bin"
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), PATH=f"{self.bin}:{os.environ['PATH']}")
        for key in list(self.env):
            if key.startswith("XDG_") or key.endswith(("_VM_OPTIONS", "_PROPERTIES")):
                del self.env[key]
        self.env["TMPDIR"] = str(self.root)
        self.env["KEYRUN_APPLICATIONS_DIR"] = str(self.root / "system-applications")
        self.env["KEYRUN_OPT_DIR"] = str(self.root / "system-opt")
        self.write_executable("launchctl", '#!/bin/bash\n[ "$1" != getenv ] || exit 0\nexit 0\n')
        self.platform("Darwin")
        self.config()
        (self.repo / "README.md").write_bytes(b"\xef\xbb\xbf" + "中文资源\n第二行".encode())
        (self.repo / "binary.bin").write_bytes(bytes(range(256)) + b"\x00\xff\x80")
        (self.repo / "data.json").write_text('{"name":"中文","number":42}', encoding="utf-8")
        resources = ["ja-netfilter/ja-netfilter.jar"]
        resources += [f"ja-netfilter/config/{n}.conf" for n in "dns env native power url".split()]
        resources += [f"ja-netfilter/plugins/{n}.jar" for n in "dns env native power url hideme privacy".split()]
        resources += [f"licenses/{n}.key" for n in PRODUCTS]
        self.resources = resources
        for rel in resources:
            path = self.repo / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"fixture:\x00\xff:" + rel.encode())

    def config(self, **kwargs):
        data = dict(mode="local", localRoot=".", httpBase="http://127.0.0.1:1", timeoutSeconds=1)
        data.update(kwargs)
        (self.repo / "source-config.json").write_text(json.dumps(data), encoding="utf-8")

    def write_executable(self, name, content):
        path = self.bin / name
        path.write_text(content, encoding="utf-8")
        path.chmod(0o755)

    def platform(self, name):
        self.write_executable("uname", f"#!/bin/bash\nprintf '%s\\n' '{name}'\n")
        if name == "Darwin":
            self.config_root = self.home / "Library/Application Support/JetBrains"
            self.cache_root = self.home / "Library/Caches/JetBrains"
        else:
            self.config_root = Path(self.env.get("XDG_CONFIG_HOME", self.home / ".config")) / "JetBrains"
            self.cache_root = Path(self.env.get("XDG_CACHE_HOME", self.home / ".cache")) / "JetBrains"
        self.os_name = name

    def cli(self, *args, script="keyrun.sh", ok=True, input=None, cwd=None):
        result = subprocess.run(["/bin/bash", str(self.repo / script), *args], env=self.env,
                                cwd=cwd or self.root, input=input, capture_output=True, timeout=30)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout.decode(errors="replace") + result.stderr.decode(errors="replace"))
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout.decode(errors="replace"))
        return result

    def ide(self, version="IntelliJIdea2026.2", existing=True):
        config = self.config_root / version
        config.mkdir(parents=True, exist_ok=True)
        install = self.home / "Applications" / f"{version}.app" if self.os_name == "Darwin" else self.home / "IDE" / version
        bin_dir = install / "Contents/bin" if self.os_name == "Darwin" else install / "bin"
        bin_dir.mkdir(parents=True, exist_ok=True)
        filename = "idea.vmoptions" if self.os_name == "Darwin" else "idea64.vmoptions"
        template = bin_dir / filename
        template.write_bytes(b"-Xmx2048m\r\n-Dfixture=true")  # no final newline
        (bin_dir / "idea.properties").write_text("# fixture\n", encoding="utf-8")
        cache = self.cache_root / version
        cache.mkdir(parents=True, exist_ok=True)
        (cache / ".home").write_text(str(install) + "\n", encoding="utf-8")
        vm = config / filename
        if existing:
            vm.write_bytes(b"-Xmx4096m\n-javaagent:/old/ja-netfilter.jar\n-javaagent:/other/agent.jar")
        (config / "idea.key").write_bytes(b"previous-key\x00\xff")
        (config / "disabled_plugins.txt").write_text("com.intellij.modules.ultimate\nkeep.plugin\n", encoding="utf-8")
        return config, vm, install, template

    def server(self):
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(Handler, directory=str(self.repo)))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return f"http://127.0.0.1:{server.server_port}"

    def snapshot(self, root):
        return {str(p.relative_to(root)): p.read_bytes() for p in root.rglob("*") if p.is_file() and ".jb_run" not in p.parts}

    def test_local_text_json_and_binary_from_other_cwd(self):
        self.assertEqual(self.cli().stdout, "中文资源\n第二行".encode())
        self.assertEqual(self.cli("--resource-path", "binary.bin", "--format", "bytes").stdout,
                         (self.repo / "binary.bin").read_bytes())
        self.assertEqual(json.loads(self.cli("--resource-path", "data.json", "--format", "json").stdout)["number"], 42)

    def test_invalid_utf8_and_multiple_json_values(self):
        self.cli("--resource-path", "binary.bin", ok=False)
        (self.repo / "data.json").write_text('{} {}', encoding="utf-8")
        self.cli("--resource-path", "data.json", "--format", "json", ok=False)

    def test_invalid_resource_paths_and_symlink(self):
        for path in ["../LICENSE", "/README.md", "a//b", "./a", "a?b", "a:b", "a\\b", "a. /b", "x\nfile", "README.md/"]:
            with self.subTest(path=path):
                self.cli("--resource-path", path, ok=False)
        (self.repo / "linked").symlink_to(self.home, target_is_directory=True)
        self.cli("--resource-path", "linked/secret", ok=False)

    def test_invalid_configuration(self):
        for values in [dict(mode="other"), dict(timeoutSeconds=0), dict(timeoutSeconds=True), dict(timeoutSeconds=1.5), dict(localRoot=4)]:
            with self.subTest(values=values):
                self.config(**values)
                self.cli(ok=False)

    def test_switch_local_does_not_need_server_or_change_bootstrap(self):
        (self.repo / "sh").write_text("preserve", encoding="utf-8")
        self.cli("--mode", "local", script="switch-source.sh")
        self.assertEqual((self.repo / "sh").read_text(), "preserve")
        self.assertEqual(json.loads((self.repo / "source-config.json").read_text())["httpBase"], "http://127.0.0.1:1")

    def test_invalid_switch_does_not_change_files(self):
        before = (self.repo / "source-config.json").read_bytes()
        for base in ["ftp://host/root", "http://http://host", "https://user:pass@host/root", "https://host/q?x=1", "https://host/#x", "https://host:99999", "https://host/path with space"]:
            with self.subTest(base=base):
                self.cli("--mode", "http", "--http-base", base, script="switch-source.sh", ok=False)
                self.assertEqual((self.repo / "source-config.json").read_bytes(), before)

    def test_http_resources_redirect_errors_and_timeout(self):
        base = self.server()
        self.config(mode="http", httpBase=base)
        self.assertEqual(self.cli().stdout, "中文资源\n第二行".encode())
        self.assertEqual(self.cli("--resource-path", "binary.bin", "--format", "bytes").stdout, (self.repo / "binary.bin").read_bytes())
        (self.repo / "中文 空格.txt").write_text("编码路径", encoding="utf-8")
        self.assertEqual(self.cli("--resource-path", "中文 空格.txt").stdout, "编码路径".encode())
        for resource in ["redirect", "missing", "slow"]:
            result = self.cli("--resource-path", resource, ok=False)
            self.assertEqual(result.stdout, b"")

    def test_diagnosis_expands_home_and_relative_paths_without_writes(self):
        config, _, _, _ = self.ide()
        props = config / "idea.properties"
        props.write_text("idea.config.path=${user.home}/custom config\nidea.system.path=../cache\n", encoding="utf-8")
        before = self.snapshot(self.home)
        result = self.cli("--diagnose-idea-paths", "--properties-path", str(props))
        self.assertIn(str(self.home / "custom config").encode(), result.stdout)
        self.assertIn(str(config.parent / "cache").encode(), result.stdout)
        self.assertEqual(before, self.snapshot(self.home))

    def test_diagnosis_continues_after_bad_property(self):
        config, _, _, _ = self.ide()
        props = config / "idea.properties"
        props.write_text("idea.config.path=${unknown}/bad\nidea.system.path=/valid\n", encoding="utf-8")
        result = self.cli("--diagnose-idea-paths", "--properties-path", str(props), ok=False)
        self.assertIn(b"/valid", result.stdout)

    def test_dry_run_both_platforms_changes_nothing(self):
        for platform in ["Darwin", "Linux"]:
            with self.subTest(platform=platform):
                self.platform(platform)
                self.ide()
                before = self.snapshot(self.home)
                self.cli("--install", "--dry-run")
                self.assertEqual(self.snapshot(self.home), before)
                self.assertFalse((self.home / ".jb_run").exists())

    def test_native_platform_entry(self):
        self.platform(os.uname().sysname)
        (self.bin / "uname").unlink()
        _, vm, _, _ = self.ide()
        self.cli("--install", "--yes")
        self.assertIn("/.jb_run/ja-netfilter.jar", vm.read_text())

    def test_install_preserves_options_and_keys_with_backup_and_idempotence(self):
        config, vm, _, _ = self.ide()
        original = vm.read_bytes()
        profile = self.home / ".zshrc"
        profile.write_text('export IDEA_VM_OPTIONS="/old/options"\nexport KEEP=1\n', encoding="utf-8")
        self.cli("--install", "--yes")
        content = vm.read_text()
        self.assertIn("-Xmx4096m", content)
        self.assertIn("-javaagent:/other/agent.jar\n", content)
        self.assertNotIn("/old/ja-netfilter.jar", content)
        self.assertEqual((config / "idea.key").read_bytes(), (self.repo / "licenses/idea.key").read_bytes())
        self.assertEqual(profile.read_text(), "export KEEP=1\n")
        self.assertEqual((config / "disabled_plugins.txt").read_text(), "keep.plugin\n")
        backups = list((self.home / ".jb_run/backups").glob("run-*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / ("files" + str(vm))).read_bytes(), original)
        self.cli("--install", "--yes")
        self.assertEqual(vm.read_text().count("/.jb_run/ja-netfilter.jar"), 1)
        self.assertEqual(vm.read_text(), content)

    def test_linux_xdg_and_copy_installed_template(self):
        self.env["XDG_CONFIG_HOME"] = str(self.home / "xdg config")
        self.env["XDG_CACHE_HOME"] = str(self.home / "xdg cache")
        self.platform("Linux")
        _, vm, _, template = self.ide(existing=False)
        original = template.read_bytes()
        self.cli("--install", "--yes")
        self.assertTrue(vm.name.endswith("64.vmoptions"))
        self.assertIn("-Xmx2048m\n-Dfixture=true\n", vm.read_text())
        self.assertEqual(template.read_bytes(), original)

    def test_metadata_discovery_without_cache_or_existing_config(self):
        config, vm, install, _ = self.ide(existing=False)
        shutil.rmtree(self.cache_root)
        shutil.rmtree(config)
        info = install / "Contents/Resources/product-info.json"
        info.parent.mkdir(parents=True)
        info.write_text(json.dumps(dict(dataDirectoryName=config.name)), encoding="utf-8")
        self.cli("--install", "--yes")
        self.assertTrue(vm.is_file())

    def test_duplicate_discovery_of_same_app_is_deduplicated(self):
        config, vm, install, _ = self.ide(existing=False)
        shutil.rmtree(config)
        # Both .home and ~/Applications resolve to this same application bin.
        info = install / "Contents/Resources/product-info.json"
        info.parent.mkdir(parents=True)
        info.write_text(json.dumps(dict(dataDirectoryName=config.name)), encoding="utf-8")
        self.cli("--install", "--yes")
        self.assertTrue(vm.is_file())

    def test_custom_config_and_explicit_install(self):
        config, _, install, _ = self.ide(existing=False)
        custom = self.home / "custom-config"
        (config / "idea.properties").write_text("idea.config.path=${user.home}/custom-config\n", encoding="utf-8")
        self.cli("--install", "--yes", "--config-dir", str(config), "--product", "idea", "--ide-home", str(install))
        self.assertTrue((custom / "idea.vmoptions").is_file())
        self.assertFalse((config / "idea.vmoptions").exists())

    def test_properties_merge_and_environment_precedence(self):
        config, _, install, template = self.ide(existing=False)
        custom = self.home / "bundled-custom"
        (template.parent / "idea.properties").write_text("idea.config.path=${user.home}/bundled-custom\n", encoding="utf-8")
        (config / "idea.properties").write_text("idea.other.property=true\n", encoding="utf-8")
        args = ("--install", "--yes", "--config-dir", str(config), "--product", "idea", "--ide-home", str(install))
        self.cli(*args)
        self.assertTrue((custom / "idea.vmoptions").exists())
        env_props = self.home / "env/idea.properties"
        env_props.parent.mkdir()
        env_props.write_text("idea.config.path=${user.home}/env-custom\n", encoding="utf-8")
        self.env["IDEA_PROPERTIES"] = str(env_props)
        self.cli(*args)
        self.assertTrue((self.home / "env-custom/idea.vmoptions").exists())

    def test_timeout_validation_and_bootstrap_shell_quoting(self):
        for timeout in ["0", "301", "08", "true", "1.5"]:
            with self.subTest(timeout=timeout):
                self.cli("--mode", "local", "--timeout-seconds", timeout, script="switch-source.sh", ok=False)
        base = "https://example.test/quote'&literal$(false)"
        self.cli("--mode", "http", "--http-base", base, script="switch-source.sh")
        self.assertEqual((self.repo / "sh").stat().st_mode & 0o777, 0o644)
        line = next(line for line in (self.repo / "sh").read_text().splitlines() if line.startswith("KR_BOOT_BASE="))
        result = subprocess.run(["/bin/bash", "-c", line + '\n: "$KR_BOOT_BASE"\nprintf "%s" "$KR_BOOT_BASE"'], capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.decode(), base)

    def test_missing_resource_prevents_all_changes(self):
        self.ide()
        before = self.snapshot(self.home)
        (self.repo / "licenses/rustrover.key").unlink()
        self.cli("--install", "--yes", ok=False)
        self.assertEqual(self.snapshot(self.home), before)
        self.assertFalse((self.home / ".jb_run").exists())

    def test_empty_resource_prevents_all_changes(self):
        self.ide()
        before = self.snapshot(self.home)
        (self.repo / "ja-netfilter/config/url.conf").write_bytes(b"")
        self.cli("--install", "--yes", ok=False)
        self.assertEqual(self.snapshot(self.home), before)

    def test_existing_install_lock_prevents_writes(self):
        self.ide()
        lock = self.home / ".jb_run/.install-lock"
        lock.mkdir(parents=True)
        before = self.snapshot(self.home)
        self.cli("--install", "--yes", ok=False)
        self.assertEqual(self.snapshot(self.home), before)
        self.assertTrue(lock.exists())

    def test_launchctl_failure_restores_files(self):
        self.ide()
        before = self.snapshot(self.home)
        self.write_executable("launchctl", '#!/bin/bash\ncase "$1" in getenv) echo /previous/options;; unsetenv) exit 1;; esac\n')
        self.cli("--install", "--yes", ok=False)
        self.assertEqual(self.snapshot(self.home), before)

    def test_symlink_write_rejected(self):
        config, vm, _, _ = self.ide()
        outside = self.home / "outside.vmoptions"
        outside.write_bytes(vm.read_bytes())
        vm.unlink()
        vm.symlink_to(outside)
        self.cli("--install", "--yes", ok=False)
        self.assertNotIn(b"/.jb_run/", outside.read_bytes())

    def test_complex_profile_is_not_sourced_or_modified(self):
        self.ide()
        marker = self.home / "must-not-exist"
        profile = self.home / ".zshrc"
        profile.write_text(f'export IDEA_VM_OPTIONS="/old"; touch "{marker}"\n', encoding="utf-8")
        before = self.snapshot(self.home)
        self.cli("--install", "--yes", ok=False)
        self.assertEqual(self.snapshot(self.home), before)
        self.assertFalse(marker.exists())

    def test_failed_write_restores_previous_files(self):
        self.ide()
        before = self.snapshot(self.home)
        real_mv = shutil.which("mv")
        marker = self.root / "failed-once"
        self.write_executable("mv", f'''#!/bin/bash
case "${{@: -1}}" in */idea.key)
    if [ ! -e '{marker}' ]; then touch '{marker}'; exit 42; fi;;
esac
exec '{real_mv}' "$@"
''')
        self.cli("--install", "--yes", ok=False)
        self.assertEqual(self.snapshot(self.home), before)
        self.assertFalse((self.home / ".jb_run/ja-netfilter.jar").exists())

    def test_http_installer_stages_all_resources(self):
        self.platform("Linux")
        config, vm, _, _ = self.ide()
        self.config(mode="http", httpBase=self.server())
        self.cli("--install", "--yes")
        self.assertIn("/.jb_run/ja-netfilter.jar", vm.read_text())
        self.assertEqual((config / "idea.key").read_bytes(), (self.repo / "licenses/idea.key").read_bytes())

    def test_bootstrap_from_empty_directory_and_hash_rejection(self):
        self.platform("Linux")
        self.ide()
        base = self.server()
        self.cli("--mode", "http", "--http-base", base, script="switch-source.sh")
        empty = self.root / "empty"
        empty.mkdir()
        # Pipe exactly as a remote user would; --dry-run avoids persistent changes.
        payload = (self.repo / "sh").read_bytes()
        result = subprocess.run(["/bin/bash", "-s", "--", "--dry-run"], input=payload,
                                cwd=empty, env=self.env, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertIn(base.encode(), result.stdout)
        self.assertEqual(list(empty.iterdir()), [])
        self.assertEqual(list(self.root.glob("keyrun-http.*")), [])
        with (self.repo / "keyrun.sh").open("a") as file:
            file.write("\n# tampered\n")
        result = subprocess.run(["/bin/bash", "-s", "--", "--yes"], input=payload,
                                cwd=empty, env=self.env, capture_output=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"SHA-256 mismatch", result.stderr)
        self.assertFalse((self.home / ".jb_run").exists())
        self.assertEqual(list(self.root.glob("keyrun-http.*")), [])

    def test_bootstrap_actual_install_and_missing_resource(self):
        self.platform("Linux")
        _, vm, _, _ = self.ide()
        base = self.server()
        self.cli("--mode", "http", "--http-base", base, script="switch-source.sh")
        payload = (self.repo / "sh").read_bytes()
        missing = self.repo / "licenses/rustrover.key"
        original = missing.read_bytes()
        missing.unlink()
        before = self.snapshot(self.home)
        result = subprocess.run(["/bin/bash", "-s", "--", "--yes"], input=payload,
                                cwd=self.root, env=self.env, capture_output=True, timeout=30)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(before, self.snapshot(self.home))
        self.assertFalse((self.home / ".jb_run").exists())
        missing.write_bytes(original)
        result = subprocess.run(["/bin/bash", "-s", "--", "--yes"], input=payload,
                                cwd=self.root, env=self.env, capture_output=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertIn("/.jb_run/ja-netfilter.jar", vm.read_text())
        self.assertEqual(list(self.root.glob("keyrun-http.*")), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
