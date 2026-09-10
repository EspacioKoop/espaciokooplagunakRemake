"""Build and run the actual Compose service with real native clients. Requires Docker."""
from pathlib import Path
import json
import os
import re
import subprocess
import tempfile
from run_dedicated_server import ROOT, free_port, read_save, run_peer

def main():
    with tempfile.TemporaryDirectory(prefix="lagunak-container-") as temporary:
        directory = Path(temporary)  # 0700 enclosing directory protects the host secret.
        key = directory / "session-key"
        key.write_text("synthetic-container-key-0123456789")
        key.chmod(0o444)  # Bind-mounted file must be readable by container UID 10001.
        port = free_port()
        env = {**os.environ, "LAGUNAK_KEY_FILE": str(key), "LAGUNAK_HOST_PORT": str(port), "LAGUNAK_BIND_ADDRESS": "127.0.0.1", "LAGUNAK_LOAD_MODE": "auto", "LAGUNAK_MISSION_INDEX": "-1"}
        prefix = ["docker", "compose", "--project-name", "lagunak-smoke-" + str(os.getpid()), "--file", str(ROOT / "compose.yaml")]
        def compose(*args, check=True, timeout=60):
            result = subprocess.run([*prefix, *args], env=env, text=True, capture_output=True, timeout=timeout)
            if check:
                assert result.returncode == 0, result.stdout + result.stderr
            return result
        def inspect(container):
            return json.loads(subprocess.check_output(["docker", "inspect", container], text=True))[0]
        try:
            compose("build", timeout=360)
            rendered = compose("config", "--format", "json").stdout
            assert key.read_text() not in rendered
            run_id = ""
            for mode in ["command", "resume"]:
                compose("up", "-d", "--wait", "--wait-timeout", "45")
                container = compose("ps", "-q", "lagunak").stdout.strip()
                details = inspect(container)
                assert details["State"]["Health"]["Status"] == "healthy"
                assert details["Config"]["User"] == "10001:10001"
                assert details["HostConfig"]["ReadonlyRootfs"]
                assert details["HostConfig"]["CapDrop"] == ["ALL"]
                assert set(details["NetworkSettings"]["Ports"]) == {"27840/udp"}
                assert details["NetworkSettings"]["Ports"]["27840/udp"][0]["HostIp"] == "127.0.0.1"
                assert key.read_text() not in json.dumps(details)
                peer_env = {**env, "XDG_DATA_HOME": str(directory / "client"), "LAGUNAK_TEST_PORT": str(port), "LAGUNAK_TEST_ADDRESS": "127.0.0.1", "LAGUNAK_TEST_RUN": run_id}
                if mode == "command": run_peer(peer_env, "bad")
                run_id = run_peer(peer_env, mode)
                compose("stop", "--timeout", "20")
                assert inspect(container)["State"]["ExitCode"] == 0
                logs = compose("logs", "--no-color").stdout
                assert "SERVER_STOPPED saved=true" in logs
                assert not re.search(r"(?:SCRIPT ERROR|ERROR):", logs), logs
                assert key.read_text() not in logs
                destination = directory / mode
                destination.mkdir()
                subprocess.run(["docker", "cp", container + ":/var/lib/lagunak/.", str(destination)], check=True)
                saves = list(destination.rglob("campaign.json"))
                assert len(saves) == 1
                saved = read_save(saves[0])
                assert saved["run_id"] == run_id and saved["ship"]["alert"] == "roja"
            # Invalid external configuration fails before hosting or modifying the volume.
            key.chmod(0o600)
            key.write_text("short")
            key.chmod(0o444)
            invalid = compose("run", "--rm", "-T", "--no-deps", "lagunak", check=False)
            assert invalid.returncode == 2 and "SERVER_CONFIG_ERROR" in invalid.stderr + invalid.stdout
            print("DOCKER_OK actual build/healthy/nonroot/read-only/UDP/authentication/graceful stop/persisted restart/invalid key")
        finally:
            compose("down", "--volumes", "--remove-orphans", check=False)

if __name__ == "__main__": main()
