#!/usr/bin/env python3
"""Generate a random LOANREC test deck covering the whole input domain.

  gen_stress_deck.py SEED COUNT OUT-FILE

Principals are log-uniform from 0.01 to 999,999,999.99, rates mix 0%,
tiny, typical and up-to-36% values, terms favour the classic product
terms plus the 1 and 480 month extremes.  The same seed always gives
the same deck, so a failure can be reproduced exactly.
"""
import random
import sys


def main(seed, count, out_path):
    rng = random.Random(seed)
    terms = [1, 2, 3, 6, 12, 24, 36, 48, 60, 72, 84, 120, 180, 240, 300, 360, 480]
    lines = []
    for n in range(1, count + 1):
        cents = int(10 ** rng.uniform(0, 11)) % 100000000000 or 1
        roll = rng.random()
        if roll < 0.08:
            rate = 0
        elif roll < 0.15:
            rate = rng.randint(1, 500)               # 0.0001% - 0.0500%
        else:
            rate = rng.randint(1, 360000)            # up to 36.0000%
        term = rng.choice(terms) if rng.random() < 0.7 else rng.randint(1, 480)
        yyyymm = f"{rng.randint(2026, 2030)}{rng.randint(1, 12):02d}"
        lines.append(f"STR{n:07d}{'STRESS CASE':<30}{cents:011d}{rate:06d}"
                     f"{term:03d}{yyyymm}{rng.choice('MAPC')}".ljust(80))
    with open(out_path, "w", encoding="ascii") as fh:
        fh.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(int(sys.argv[1]), int(sys.argv[2]), sys.argv[3])
