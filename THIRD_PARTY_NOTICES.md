# Third-Party Notices

WallFlow includes and uses third-party model assets.

## deepghs/anime_face_detection

- Source: https://huggingface.co/deepghs/anime_face_detection
- Included model: `face_detect_v1.4_n`, converted to Core ML format
- Listed license: MIT

The model is bundled as `WallFlow/AnimeFaceDetector.mlmodelc` and is used for anime-style face detection.

## SmilingWolf/wd-vit-tagger-v3

- Source: https://huggingface.co/SmilingWolf/wd-vit-tagger-v3
- Included model: adapted from `wd-vit-tagger-v3`, converted to Core ML format
- Listed license: Apache-2.0

The adapted model is bundled as `WallFlow/AnimeCharacterClassifier.mlmodelc` and is used to prioritize human face candidates while avoiding non-human face candidates when multiple faces are detected.
