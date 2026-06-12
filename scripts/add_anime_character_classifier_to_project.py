#!/usr/bin/env python3
from pathlib import Path


PROJECT_FILE = Path("WallFlow.xcodeproj/project.pbxproj")
BUILD_FILE_ID = "A10000000000000000000008"
FILE_REF_ID = "A10000000000000000000019"


def replace_once(text, old, new):
    if old not in text:
        raise RuntimeError(f"Could not find expected project section: {old[:80]!r}")
    return text.replace(old, new, 1)


def main():
    model_path = Path("WallFlow/AnimeCharacterClassifier.mlmodelc")
    if not model_path.exists():
        raise SystemExit("WallFlow/AnimeCharacterClassifier.mlmodelc does not exist.")

    text = PROJECT_FILE.read_text()
    if FILE_REF_ID in text or "AnimeCharacterClassifier.mlmodelc" in text:
        return

    text = replace_once(
        text,
        "\t\tA10000000000000000000007 /* AnimeFaceDetector.mlmodelc in Resources */ = {isa = PBXBuildFile; fileRef = A10000000000000000000018 /* AnimeFaceDetector.mlmodelc */; };\n",
        "\t\tA10000000000000000000007 /* AnimeFaceDetector.mlmodelc in Resources */ = {isa = PBXBuildFile; fileRef = A10000000000000000000018 /* AnimeFaceDetector.mlmodelc */; };\n"
        f"\t\t{BUILD_FILE_ID} /* AnimeCharacterClassifier.mlmodelc in Resources */ = {{isa = PBXBuildFile; fileRef = {FILE_REF_ID} /* AnimeCharacterClassifier.mlmodelc */; }};\n",
    )
    text = replace_once(
        text,
        "\t\tA10000000000000000000018 /* AnimeFaceDetector.mlmodelc */ = {isa = PBXFileReference; lastKnownFileType = wrapper.mlmodelc; path = AnimeFaceDetector.mlmodelc; sourceTree = \"<group>\"; };\n",
        "\t\tA10000000000000000000018 /* AnimeFaceDetector.mlmodelc */ = {isa = PBXFileReference; lastKnownFileType = wrapper.mlmodelc; path = AnimeFaceDetector.mlmodelc; sourceTree = \"<group>\"; };\n"
        f"\t\t{FILE_REF_ID} /* AnimeCharacterClassifier.mlmodelc */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.mlmodelc; path = AnimeCharacterClassifier.mlmodelc; sourceTree = \"<group>\"; }};\n",
    )
    text = replace_once(
        text,
        "\t\t\t\tA10000000000000000000018 /* AnimeFaceDetector.mlmodelc */,\n",
        "\t\t\t\tA10000000000000000000018 /* AnimeFaceDetector.mlmodelc */,\n"
        f"\t\t\t\t{FILE_REF_ID} /* AnimeCharacterClassifier.mlmodelc */,\n",
    )
    text = replace_once(
        text,
        "\t\t\t\tA10000000000000000000007 /* AnimeFaceDetector.mlmodelc in Resources */,\n",
        "\t\t\t\tA10000000000000000000007 /* AnimeFaceDetector.mlmodelc in Resources */,\n"
        f"\t\t\t\t{BUILD_FILE_ID} /* AnimeCharacterClassifier.mlmodelc in Resources */,\n",
    )
    PROJECT_FILE.write_text(text)


if __name__ == "__main__":
    main()
