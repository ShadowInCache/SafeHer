"""Pin the relationship between the bundled detector's classes and the app's filter.

## The defect these tests exist to prevent

`WeaponScorer` decides what counts as a weapon by **name**. It holds a reject
list -- `nonWeaponLabels` -- and drops a detection whose label is on it,
counting everything else. Unknown labels are counted on purpose: an allow list
would mean a plugin upgrade that renamed its classes silently produced "no
weapons anywhere", which is the failure mode where a safety feature keeps
running and always reports calm.

That design is only sound while the labels reaching it are real names. They
come from metadata inside the `.tflite`, and the bundled file is built by hand
with `TFLiteConverter.from_concrete_functions`, which writes none. Ultralytics'
own exporter does; it refuses to run on Windows, so this project does not use
it. With no metadata the plugin falls back to a positional string:

    // ultralytics_yolo-0.6.14 android/.../Predictor.kt
    protected fun labelName(index: Int): String {
        if (index < 0) return "class $index"
        return labels.getOrNull(index)?.takeIf { it.isNotBlank() } ?: "class $index"
    }

For the shipped 2-class model that is survivable. Both classes are weapons, so
counting `"class 0"` and `"class 1"` is the right answer arrived at by the wrong
route. (It does mean an incident records `strongestLabel: "class 0"` rather than
`"pistol"`, which is a reporting bug, not a safety one.)

For a model with distractor classes it is fatal, and silently so. A 6-class
detector trained to recognise phones, wallets, banknotes and cards -- so that a
confident "smartphone" suppresses the box instead of being mistaken for a
knife -- emits 10,960 distractor boxes across the 1,385 held-out negatives. The
reject list screens `{smartphone, monedero, billete, tarjeta}`. The plugin would
hand it `{"class 2", "class 3", "class 4", "class 5"}`. Nothing matches, every
distractor counts as a weapon hit, and the model built to cut the
false-positive rate reinstates every box it learned to suppress -- while the
reject list, its tests, and its documentation all look correct.

## The invariant

Either the bundled model carries metadata naming its classes, **or** every
class it can emit is a weapon. The second branch is what makes the current
2-class artifact legitimate rather than merely lucky; the first is what a model
with distractors must satisfy before it ships.

Stated that way the property is true today and false exactly when someone swaps
in a multi-class model without metadata -- which is the mistake worth catching,
and one that no amount of `weapon_scorer_test.dart` passing would reveal,
because those tests supply labels directly and never consult the artifact.
"""

from __future__ import annotations

import io
import json
import re
import zipfile
from pathlib import Path

import pytest

litert = pytest.importorskip(
    "ai_edge_litert.interpreter", reason="ML extras not installed"
)

ROOT = Path(__file__).resolve().parents[1]
MODEL = ROOT / "mobile/assets/models/weapon_yolov8n_fp16.tflite"
DART_SCORER = ROOT / "mobile/lib/features/devices/domain/weapon_scorer.dart"

# The classes this project treats as weapons. Everything else a detector can
# emit must be on the Dart reject list.
WEAPON_NAMES = {"pistol", "knife"}

# Read off the plugin's own reader (YOLOFileUtils.loadMetadataFromAppendedZip):
# it reads this many bytes from the end of the file, scans backwards for the
# last local-file-header signature, and opens a ZipInputStream there.
TAIL_SEARCH = 65536 + 256
PK_LOCAL_HEADER = b"PK\x03\x04"
ACCEPTED_ENTRIES = ("TFLITE_ULTRALYTICS_METADATA.json", "metadata.json")


