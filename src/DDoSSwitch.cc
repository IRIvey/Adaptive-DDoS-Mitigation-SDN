#include "DDoSSwitch.h"

#include "DDoSMessages_m.h"

#include "inet/networklayer/common/L3AddressResolver.h"
#include "inet/networklayer/ipv4/IPv4Datagram.h"
#include "inet/transportlayer/tcp_common/TCPSegment.h"
#include "inet/transportlayer/udp/UDPPacket.h"
#include "openflow/openflow/protocol/OpenFlow.h"

using namespace omnetpp;
using namespace inet;

namespace sdnddos {

Define_Module(DDoSSwitch);

// Kept well clear of the base class's own kinds (1 and 3).
#define MSGKIND_DDOS_STATS 9101

// Link colouring thresholds, in bytes per second on a 100 Mbit/s link.
// A normal client sits near 10 kB/s and the flood near 350 kB/s, so these
// sit either side of the gap rather than being round numbers for their own
// sake.
static const double ACTIVE_BYTES_PER_SEC = 20000.0;
static const double BUSY_BYTES_PER_SEC = 100000.0;

DDoSSwitch::~DDoSSwitch()
{
    cancelAndDelete(statsTimer);
}

void DDoSSwitch::initialize()
{
    openflow::OF_Switch::initialize();

    statsInterval = par("statsInterval").doubleValue();

    statsTimer = new cMessage("ddosStatsTimer");
    statsTimer->setKind(MSGKIND_DDOS_STATS);
    // Offset the first report so it does not land during the OpenFlow
    // handshake, when there is no socket to send it on yet.
    scheduleAt(simTime() + statsInterval + 1.0, statsTimer);
}

bool DDoSSwitch::extractIpv4(EthernetIIFrame *frame,
                             uint32_t& srcIp, uint32_t& dstIp, uint16_t& proto,
                             uint16_t& srcPort, uint16_t& dstPort)
{
    cPacket *payload = frame->getEncapsulatedPacket();
    IPv4Datagram *ip = dynamic_cast<IPv4Datagram *>(payload);
    if (ip == nullptr)
        return false;                       // ARP, LLDP and friends

    srcIp = ip->getSrcAddress().getInt();
    dstIp = ip->getDestAddress().getInt();
    proto = static_cast<uint16_t>(ip->getTransportProtocol());

    srcPort = 0;
    dstPort = 0;
    cPacket *transport = ip->getEncapsulatedPacket();
    if (UDPPacket *udp = dynamic_cast<UDPPacket *>(transport)) {
        srcPort = udp->getSourcePort();
        dstPort = udp->getDestinationPort();
    }
    else if (tcp::TCPSegment *seg = dynamic_cast<tcp::TCPSegment *>(transport)) {
        srcPort = seg->getSrcPort();
        dstPort = seg->getDestPort();
    }
    return true;
}

bool DDoSSwitch::isBlocked(uint32_t inPort, uint32_t srcIp)
{
    auto it = blocked.find(std::make_pair(inPort, srcIp));
    if (it == blocked.end())
        return false;

    if (simTime() >= it->second) {
        // Block expired. Letting it lapse rather than persist means a false
        // positive costs a bounded amount of legitimate traffic.
        blocked.erase(it);
        setHostAlarm(srcIp, false);
        refreshBlockDisplay();
        return false;
    }
    return true;
}

void DDoSSwitch::setHostAlarm(uint32_t srcIp, bool blocked_now)
{
    cModule *host = L3AddressResolver().findHostWithAddress(IPv4Address(srcIp));
    if (host == nullptr)
        return;

    // Argument 1 of the "i" tag is the icon tint. Only the tint is touched, so
    // whatever icon the topology gave the host survives.
    host->getDisplayString().setTagArg("i", 1, blocked_now ? "red" : "");
    if (blocked_now)
        host->bubble("blocked");
}

void DDoSSwitch::colourLinks()
{
    cModule *node = getParentModule();
    const int n = gateSize("dataPlaneIn");

    for (int i = 0; i < n; i++) {
        cGate *g = node->gate("gateDataPlane$o", i);
        if (g == nullptr)
            continue;

        const double rate = portBytes[i] / statsInterval;
        cDisplayString& ds = g->getDisplayString();

        if (rate > BUSY_BYTES_PER_SEC) {
            ds.setTagArg("ls", 0, "red");
            ds.setTagArg("ls", 1, "4");
        }
        else if (rate > ACTIVE_BYTES_PER_SEC) {
            ds.setTagArg("ls", 0, "orange");
            ds.setTagArg("ls", 1, "2");
        }
        else {
            ds.setTagArg("ls", 0, "");
            ds.setTagArg("ls", 1, "1");
        }
    }
    portBytes.clear();
}

void DDoSSwitch::refreshBlockDisplay()
{
    char buf[96];
    snprintf(buf, sizeof(buf), "blocking %d source(s)\n%ld frames dropped",
             (int)blocked.size(), framesDroppedByBlock);
    getDisplayString().setTagArg("t", 0, buf);
}

void DDoSSwitch::recordFrame(EthernetIIFrame *frame, uint32_t inPort)
{
    uint32_t srcIp, dstIp;
    uint16_t proto, srcPort, dstPort;
    if (!extractIpv4(frame, srcIp, dstIp, proto, srcPort, dstPort))
        return;

    FlowKey key{inPort, srcIp, dstIp, proto, srcPort, dstPort};
    auto& acc = flows[key];
    if (acc.packets == 0 && acc.firstSeen == SIMTIME_ZERO)
        acc.firstSeen = simTime();

    acc.packets++;
    acc.bytes += static_cast<long>(frame->getByteLength());

    seenDirections.insert(
            std::make_tuple(srcIp, dstIp, proto, srcPort, dstPort));
}

void DDoSSwitch::sendStatsReport()
{
    // Keep the on-screen state live rather than only updating it when a block
    // is installed. Both run before the early returns below, so the picture
    // stays current even in an interval with nothing to report.
    refreshBlockDisplay();
    colourLinks();

    // Nothing to say, or nowhere to say it.
    if (flows.empty() || socket.getState() != TCPSocket::CONNECTED) {
        flows.clear();
        return;
    }

    // Only flows that actually carried traffic this interval get reported. An
    // idle flow still sitting in the map would otherwise produce a row of
    // zeroes, which is not an observation of anything and just dilutes the
    // dataset with noise.
    std::vector<const std::pair<const FlowKey, FlowAcc> *> active;
    for (auto& kv : flows)
        if (kv.second.packets > 0)
            active.push_back(&kv);

    if (active.empty()) {
        return;
    }

    // How many distinct sources were active on each ingress port this interval.
    // Source spoofing inflates this; so does a legitimate uplink carrying many
    // hosts, which is why it is a feature and not a rule.
    std::map<uint32_t, std::set<uint32_t>> srcsPerPort;
    for (auto *kv : active)
        srcsPerPort[kv->first.inPort].insert(kv->first.srcIp);

    DDoSFlowStats *msg = new DDoSFlowStats("ddosFlowStats");
    openflow::ofp_header header = msg->getHeader();
    header.version = OFP_VERSION;
    // OFPT_VENDOR is what the controller routes to apps as PacketExperimenter.
    header.type = openflow::OFPT_VENDOR;
    msg->setHeader(header);
    msg->setFlowsArraySize(active.size());

    size_t i = 0;
    const simtime_t now = simTime();
    for (auto *kvp : active) {
        const FlowKey& k = kvp->first;
        const FlowAcc& a = kvp->second;

        FlowRecord rec;
        rec.inPort = k.inPort;
        rec.srcIp = k.srcIp;
        rec.dstIp = k.dstIp;
        rec.proto = k.proto;
        rec.srcPort = k.srcPort;
        rec.dstPort = k.dstPort;

        rec.pktRate = a.packets / statsInterval;
        rec.byteRate = a.bytes / statsInterval;
        rec.avgPktSize = a.packets > 0 ? (double)a.bytes / a.packets : 0.0;
        rec.duration = (now - a.firstSeen).dbl();
        // Reverse direction: addresses and ports both swapped.
        rec.pairFlow = seenDirections.count(std::make_tuple(
                k.dstIp, k.srcIp, k.proto, k.dstPort, k.srcPort)) > 0 ? 1.0 : 0.0;
        rec.portSrcCount = srcsPerPort[k.inPort].size();

        msg->setFlows(i++, rec);
    }

    msg->setByteLength(16 + 40 * active.size());
    msg->setKind(TCP_C_SEND);
    socket.send(msg);
    statsReportsSent++;

    // Counters reset each interval so rates describe the interval, not the
    // whole run. firstSeen is intentionally not reset - flow age is cumulative.
    for (auto& kv : flows) {
        kv.second.packets = 0;
        kv.second.bytes = 0;
    }
}

void DDoSSwitch::handleMessage(cMessage *msg)
{
    // --- our own stats timer -------------------------------------------
    if (msg->isSelfMessage() && msg->getKind() == MSGKIND_DDOS_STATS) {
        sendStatsReport();
        scheduleAt(simTime() + statsInterval, msg);
        return;
    }

    // --- block instruction from the controller --------------------------
    if (DDoSBlockCommand *cmd = dynamic_cast<DDoSBlockCommand *>(msg)) {
        blocked[std::make_pair(cmd->getInPort(), cmd->getSrcIp())] =
                simTime() + cmd->getDurationSec();
        EV << "DDoSSwitch: blocking source " << cmd->getSrcIp()
           << " on port " << cmd->getInPort()
           << " for " << cmd->getDurationSec() << "s\n";

        // Make it visible on screen: the attacker turns red and the switch
        // announces the block.
        const std::string who = IPv4Address(cmd->getSrcIp()).str();
        bubble(("BLOCKED " + who).c_str());
        setHostAlarm(cmd->getSrcIp(), true);
        refreshBlockDisplay();

        delete cmd;
        return;
    }

    // --- data plane ------------------------------------------------------
    cGate *arrival = msg->getArrivalGate();
    if (arrival != nullptr && strcmp(arrival->getBaseName(), "dataPlaneIn") == 0) {
        if (EthernetIIFrame *frame = dynamic_cast<EthernetIIFrame *>(msg)) {
            uint32_t inPort = arrival->getIndex();

            // Counted before the block check on purpose: this is wire load, and
            // a blocked attacker is still filling the cable.
            portBytes[inPort] += static_cast<long>(frame->getByteLength());

            uint32_t srcIp, dstIp;
            uint16_t proto, srcPort, dstPort;
            if (extractIpv4(frame, srcIp, dstIp, proto, srcPort, dstPort)
                    && isBlocked(inPort, srcIp)) {
                // This is the mitigation actually taking effect: the frame is
                // destroyed here and never reaches the forwarding logic.
                framesDroppedByBlock++;
                delete frame;
                return;
            }

            recordFrame(frame, inPort);
        }
    }

    openflow::OF_Switch::handleMessage(msg);
}

void DDoSSwitch::finish()
{
    openflow::OF_Switch::finish();
    recordScalar("framesDroppedByBlock", framesDroppedByBlock);
    recordScalar("statsReportsSent", statsReportsSent);
    recordScalar("blockedEntries", (double)blocked.size());
}

} // namespace sdnddos
