# Loafly order pipeline

Python standard library only. Nothing to pip install.

## Setup (Windows)

Open a terminal in this folder:

```text
python -m venv .venv
.venv\Scripts\activate
```

Copy `env.example` to `.env` if you do not already have one. The key name is `LOAFLY_API_KEY`.

## Run

```text
python run_pipeline.py
```

Logs go to the console and to `logs/loafly.log`.

## Layout

```text
run_pipeline.py     extract → transform → load
loafly/             package (config, models, extract, transform, load)
gateway.py          provided API client — do not edit
data/raw_orders.csv input
env.example         template for .env
requirements.txt    stdlib only
```

Do not commit `.env`.
