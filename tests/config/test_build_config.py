"""Provider activation must match Decidealot's enabled-by-default CLM contract."""

import runpy
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

BUILD_CONFIG = runpy.run_path(
    str(Path(__file__).resolve().parents[2] / "litellm/build-config.py")
)
ENCODER_PROVIDER = "llamacpp-cuda"
ENCODER_MODEL = "local-llamacpp-cuda-qwen3-8b"


class DecidealotEncoderActivationTest(unittest.TestCase):
    def test_generated_ollama_configuration_keeps_phi_cpu_only(self):
        repository = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            litellm = workspace / "litellm"
            shutil.copytree(repository / "litellm/config", litellm / "config")
            shutil.copyfile(
                repository / "litellm/build-config.py", litellm / "build-config.py"
            )
            (workspace / ".env").write_text(
                "OLLAMA=1\nOLLAMA_CUDA=1\n", encoding="utf-8"
            )
            subprocess.run(
                [sys.executable, str(litellm / "build-config.py")],
                check=True,
                capture_output=True,
                text=True,
            )
            generated = (litellm / "config.yaml").read_text(encoding="utf-8")
            models = BUILD_CONFIG["extract_model_names"](generated)
            self.assertIn("local-ollama-cpu-dolphin-phi", models)
            self.assertIn("local-ollama-cuda-qwen3-abliterated-16b", models)
            self.assertNotIn("local-ollama-cuda-dolphin-phi", generated)
            self.assertNotIn("ollama-cuda-f16", generated)

    def test_generated_configuration_includes_default_encoder(self):
        repository = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as directory:
            workspace = Path(directory)
            litellm = workspace / "litellm"
            shutil.copytree(repository / "litellm/config", litellm / "config")
            shutil.copyfile(
                repository / "litellm/build-config.py", litellm / "build-config.py"
            )
            (workspace / ".env").write_text("DECIDEALOT=1\n", encoding="utf-8")
            subprocess.run(
                [sys.executable, str(litellm / "build-config.py")],
                check=True,
                capture_output=True,
                text=True,
            )
            generated = (litellm / "config.yaml").read_text(encoding="utf-8")
            self.assertIn(ENCODER_MODEL, BUILD_CONFIG["extract_model_names"](generated))

    def test_encoder_follows_default_and_explicit_provider_selection(self):
        cases = [
            ({}, False),
            ({"DECIDEALOT": "1"}, True),
            ({"DECIDEALOT_CUDA": "1"}, True),
            ({"DECIDEALOT": "1", "DECIDEALOT_CLM_ENABLED": ""}, True),
            ({"DECIDEALOT": "1", "DECIDEALOT_CLM_ENABLED": "true"}, True),
            ({"DECIDEALOT": "1", "DECIDEALOT_CLM_ENABLED": "false"}, False),
            ({"DECIDEALOT_CUDA": "1", "DECIDEALOT_CLM_ENABLED": "false"}, False),
            ({"DECIDEALOT": "0", "DECIDEALOT_CLM_ENABLED": "true"}, False),
            ({"LLAMACPP_CUDA": "1", "DECIDEALOT_CLM_ENABLED": "false"}, True),
        ]
        for environment, expected in cases:
            with self.subTest(environment=environment):
                providers = BUILD_CONFIG["active_providers"](environment)
                self.assertEqual(ENCODER_PROVIDER in providers, expected)
                self.assertEqual(providers.count(ENCODER_PROVIDER), int(expected))


if __name__ == "__main__":
    unittest.main()
