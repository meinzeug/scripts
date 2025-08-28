#!/usr/bin/env /home/developer/scripts/.venv/bin/python3
import subprocess
from pathlib import Path
from textual.app import App
from textual.containers import Horizontal
from textual.widgets import Button, Header, Footer, Static, Input

def find_git_root():
    p = Path.cwd()
    for d in [p] + list(p.parents):
        if (d / '.git').exists():
            return d
    return None

class GititTUI(App):
    CSS = """
Screen { layout: vertical; padding:1; }
#info { height:2; }
#buttons { layout: horizontal; align: center middle; padding:1; }
Button { margin:1; width:25%; min-width:8; height:3; }
"""

    def compose(self):
        yield Header(show_clock=True)
        self.info = Static("", id="info")
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
            id="buttons"
        )
        self.msg = Input(placeholder="Commit message…", id="msg")
        yield self.msg
        yield Footer()

    def on_mount(self):
        root = find_git_root()
        if root:
            self.root = root
            self.info.update(f"📁 Git Root: {root}")
        else:
            self.root = None
            self.info.update("❌ Kein Git-Repo gefunden")

    async def on_button_pressed(self, event):
        if not self.root: return
        btn = event.button.id
        if btn == "status":
            subprocess.run(["git", "-C", str(self.root), "status"])
        elif btn == "pull":
            subprocess.run(["git", "-C", str(self.root), "pull"])
        elif btn == "push":
            subprocess.run(["git", "-C", str(self.root), "add", "."])
            msg = self.msg.value or "Auto"
            subprocess.run(["git", "-C", str(self.root), "commit", "-m", msg])
            subprocess.run(["git", "-C", str(self.root), "push"])
        elif btn == "log":
            subprocess.run(["git", "-C", str(self.root), "log", "--oneline", "--graph", "--all"])
        elif btn == "selectall":
            self.msg.selection_anchor = 0
            self.msg.cursor_position = len(self.msg.value)
        elif btn == "copy":
            self.msg.copy()
        elif btn == "paste":
            self.msg.paste()
        elif btn == "commit":
            msg = self.msg.value or "Auto"
            subprocess.run(["git", "-C", str(self.root), "commit", "-m", msg])

    async def on_key(self, event):
        if event.key == "ctrl+c":
            self.exit()

if __name__ == "__main__":
    GititTUI().run()
