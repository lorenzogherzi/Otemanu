# Otemanu

> [!WARNING]
> **Otemanu is currently in active testing.** Features, behavior, compatibility,
> and the interface may change without notice. This repository is published as
> source code for testing and development; no stable prebuilt application is
> currently provided.

Otemanu is a native macOS monitor for local Jupyter Notebook and JupyterLab
sessions. It turns the area around the MacBook notch, or a compact pill on
other Macs, into a live view of notebook execution.

The island follows the kernel while a cell is working and reports progress and
resource usage for as long as it is running. When the cell finishes, Otemanu
shows the completed cell snapshot until the island closes or a new cell starts,
then returns to the connected/idle state. Monitoring happens locally through
Jupyter runtime files, its REST API, and the kernel WebSocket channels.

## What the island shows

While a cell is running, Otemanu can display:

- the notebook filename;
- the Jupyter execution counter, such as `In [12]`;
- a short description extracted from the cell source;
- the kernel state and elapsed execution time;
- determinate or indeterminate progress;
- `tqdm` description, iteration count, percentage, ETA, and iteration rate;
- RAM, CPU, and GPU activity associated with the kernel process tree.

When no cell is running, the island returns to the Jupyter connection state and
reports that the kernel is idle.

## Execution lifecycle

Otemanu discovers active Jupyter sessions in the background and reacts as soon
as an `execute_input` message is received from a kernel. By default it opens the
complete island; **Settings → General → Open when execution starts** can instead
start directly with the compact `busy` indicator and elapsed time.

During execution:

1. The island remains in the selected full or compact presentation while the
   cell is busy.
2. Its timer is updated every second.
3. Progress messages and kernel resource metrics update in real time.
4. The island cannot close accidentally while execution is active.

If a long-running cell no longer needs the full interface, click the open
island once. It shrinks to menu-bar height and remains wider than its normal
closed state, showing only the orange `busy` indicator and elapsed time. Click
the compact indicator again to restore the complete view.

When the cell finishes, Otemanu shows `Cell complete` together with the name and
details of that cell for as long as the completion notification remains active.
The island opens for this notification even when execution started in compact
mode. The snapshot is removed when the island closes or a new cell starts; the
island then reports `Jupyter session active` and `kernel idle`. No completed
execution history is retained after the notification disappears.

## Close behavior

Open **Settings → General** to configure what happens after the last running
cell finishes.

- **Close automatically after execution** closes the island after the selected
  delay. The delay can be set from 1 to 30 seconds.
- When automatic closing is disabled, the island remains open until it is
  clicked.

Automatic closing is disabled by default. The initial stored delay is two
seconds.

When the kernel is idle, hovering over the closed island opens it after a
short delay. Moving the pointer away closes the idle preview. This hover
behavior does not interrupt an active execution.

## Progress monitoring

Otemanu listens to Jupyter IOPub messages and supports the common progress
formats produced by:

- terminal `tqdm` output;
- `tqdm.notebook`;
- Jupyter progress widgets based on `FloatProgress` and their associated HTML
  labels.

A standard notebook loop works without importing any Otemanu-specific code:

```python
from tqdm.notebook import tqdm
import time

for item in tqdm(range(100), desc="Analysis"):
    time.sleep(0.1)
```

When Jupyter publishes all widget fields, the island extracts the description,
current and total iterations, percentage, elapsed time, ETA, and processing
rate. The exact amount of information available depends on the output format
emitted by the installed `tqdm`, `ipywidgets`, Jupyter Notebook, or JupyterLab
version.

Cells that do not publish measurable progress still receive an indeterminate
busy bar and execution timer.

## Example notebook

[`jupyter_test_otemanu.ipynb`](jupyter_test_otemanu.ipynb) is an output-free
Python notebook for testing Otemanu with one cell at a time. It covers:

