#!/usr/bin/env python3
import argparse
import csv
from pathlib import Path

import coremltools as ct
import timm
import torch


HUMAN_LABELS = {
    "1girl",
    "1boy",
    "2girls",
    "2boys",
    "girl",
    "boy",
    "female",
    "male",
    "woman",
    "man",
    "person",
    "solo",
    "solo_focus",
    "multiple_girls",
    "multiple_boys",
}
NON_HUMAN_LABELS = {
    "animal",
    "animal_focus",
    "bird",
    "cat",
    "creature",
    "dog",
    "horse",
    "mascot",
    "monster",
    "no_humans",
    "pokemon_(creature)",
    "rabbit",
    "stuffed_animal",
}


class CharacterFocusClassifier(torch.nn.Module):
    def __init__(self, base_model, human_indices, non_human_indices):
        super().__init__()
        self.base_model = base_model
        self.register_buffer("human_indices", torch.tensor(human_indices, dtype=torch.long))
        self.register_buffer("non_human_indices", torch.tensor(non_human_indices, dtype=torch.long))

    def forward(self, image):
        tag_scores = torch.sigmoid(self.base_model(image))
        human_score = tag_scores.index_select(1, self.human_indices).max(dim=1).values
        non_human_score = tag_scores.index_select(1, self.non_human_indices).max(dim=1).values
        return torch.stack((non_human_score, human_score), dim=1)


def normalize_tag(tag):
    return tag.strip().lower().replace(" ", "_")


def load_tag_names(path):
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames or []
        name_field = "name" if "name" in fieldnames else fieldnames[-1]
        return [normalize_tag(row[name_field]) for row in reader]


def indices_for(tags, targets):
    return [index for index, tag in enumerate(tags) if tag in targets]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", default="SmilingWolf/wd-vit-tagger-v3")
    parser.add_argument("--tags", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    tags = load_tag_names(args.tags)
    human_indices = indices_for(tags, HUMAN_LABELS)
    non_human_indices = indices_for(tags, NON_HUMAN_LABELS)
    if not human_indices:
        raise RuntimeError(f"Human labels not found in {args.tags}")
    if not non_human_indices:
        raise RuntimeError(f"Non-human labels not found in {args.tags}")

    base_model = timm.create_model(f"hf_hub:{args.repo}", pretrained=True)
    base_model.eval()
    wrapped_model = CharacterFocusClassifier(
        base_model,
        human_indices,
        non_human_indices,
    ).eval()

    example_input = torch.rand(1, 3, 448, 448)
    traced_model = torch.jit.trace(wrapped_model, example_input)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    mlmodel = ct.convert(
        traced_model,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.macOS14,
        inputs=[
            ct.ImageType(
                name="image",
                shape=example_input.shape,
                scale=1 / 127.5,
                bias=[-1.0, -1.0, -1.0],
                color_layout=ct.colorlayout.RGB,
            )
        ],
        classifier_config=ct.ClassifierConfig(["non_human", "human"]),
    )
    mlmodel.short_description = "Human/non-human classifier derived from SmilingWolf/wd-vit-tagger-v3."
    mlmodel.author = "SmilingWolf, adapted for WallFlow"
    mlmodel.license = "Apache-2.0"
    mlmodel.save(str(args.output))


if __name__ == "__main__":
    main()
