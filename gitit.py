#!/usr/bin/env /home/developer/scripts/.venv/bin/python3

import subprocess, sys
from pathlib import Path
from textual.app import App
from textual.containers import Horizontal
from textual.widgets import Button, Header, Footer, Static, Input

def find_git_root(start: Path):
    for p in [start] + list(start.parents):
        if (p / ".git").exists():
            return p
    return None

class GitTuiApp(App):
    CSS = """
    Screen { layout: vertical; padding:1; }
    #info { height:2; }
    #buttonbar { layout: horizontal; align: center middle; padding:1; }
    Button { margin:1; width:25%; min-width:8; height:3; }
    """

    def compose(self):
        yield Header(show_clock=True)
        self.info = Static("…initialisiere…", id="info")
        yield self.info
        yield Horizontal(
            Button("Status", id="status"),
            Button("Pull", id="pull"),
            Button("Push", id="push"),
            Button("Log", id="log"),
            Button("Copy", id="copy"),
            Button("Paste", id="paste"),
            Button("All", id="selectall"),
            Button("Commit", id="commit"),
            id="buttonbar"
        )
        self.commit_msg = Input(placeholder="Commit message…", id="commitmsg")
        yield self.commit_msg
        yield Footer()

    def on_mount(self):
        root = find_git_root(Path.cwd())
        if root:
            self.git_root = root
            self.info.update(f"Git-Root: {root}")
        else:
            self.git_root = None
            self.info.update("Kein Git-Repo hier oder oben gefunden.")

    async def on_button_pressed(self, event):
        bid = event.button.id
        root = self.git_root
        if not root:
            return
        if bid == "status":
            subprocess.run(["git", "-C", str(root), "status"])
        elif bid == "pull":
            subprocess.run(["git", "-C", str(root), "pull"])
        elif bid == "push":
            subprocess.run(["git", "-C", str(root), "add", "."])
            cm = self.commit_msg.value or "Auto commit"
            subprocess.run(["git", "-C", str(root), "commit", "-m", cm])
            subprocess.run(["git", "-C", str(root), "push"])
        elif bid == "log":
            subprocess.run(["git", "-C", str(root), "log", "--oneline", "--graph", "--all"])
        elif bid == "selectall":
            self.commit_msg.selection_anchor = 0
            self.commit_msg.cursor_position = len(self.commit_msg.value)
        elif bid == "copy":
            self.commit_msg.copy()
        elif bid == "paste":
            self.commit_msg.paste()
        elif bid == "commit":
            cm = self.commit_msg.value or "Auto commit"
            subprocess.run(["git", "-C", str(root), "commit", "-m", cm])

    async def on_key(self, event):
        if event.key == "ctrl+c":
            self.exit()

if __name__ == "__main__":
    GitTuiApp().run()
