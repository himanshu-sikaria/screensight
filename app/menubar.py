#!/usr/bin/env python3
"""Screen Capture — Menu Bar App

Lightweight menu bar indicator showing capture status with pause/resume control.
Requires: pip3 install rumps
"""

import os
import signal
import subprocess
from datetime import datetime
from pathlib import Path

import rumps

PID_FILE = "/tmp/screen-capture.pid"
PAUSE_FILE = "/tmp/screen-capture.paused"
CONFIG_FILE = os.path.expanduser("~/.screen-capture/config.yaml")


def get_output_dir():
    """Read output directory from config, fall back to default."""
    try:
        with open(CONFIG_FILE) as f:
            for line in f:
                stripped = line.strip()
                if stripped.startswith("directory:"):
                    val = stripped.split(":", 1)[1].strip().strip('"').strip("'")
                    return os.path.expanduser(val)
    except FileNotFoundError:
        pass
    return os.path.expanduser("~/screen-capture")


def is_daemon_running():
    """Check if capture daemon is running via PID file."""
    try:
        with open(PID_FILE) as f:
            pid = int(f.read().strip())
        os.kill(pid, 0)
        return True
    except (FileNotFoundError, ValueError, ProcessLookupError, PermissionError):
        return False


def is_paused():
    return os.path.exists(PAUSE_FILE)


def today_screenshot_count():
    today = datetime.now().strftime("%Y-%m-%d")
    raw_dir = Path(get_output_dir()) / "raw" / today
    if not raw_dir.exists():
        return 0
    return len(list(raw_dir.glob("*.jpg")))


def last_analysis_date():
    output_dir = Path(get_output_dir())
    digests = sorted(output_dir.glob("*/digest.md"), reverse=True)
    if digests:
        return digests[0].parent.name
    return "never"


class ScreenCaptureApp(rumps.App):
    def __init__(self):
        super().__init__("", quit_button=None)
        self.menu = [
            rumps.MenuItem("status", callback=None),
            rumps.MenuItem("count", callback=None),
            rumps.MenuItem("last_analysis", callback=None),
            None,  # separator
            rumps.MenuItem("Pause Capture", callback=self.toggle_pause),
            None,
            rumps.MenuItem("Open Output Folder", callback=self.open_output),
            rumps.MenuItem("Edit Config", callback=self.open_config),
            rumps.MenuItem("Run Analysis Now", callback=self.run_analysis),
            None,
            rumps.MenuItem("Quit", callback=self.quit_app),
        ]
        self.update_status(None)
        # Update every 10 seconds
        self.timer = rumps.Timer(self.update_status, 10)
        self.timer.start()

    def update_status(self, _):
        running = is_daemon_running()
        paused = is_paused()
        count = today_screenshot_count()
        last = last_analysis_date()

        # Icon
        if not running:
            self.title = "\u25cf"  # filled circle, will appear in menu bar
            self.icon = None
        elif paused:
            self.title = "\u275a\u275a"  # pause bars
        else:
            self.title = "\u25cf"  # filled circle

        # Status text
        if not running:
            self.menu["status"].title = "Capture: Not Running"
        elif paused:
            self.menu["status"].title = "Capture: Paused"
        else:
            self.menu["status"].title = "Capture: Active"

        self.menu["count"].title = f"Today: {count} screenshots"
        self.menu["last_analysis"].title = f"Last analysis: {last}"

        # Toggle button text
        pause_item = self.menu["Pause Capture"]
        if paused:
            pause_item.title = "Resume Capture"
        else:
            pause_item.title = "Pause Capture"

    def toggle_pause(self, sender):
        if is_paused():
            try:
                os.remove(PAUSE_FILE)
            except FileNotFoundError:
                pass
            rumps.notification("Screen Capture", "", "Capture resumed")
        else:
            Path(PAUSE_FILE).touch()
            rumps.notification("Screen Capture", "", "Capture paused")
        self.update_status(None)

    def open_output(self, _):
        output_dir = get_output_dir()
        subprocess.run(["open", output_dir])

    def open_config(self, _):
        subprocess.run(["open", CONFIG_FILE])

    def run_analysis(self, _):
        # Find analyze.sh relative to this script or in the installed location
        script_dir = Path(__file__).parent.parent / "scripts"
        analyze = script_dir / "analyze.sh"
        if analyze.exists():
            subprocess.Popen(["/bin/bash", str(analyze)])
            rumps.notification("Screen Capture", "", "Analysis started — check logs for progress")
        else:
            rumps.notification("Screen Capture", "", "analyze.sh not found")

    def quit_app(self, _):
        rumps.quit_application()


if __name__ == "__main__":
    ScreenCaptureApp().run()
