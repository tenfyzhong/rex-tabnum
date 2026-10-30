"""Interactive Rex acceptance fixture: each input line becomes the OSC title."""
import sys


def set_title(title):
    sys.stdout.write("\033]2;" + title.strip() + "\007")
    sys.stdout.flush()


set_title("dynamic-alpha")
print("Enter a line to change this terminal's title.", flush=True)
for line in sys.stdin:
    set_title(line)
