#!/usr/bin/env python3
"""Render real cc-progress output to assets/demo.png with PIL.

Runs the CLI against a throwaway state directory, so the picture is what the status
line would show, not a mock-up. Usage: python3 assets/make-demo.py [font.ttf]
"""
import os, re, subprocess, sys, tempfile, time, json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
CLI = ROOT / "bin" / "cc-progress"
FONT = sys.argv[1] if len(sys.argv) > 1 else "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
BOLD = FONT.replace("DejaVuSansMono.ttf", "DejaVuSansMono-Bold.ttf")

# a dark and a light terminal theme, both only through the ANSI roles the CLI emits
THEMES = {
    "dark":  {"bg": "#0f172a", "fg": "#e2e8f0", "31": "#f87171", "32": "#3ddc97", "33": "#fbbf24", "36": "#67e8f9", "90": "#64748b"},
    "light": {"bg": "#fbfaf6", "fg": "#1e293b", "31": "#b91c1c", "32": "#15803d", "33": "#b45309", "36": "#0e7490", "90": "#94a3b8"},
}

def bars(state):
    env = dict(os.environ, CC_PROGRESS_DIR=state, CC_PROGRESS_SESSION="demo", COLUMNS="120")
    run = lambda *a: subprocess.run([str(CLI), *a], env=env, check=True, capture_output=True)
    f = lambda i: Path(state, "demo", f"{i}.json")
    age = lambda i, jq: subprocess.run(["jq", "-c", jq, f(i)], check=True, capture_output=True).stdout
    def write(i, data): f(i).write_bytes(data)
    now = time.time()
    run("start", "--id", "convert", "--label", "Converting", "--unit", "files", "--total", "40", "--note", "report-q3.pdf")
    write("convert", age("convert", f'.started_at = {now-78} | .samples = [[{now-78},0,0],[{now-2},13,13]] | .done = 13 | .wdone = 13 | .updated_at = {now-2}'))
    w = Path(state, "w.txt"); w.write_text("4 test_api.py\n6 test_cli.py\n72 test_sweep.py\n3 test_util.py\n")
    run("start", "--id", "tests", "--label", "Tests", "--unit", "files", "--weights", str(w))
    write("tests", age("tests", f'.started_at = {now-400} | .samples = [[{now-400},0,0],[{now-360},1,4],[{now-290},2,10]] | .done = 2 | .wdone = 10 | .note = "test_sweep.py" | .updated_at = {now-5}'))
    run("start", "--id", "scan", "--label", "Scanning", "--unit", "rows")
    run("set", "1200", "--id", "scan")
    write("scan", age("scan", f'.started_at = {now-40}'))
    run("start", "--id", "agents", "--agents", "--label", "Reviewers")
    for a, t in (("a1", "Explore"), ("a2", "general-purpose"), ("a3", "Explore")):
        subprocess.run([str(CLI), "hook"], env=dict(env, CLAUDE_CODE_SESSION_ID="demo"), input=json.dumps({"hook_event_name": "SubagentStart", "agent_id": a, "agent_type": t}).encode(), check=True)
    subprocess.run([str(CLI), "hook"], env=dict(env, CLAUDE_CODE_SESSION_ID="demo"), input=json.dumps({"hook_event_name": "SubagentStop", "agent_id": "a1", "agent_type": "Explore"}).encode(), check=True)
    write("agents", age("agents", f'.started_at = {now-130} | .samples[0][0] = {now-130}'))
    run("start", "--id", "done", "--label", "Backfill", "--unit", "rows", "--total", "240")
    run("set", "240", "--id", "done")
    write("done", age("done", f'.started_at = {now-242} | .samples = [[{now-242},0,0],[{now-1},240,240]] | .updated_at = {now-1}'))
    run("start", "--id", "deploy", "--label", "Deploy", "--unit", "steps", "--total", "6")
    run("set", "2", "--id", "deploy"); run("fail", "--id", "deploy", "--note", "step 3: migrate")
    write("deploy", age("deploy", f'.started_at = {now-12} | .finished_at = {now}'))
    out = subprocess.run([str(CLI), "render"], env=env, input=b'{"session_id":"demo"}', check=True, capture_output=True).stdout.decode()
    return out.rstrip("\n").split("\n")

SGR = re.compile(r"\x1b\[([0-9;]*)m")
def spans(line):
    """(text, bold, colour-key) runs from one ANSI line."""
    bold, colour, pos, runs = False, None, 0, []
    for m in SGR.finditer(line):
        if m.start() > pos: runs.append((line[pos:m.start()], bold, colour))
        for code in (m.group(1) or "0").split(";"):
            if code in ("", "0"): bold, colour = False, None
            elif code == "1": bold = True
            elif code in ("31", "32", "33", "36", "90"): colour = code
        pos = m.end()
    if pos < len(line): runs.append((line[pos:], bold, colour))
    return runs

def paint(lines, theme, path, size=22):
    font, bfont = ImageFont.truetype(FONT, size), ImageFont.truetype(BOLD, size)
    cw = font.getlength("M"); lh = int(size * 1.55); pad = 28
    width = int(max(sum(font.getlength(t) for t, _, _ in spans(l)) for l in lines)) + 2 * pad
    img = Image.new("RGB", (width, lh * len(lines) + 2 * pad), theme["bg"]); d = ImageDraw.Draw(img)
    for i, line in enumerate(lines):
        x = pad
        for text, bold, colour in spans(line):
            d.text((x, pad + i * lh), text, font=bfont if bold else font, fill=theme.get(colour, theme["fg"]))
            x += (bfont if bold else font).getlength(text)
    img.save(path)
    return img.size

if __name__ == "__main__":
    with tempfile.TemporaryDirectory() as state:
        lines = bars(state)
    print("\n".join(SGR.sub("", l) for l in lines))
    for name, theme in THEMES.items():
        print(name, paint(lines, theme, ROOT / "assets" / f"demo-{name}.png"))
