# 10. Coordinate people and automation during an incident

Read the corresponding chapter in [the handbook](../../README.md) for setup, architecture, failure exercises, acceptance criteria, costs, and cleanup. Run commands from the handbook root after completing workstation setup.

```text
python -m uvicorn scripts.incident_api:app --host 127.0.0.1 --port 18086
```

Publish measured evidence from your own run. The fixture inputs demonstrate decision behavior; they are not production incident results.
