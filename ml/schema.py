"""Shared dataset schema.

One CSV row = one flow, observed by one switch, during one collection interval.

Why per-flow instead of per-switch-window: an aggregate window can only say
"this switch is under attack". It cannot say which port to block. Per-flow rows
carry the identity columns, so the moment a row is classified as attack we
already know the switch, source and ingress port to install the DROP rule on.
"""

# Not fed to the model - used to locate the attacker for mitigation.
IDENTITY = ["time", "switch_id", "src_ip", "dst_ip", "proto",
            "src_port", "dst_port", "in_port"]

# The actual model inputs, in this exact order. The C++ side must use the
# same order when it fills its feature vector.
FEATURES = [
    "pkt_rate",        # packets/second for this flow
    "byte_rate",       # bytes/second for this flow
    "avg_pkt_size",    # bytes/packet
    "duration",        # seconds this flow has been active
    "pair_flow",       # 1 if a reverse flow (dst->src) exists, else 0
    "port_src_count",  # distinct source IPs seen on this ingress port
]

LABEL = "label"        # 0 = normal, 1 = attack

CSV_COLUMNS = IDENTITY + FEATURES + [LABEL]

# Attack classes used when generating/labelling data. The models only ever see
# the binary label; this is for reporting which attack was misclassified.
ATTACK_NONE = "normal"
ATTACK_UDP = "udp_flood"
ATTACK_SYN = "syn_flood"
