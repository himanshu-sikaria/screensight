#!/usr/bin/env python3
"""Screen capture using CoreGraphics API.

On macOS, /usr/sbin/screencapture inherits Screen Recording permission from
its parent GUI app (Terminal, iTerm). Under launchd, there is no parent GUI
app, so screencapture fails with "could not create image from display."

This script calls CGWindowListCreateImage directly. TCC checks the calling
process, so the launchd agent (or its app bundle wrapper) can be granted
Screen Recording permission and captures will succeed.

Requires: pip3 install pyobjc-framework-Quartz
"""

import sys

import Quartz
from Foundation import NSURL


def capture_screen(output_path):
    """Capture the main display and save as PNG."""
    image = Quartz.CGWindowListCreateImage(
        Quartz.CGRectInfinite,
        Quartz.kCGWindowListOptionOnScreenOnly,
        Quartz.kCGNullWindowID,
        Quartz.kCGWindowImageDefault,
    )
    if image is None:
        print("CGWindowListCreateImage returned nil", file=sys.stderr)
        return False

    url = NSURL.fileURLWithPath_(output_path)
    dest = Quartz.CGImageDestinationCreateWithURL(url, "public.png", 1, None)
    if dest is None:
        print("CGImageDestinationCreateWithURL failed", file=sys.stderr)
        return False

    Quartz.CGImageDestinationAddImage(dest, image, None)
    Quartz.CGImageDestinationFinalize(dest)
    return True


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <output.png>", file=sys.stderr)
        sys.exit(1)
    sys.exit(0 if capture_screen(sys.argv[1]) else 1)
