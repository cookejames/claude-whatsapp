#!/usr/bin/env bash
# Local voice-note transcription for the WhatsApp plugin (faster-whisper, CPU).
# The plugin runs ~/whisper-transcribe.sh <audio file> for every incoming voice
# note (the Dockerfile links it there) and uses stdout verbatim as the
# transcript, so stdout must be the transcript only; diagnostics go to stderr.
#
#   whisper-transcribe.sh <audio file>   print the transcript
#   whisper-transcribe.sh --download     fetch the model into the cache and exit
#
# Exit codes: 1 = transcription failed, 2 = faster-whisper isn't installed.
set -euo pipefail

PY=/opt/whisper/bin/python
if [[ ! -x "$PY" ]]; then
  echo "whisper-transcribe: $PY not found (faster-whisper is installed by the Dockerfile)" >&2
  exit 2
fi
if [[ $# -ne 1 ]]; then
  echo "usage: whisper-transcribe.sh <audio file> | --download" >&2
  exit 1
fi

export WHISPER_MODEL="${WHISPER_MODEL:-large-v3-turbo}"
export WHISPER_LANGUAGE="${WHISPER_LANGUAGE:-}"
export HF_HOME="$HOME/.cache/whisper"   # mounted from local/data/whisper
export HF_HUB_DISABLE_PROGRESS_BARS=1

exec "$PY" - "$1" <<'EOF'
import os
import sys

from faster_whisper import WhisperModel

model = WhisperModel(os.environ["WHISPER_MODEL"], device="cpu", compute_type="int8")
if sys.argv[1] == "--download":
    sys.exit(0)
segments, _ = model.transcribe(
    sys.argv[1],
    language=os.environ["WHISPER_LANGUAGE"] or None,
    beam_size=5,
    vad_filter=True,
)
print(" ".join(s.text.strip() for s in segments).strip())
EOF