def _plugin_labels(path: Path) -> list[str] | None:
    """The labels the Ultralytics plugin would report, or None if it finds none.

    Deliberately re-implements the plugin's algorithm instead of calling
    `zipfile.ZipFile(path)`. Python locates the central directory from the end
    of the file and so succeeds on archives the plugin cannot read -- which
    would assert that metadata exists without asserting that the only code
    which matters can reach it.
    """
    data = path.read_bytes()
    tail = data[-min(len(data), TAIL_SEARCH):]
    at = tail.rfind(PK_LOCAL_HEADER)
    if at < 0:
        return None

    start = len(data) - len(tail) + at
    try:
        with zipfile.ZipFile(io.BytesIO(data[start:])) as zf:
            name = next((n for n in ACCEPTED_ENTRIES if n in zf.namelist()), None)
            if name is None:
                return None
            meta = json.loads(zf.read(name))
    except (zipfile.BadZipFile, json.JSONDecodeError, KeyError):
        return None

    names = meta.get("names")
    if not isinstance(names, dict):
        # The plugin calls getJSONObject("names"); an array or a missing key
        # leaves its label list empty.
        return None
    keys = sorted(names, key=lambda k: int(k) if k.isdigit() else 1 << 31)
    return [str(names[k]) for k in keys]


def _class_count(path: Path) -> int:
    """Classes the model can emit, from its output shape: (1, 4 + nc, anchors)."""
    interp = litert.Interpreter(model_path=str(path))
    interp.allocate_tensors()
    shape = list(interp.get_output_details()[0]["shape"])
    assert len(shape) == 3, f"unexpected output rank: {shape}"
    return int(shape[1]) - 4


def _dart_reject_list() -> set[str]:
    text = DART_SCORER.read_text(encoding="utf-8")
    block = re.search(
        r"nonWeaponLabels\s*=\s*<String>\{(.*?)\}", text, re.S
    )
    assert block, "could not find nonWeaponLabels in weapon_scorer.dart"
    return {m.lower() for m in re.findall(r"'([^']+)'", block.group(1))}


@pytest.mark.skipif(not MODEL.is_file(), reason="model asset not present")
def test_either_the_model_names_its_classes_or_they_are_all_weapons() -> None:
    """The invariant in the module docstring, which is the load-bearing one."""
    labels = _plugin_labels(MODEL)
    classes = _class_count(MODEL)

    if labels is None:
        assert classes == len(WEAPON_NAMES), (
            f"{MODEL.name} exposes no class names to the Ultralytics plugin, so "
            f"every detection arrives as 'class N' and WeaponScorer's reject "
            f"list cannot match any of them. That is only safe while every "
            f"class is a weapon, but this model emits {classes}. Attach "
            f"Ultralytics metadata (a ZIP appended to the file holding "
            f"TFLITE_ULTRALYTICS_METADATA.json with a 'names' object) before "
            f"shipping it, or the distractor classes will be counted as weapons."
        )
        return

    assert len(labels) == classes, (
        f"metadata names {len(labels)} classes ({labels}) but the model emits "
        f"{classes}. The metadata does not describe this model, so labels would "
        f"be assigned to the wrong classes."
    )


@pytest.mark.skipif(not MODEL.is_file(), reason="model asset not present")
def test_every_named_non_weapon_is_on_the_dart_reject_list() -> None:
    """A distractor the model can name but Dart does not know is counted as a weapon."""
    labels = _plugin_labels(MODEL)
    if labels is None:
        pytest.skip("no metadata; covered by the invariant test above")

    rejected = _dart_reject_list()
    unhandled = [n for n in labels
                 if n.lower() not in WEAPON_NAMES and n.lower() not in rejected]
    assert not unhandled, (
        f"the model can report {unhandled}, which are neither weapons nor on "
        f"WeaponScorer.nonWeaponLabels. The reject list fails open by design, so "
        f"these would each be scored as a weapon. Add them to nonWeaponLabels."
    )


@pytest.mark.skipif(not MODEL.is_file(), reason="model asset not present")
def test_reject_list_is_lowercase_and_trimmed() -> None:
    """`isWeaponClass` compares against `label.trim().toLowerCase()`.

    An entry with a capital or a stray space could never match, so it would sit
    in the list looking like protection while matching nothing.
    """
    for entry in _dart_reject_list():
        assert entry == entry.strip().lower(), (
            f"'{entry}' cannot ever match, because isWeaponClass lowercases and "
            f"trims the label before the lookup"
        )
