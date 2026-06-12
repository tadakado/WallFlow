#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

PYTHON_BIN="${PYTHON_BIN:-python3}"
VENV_DIR=".model-cache/wd-vit-tagger-v3-venv"
MODEL_DIR=".model-cache/wd-vit-tagger-v3"
MODEL_PACKAGE="WallFlow/AnimeCharacterClassifier.mlpackage"
MODEL_COMPILED_DIR="WallFlow/AnimeCharacterClassifier.mlmodelc"

"$PYTHON_BIN" - <<'PY'
import sys
if sys.version_info >= (3, 13):
    raise SystemExit("Python 3.12 or older is recommended for coremltools. Set PYTHON_BIN=/path/to/python3.12 and run again.")
PY

"$PYTHON_BIN" -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"

python -m pip install --upgrade pip
python -m pip install "coremltools>=8,<9" "torch>=2.2" "timm>=1.0" "huggingface_hub>=0.23" "numpy<2" pandas

mkdir -p "$MODEL_DIR"
python - <<'PY'
from huggingface_hub import hf_hub_download

repo = "SmilingWolf/wd-vit-tagger-v3"
for filename in ["selected_tags.csv", "config.json", "model.safetensors"]:
    hf_hub_download(repo_id=repo, filename=filename, local_dir=".model-cache/wd-vit-tagger-v3")
PY

python scripts/convert_wd_vit_tagger_v3_to_coreml.py \
  --tags "$MODEL_DIR/selected_tags.csv" \
  --output "$MODEL_PACKAGE"

rm -rf "$MODEL_COMPILED_DIR"
xcrun coremlcompiler compile "$MODEL_PACKAGE" WallFlow
python scripts/add_anime_character_classifier_to_project.py

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
xcodebuild -project WallFlow.xcodeproj -scheme WallFlow -configuration Debug -derivedDataPath .DerivedData build

echo "AnimeCharacterClassifier is ready."
