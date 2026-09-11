"""Generate synthetic flow data matching the schema OMNeT++ will produce.

Purpose: let the whole ML pipeline (training, evaluation, C++ export) be built
and tested before the simulator produces a single real row. When real data
arrives, the same train.py runs against it unchanged.

The value ranges below are rough but deliberately overlapping - a slice of
"normal" traffic is bursty enough to collide with low-rate attacks, so the
models cannot separate the classes on packet rate alone. Without that overlap
every model scores 100% and the comparison says nothing.

Usage:
    python make_synthetic.py --out ../data/train.csv
    python make_synthetic.py --out ../data/test_lowrate.csv --intensity 0.2
"""
import argparse
import csv
import random

from schema import CSV_COLUMNS

PROTO_TCP, PROTO_UDP = 6, 17


def _row(rng, t, sw, src, dst, proto, port, feats, label):
    pkt_rate, avg_pkt, dur, pair, nsrc = feats
    return {
        "time": round(t, 2),
        "switch_id": sw,
        "src_ip": src,
        "dst_ip": dst,
        "proto": proto,
        "in_port": port,
        "pkt_rate": round(pkt_rate, 2),
        "byte_rate": round(pkt_rate * avg_pkt, 2),
        "avg_pkt_size": round(avg_pkt, 1),
        "duration": round(dur, 2),
        "pair_flow": pair,
        "port_src_count": nsrc,
        "label": label,
    }


def gen_normal(rng, t, sw):
    """Regular traffic - deliberately spans small and large packets.

    A real network carries plenty of tiny packets (DNS, ACKs, VoIP, gaming),
    so packet size alone must not separate normal from attack. Some flows also
    arrive on an uplink/trunk port, which legitimately carries many distinct
    source IPs - the same signal a spoofed flood produces.
    """
    kind = rng.random()
    if kind < 0.35:                      # interactive / control traffic
        avg_pkt = rng.uniform(60, 260)
        pkt_rate = rng.uniform(2, 60)
    elif kind < 0.92:                    # bulk transfer
        avg_pkt = rng.uniform(500, 1450)
        pkt_rate = rng.uniform(10, 120)
    else:                                # flash crowd burst
        avg_pkt = rng.uniform(200, 1200)
        pkt_rate = rng.uniform(150, 600)

    dur = rng.uniform(0.5, 30.0)
    pair = 1 if rng.random() < 0.88 else 0     # some normal flows are one-way

    if rng.random() < 0.18:              # flow arriving over an uplink port
        nsrc, port = rng.randint(5, 45), 1
    else:
        nsrc, port = rng.randint(1, 3), rng.randint(2, 3)

    return _row(rng, t, sw, f"10.0.0.{rng.randint(1,3)}", "10.0.0.100",
                rng.choice([PROTO_TCP, PROTO_UDP]), port,
                (pkt_rate, avg_pkt, dur, pair, nsrc), 0)


def gen_udp_flood(rng, t, sw, intensity):
    # 30% of attacks come from a small set of real hosts rather than spoofed
    # sources, so a high source count is not a reliable giveaway either.
    spoofed = rng.random() < 0.70
    pkt_rate = rng.uniform(250, 3000) * intensity
    avg_pkt = rng.uniform(60, 520)             # overlaps normal small+medium
    dur = rng.uniform(0.3, 8.0)
    pair = 1 if rng.random() < 0.05 else 0
    nsrc = (max(1, int(rng.uniform(25, 400) * intensity))
            if spoofed else rng.randint(1, 3))
    return _row(rng, t, sw, f"172.16.{rng.randint(0,255)}.{rng.randint(1,254)}",
                "10.0.0.100", PROTO_UDP, rng.choice([4, 5]),
                (pkt_rate, avg_pkt, dur, pair, nsrc), 1)


def gen_syn_flood(rng, t, sw, intensity):
    spoofed = rng.random() < 0.75
    pkt_rate = rng.uniform(200, 2500) * intensity
    avg_pkt = rng.uniform(54, 140)             # overlaps normal control traffic
    dur = rng.uniform(0.2, 6.0)
    pair = 1 if rng.random() < 0.05 else 0
    nsrc = (max(1, int(rng.uniform(30, 500) * intensity))
            if spoofed else rng.randint(1, 3))
    return _row(rng, t, sw, f"192.168.{rng.randint(0,255)}.{rng.randint(1,254)}",
                "10.0.0.100", PROTO_TCP, rng.choice([4, 5]),
                (pkt_rate, avg_pkt, dur, pair, nsrc), 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--normal", type=int, default=3000)
    ap.add_argument("--udp", type=int, default=900)
    ap.add_argument("--syn", type=int, default=900)
    ap.add_argument("--intensity", type=float, default=1.0,
                    help="attack strength multiplier; <1 makes a low-rate "
                         "attack the models were never trained on")
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    rows = []
    t = 0.0
    for _ in range(args.normal):
        t += rng.uniform(0.05, 0.4)
        rows.append(gen_normal(rng, t, rng.randint(1, 3)))
    for _ in range(args.udp):
        t += rng.uniform(0.01, 0.1)
        rows.append(gen_udp_flood(rng, t, rng.randint(1, 3), args.intensity))
    for _ in range(args.syn):
        t += rng.uniform(0.01, 0.1)
        rows.append(gen_syn_flood(rng, t, rng.randint(1, 3), args.intensity))
    rng.shuffle(rows)

    with open(args.out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=CSV_COLUMNS)
        w.writeheader()
        w.writerows(rows)

    n_atk = sum(r["label"] for r in rows)
    print(f"wrote {len(rows)} rows to {args.out} "
          f"({len(rows) - n_atk} normal, {n_atk} attack, "
          f"intensity={args.intensity})")


if __name__ == "__main__":
    main()
