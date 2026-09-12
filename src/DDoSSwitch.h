#ifndef SDNDDOS_DDOSSWITCH_H_
#define SDNDDOS_DDOSSWITCH_H_

#include <map>
#include <set>
#include <tuple>
#include <utility>

#include <omnetpp.h>

#include "inet/linklayer/ethernet/EtherFrame_m.h"
#include "openflow/openflow/switch/OF_Switch.h"

namespace sdnddos {

/**
 * An OpenFlow switch that also measures traffic.
 *
 * The upstream model has no flow statistics of any kind: OF_FlowTableEntry
 * stores creation and last-match timestamps but no counters, and the protocol
 * implementation has no stats request/reply message. Everything the detector
 * needs therefore has to be measured here.
 *
 * This is a subclass rather than a patch. OF_Switch::handleMessage is virtual
 * and its members are protected, so tapping the data plane, reporting stats
 * and dropping blocked traffic can all be done without touching the vendored
 * model - which stays a clean checkout.
 */
class DDoSSwitch : public openflow::OF_Switch
{
  public:
    virtual ~DDoSSwitch();

  protected:
    /**
     * Identity of a unidirectional flow as this switch sees it.
     *
     * Transport ports are part of the key. Without them two different services
     * between the same pair of hosts collapse into one flow - a client's
     * answered echo traffic and its unanswered telemetry merge, and the merged
     * flow inherits the replies, so pair_flow reads 1 for traffic that is
     * actually one-way.
     */
    struct FlowKey {
        uint32_t inPort;
        uint32_t srcIp;
        uint32_t dstIp;
        uint16_t proto;
        uint16_t srcPort;
        uint16_t dstPort;

        bool operator<(const FlowKey& o) const {
            if (inPort  != o.inPort)  return inPort  < o.inPort;
            if (srcIp   != o.srcIp)   return srcIp   < o.srcIp;
            if (dstIp   != o.dstIp)   return dstIp   < o.dstIp;
            if (proto   != o.proto)   return proto   < o.proto;
            if (srcPort != o.srcPort) return srcPort < o.srcPort;
            return dstPort < o.dstPort;
        }
    };

    /** A directed flow identity, ignoring which port it arrived on. */
    using Direction = std::tuple<uint32_t, uint32_t, uint16_t, uint16_t, uint16_t>;

    /** Counters accumulated for one flow within the current interval. */
    struct FlowAcc {
        long packets = 0;
        long bytes = 0;
        omnetpp::simtime_t firstSeen = 0;   // survives interval resets
    };

    double statsInterval = 1.0;
    omnetpp::cMessage *statsTimer = nullptr;

    std::map<FlowKey, FlowAcc> flows;

    /**
     * Directed (src, dst, proto) triples ever seen. A flow counts as "paired"
     * when the reverse direction has also been observed - that is what tells a
     * real conversation from a one-way flood.
     *
     * Protocol is part of the key deliberately. Keyed on the address pair
     * alone, a host that holds any TCP session with the victim would have its
     * one-way UDP flows marked paired as well, and the feature would read 1 for
     * every legitimate flow regardless of direction.
     */
    std::set<Direction> seenDirections;

    /** (ingress port, source IP) -> simulation time the block expires. */
    std::map<std::pair<uint32_t, uint32_t>, omnetpp::simtime_t> blocked;

    long framesDroppedByBlock = 0;
    long statsReportsSent = 0;

    virtual void initialize() override;
    virtual void handleMessage(omnetpp::cMessage *msg) override;
    virtual void finish() override;

    /** Accumulate one data-plane frame into the per-flow counters. */
    void recordFrame(inet::EthernetIIFrame *frame, uint32_t inPort);

    /** Build and send the interval report, then reset the counters. */
    void sendStatsReport();

    /** True if this source is currently blocked on this port. */
    bool isBlocked(uint32_t inPort, uint32_t srcIp);

    /**
     * Tint a host's icon red while it is blocked, and clear it when the block
     * lapses. Purely for the GUI - without it the mitigation is invisible on
     * screen, because a dropped packet simply stops existing. No effect when
     * running headless.
     */
    void setHostAlarm(uint32_t srcIp, bool blocked);

    /** Show the live block count and dropped-frame total under the switch. */
    void refreshBlockDisplay();

    /**
     * Colour each data-plane link by how much traffic is physically on it.
     * Blocked frames count too: an attacker keeps transmitting after it is
     * blocked, and the cable should show that even though nothing gets
     * forwarded. Only the line-style tag is touched, so the channel's own
     * throughput label is left intact.
     */
    void colourLinks();

    /** Bytes seen on each ingress port during the current interval. */
    std::map<uint32_t, long> portBytes;

    /**
     * Pull addresses, protocol and transport ports out of an Ethernet frame.
     * Returns false for anything that is not IPv4 (ARP, LLDP). Ports come back
     * as 0 for protocols that have none, such as ICMP.
     */
    bool extractIpv4(inet::EthernetIIFrame *frame,
                     uint32_t& srcIp, uint32_t& dstIp, uint16_t& proto,
                     uint16_t& srcPort, uint16_t& dstPort);
};

} // namespace sdnddos

#endif