- kernel discovery, connection details, and execution timing;
- streaming terminal output;
- CPU and RAM activity;
- regular and irregular `tqdm` progress;
- `tqdm.notebook` widgets and descriptive cell headers;
- structured progress messages;
- intentional error reporting.

The notebook is published with empty outputs and execution counters. Some cells
intentionally perform sustained CPU work, allocate approximately 800 MB of RAM,
or raise a test exception. Review each cell and run it individually.

## Cell descriptions

The subtitle is taken from the first meaningful line of the executed cell.
Empty lines and divider comments containing only `=` characters are skipped.
This allows section headers such as the following:

```python
# ============================================================
# LOAD DATABASE + SETUP OUTPUT FOLDERS
# ============================================================

database = load_database()
prepare_output_folders()
```

The island displays:

```text
# LOAD DATABASE + SETUP OUTPUT FOLDERS
```

A divider must begin with `#` and contain at least three `=` characters after
whitespace is removed. For the clearest subtitle, place a short descriptive
comment immediately after the opening divider. Long descriptions are safely
truncated to fit the island.

This formatting is optional. Ordinary cells use their first non-empty line,
and cells without a meaningful source line display `Cell running`.

## Kernel resource monitoring

Otemanu identifies the operating-system process associated with each Jupyter
kernel and includes its live child processes. This is important for workloads
that use `multiprocessing`, `joblib`, native libraries, or other subprocesses.

The resource indicator reports:

- **RAM:** the combined physical memory footprint of the kernel process tree;
- **CPU:** CPU time consumed between consecutive samples;
- **GPU:** GPU activity when macOS exposes process-level GPU timing data.

Metrics are sampled four times per second while a kernel is busy. The final
sample remains visible with `Cell complete` and is released with the completed
cell snapshot. Values are only shown when activity is available and greater
than zero. GPU data may be absent for workloads or systems where macOS does not
expose it to the app.

## Jupyter discovery and connection

Otemanu checks the following runtime locations:

- the directory defined by `JUPYTER_RUNTIME_DIR`;
- `~/Library/Jupyter/runtime`;
- `~/.local/share/jupyter/runtime`;
- `~/.jupyter/runtime`.

It reads `jpserver-*.json` and `nbserver-*.json` files, ignores stale server
processes, and requests active sessions from `/api/sessions`. A separate
WebSocket connection is then opened for each active kernel.

Token-authenticated local servers are supported automatically when the token
is present in the runtime file. A password-only server without an available
token is reported as requiring authentication.

## Controls

- **Click while idle:** close an open island or open a closed one.
- **Click while busy:** switch between full and minimized busy views.
- **Right-click:** open Settings or quit Otemanu.
- **Settings → About:** view the application name and version.

Otemanu runs as an accessory application and does not add a menu-bar icon.

## Privacy

All monitoring is performed on the Mac. Otemanu reads local Jupyter runtime
metadata, calls the local Jupyter server, receives kernel channel messages,
and inspects local kernel processes. It does not upload notebook source,
outputs, tokens, or resource metrics.

## Requirements

- macOS 14.6 or later;
- a local Jupyter Notebook or JupyterLab server;
- at least one notebook session with an active kernel.

Otemanu has no third-party runtime dependencies.

## Troubleshooting

If no Jupyter server is detected, confirm that Jupyter is running locally and
that its runtime JSON file exists in one of the supported directories. If the
server is found but no notebook appears, open a notebook and start its kernel.

If progress details are missing but the cell is detected correctly, verify
that the notebook is rendering `tqdm` output and that `ipywidgets` is enabled
for `tqdm.notebook`. Otemanu can only display fields published by the kernel.

Resource values may take an initial sample to appear. RAM, CPU, and GPU rows
are intentionally hidden when their reported value is zero or unavailable.

## License

Otemanu is distributed under the GNU General Public License version 3 or, at
your option, any later version. See `LICENSE` for the complete terms and
`NOTICE` for attribution.
