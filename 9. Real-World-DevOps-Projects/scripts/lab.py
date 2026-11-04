"""Explicit local Docker Compose wrapper. No cloud profiles or Kubernetes contexts are used."""
from pathlib import Path
import subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
subprocess.run(['docker','compose','--env-file',str(ROOT/'.private/lab.env'),'-f',str(ROOT/'compose.yaml'),*sys.argv[1:]],cwd=ROOT,check=True)
