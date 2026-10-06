"""Entry point for the staged incidental PR-monitor report task."""
import sys
from base_verify import STEPS, verify

if __name__ == "__main__":
    verify(STEPS.index(sys.argv[1]), report_kind="pr-monitor")
