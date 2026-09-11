import openflow.messages.Open_Flow_Message;

namespace sdnddos;

//
// Statistics for one observed flow during one collection interval.
//
// The model's flow table stores no packet or byte counters and there is no
// flow-stats message in the protocol implementation, so the switch has to do
// this accounting itself and ship it up. Field order here is deliberate: it
// matches ml/schema.py FEATURES exactly, because the same six numbers are fed
// to the classifier on the controller.
//
struct FlowRecord
{
    uint32_t inPort;          // ingress port - what mitigation acts on
    uint32_t srcIp;           // IPv4 as integer
    uint32_t dstIp;
    uint16_t proto;
    uint16_t srcPort;         // 0 for protocols without ports (e.g. ICMP)
    uint16_t dstPort;

    double pktRate;           // feature 0
    double byteRate;          // feature 1
    double avgPktSize;        // feature 2
    double duration;          // feature 3
    double pairFlow;          // feature 4  (0 or 1)
    double portSrcCount;      // feature 5
}

//
// Switch -> controller. Sent on a timer, carrying every flow seen in the
// interval. Rides the OpenFlow vendor/experimenter channel (OFPT_VENDOR),
// which the controller already forwards to apps as a PacketExperimenter
// signal - so no change to the model is required.
//
packet DDoSFlowStats extends openflow::Open_Flow_Message
{
    FlowRecord flows[];
}

//
// Controller -> switch. Blocks one source on one ingress port.
//
// A flow-mod cannot express this: the switch's forwarding path reads an
// output port straight out of the matched entry and has no notion of an empty
// action list meaning "drop". Our switch subclass therefore implements the
// drop itself, and this is the instruction that turns it on.
//
packet DDoSBlockCommand extends openflow::Open_Flow_Message
{
    uint32_t inPort;
    uint32_t srcIp;
    double durationSec;       // block expires after this, so a false positive
                              // is recoverable rather than permanent
}
