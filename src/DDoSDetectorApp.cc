#include "DDoSDetectorApp.h"

#include "DDoSMessages_m.h"
#include "DecisionTree.h"
#include "KMeansModel.h"

#include "inet/networklayer/common/L3AddressResolver.h"
#include "inet/networklayer/contract/ipv4/IPv4Address.h"
#include "openflow/openflow/controller/Switch_Info.h"

using namespace omnetpp;
using namespace inet;

namespace sdnddos {

Define_Module(DDoSDetectorApp);

DDoSDetectorApp::~DDoSDetectorApp()
{
    if (csv.is_open())
        csv.close();
}

void DDoSDetectorApp::initialize()
{
    openflow::AbstractControllerApp::initialize();

    const std::string m = par("mode").stdstringValue();
    if (m == "collect")      mode = MODE_COLLECT;
    else if (m == "dt")      mode = MODE_DT;
    else if (m == "kmeans")  mode = MODE_KMEANS;
    else throw cRuntimeError("DDoSDetectorApp: unknown mode '%s' "
                             "(expected collect, dt or kmeans)", m.c_str());

    blockDuration = par("blockDuration").doubleValue();
    writeCsv = par("writeCsv").boolValue();
    csvPath = par("csvFile").stdstringValue();

    if (writeCsv) {
        csv.open(csvPath.c_str(), std::ios::out | std::ios::trunc);
        if (!csv.is_open())
            throw cRuntimeError("DDoSDetectorApp: cannot open '%s' for writing",
                                csvPath.c_str());
        // Header must match ml/schema.py CSV_COLUMNS exactly.
        csv << "time,switch_id,src_ip,dst_ip,proto,src_port,dst_port,in_port,"
            << "pkt_rate,byte_rate,avg_pkt_size,duration,pair_flow,port_src_count,"
            << "label\n";
    }

    // Attacker addresses are resolved lazily, not here: interface tables are
    // still empty during initialization, and L3AddressResolver throws.
}

void DDoSDetectorApp::resolveAttackers()
{
    attackersResolved = true;

    // Ground truth comes from the simulation setup, not from the traffic. It
    // is used to label the training data and to score detection afterwards -
    // never as an input to a classifier.
    const char *mods = par("attackerModules");
    cStringTokenizer tok(mods);
    while (tok.hasMoreTokens()) {
        const char *path = tok.nextToken();
        cModule *m = getSimulation()->getModuleByPath(path);
        if (m == nullptr) {
            EV_WARN << "DDoSDetectorApp: attacker module '" << path
                    << "' not found\n";
            continue;
        }
        L3Address addr = L3AddressResolver().addressOf(m);
        attackerIps.insert(addr.toIPv4().getInt());
        EV << "DDoSDetectorApp: attacker " << path << " = "
           << addr.str() << "\n";
    }
}

void DDoSDetectorApp::receiveSignal(cComponent *src, simsignal_t id,
                                    cObject *obj, cObject *details)
{
    openflow::AbstractControllerApp::receiveSignal(src, id, obj, details);

    if (id == PacketExperimenterSignalId) {
        if (DDoSFlowStats *stats = dynamic_cast<DDoSFlowStats *>(obj))
            handleFlowStats(stats);
    }
}

void DDoSDetectorApp::handleFlowStats(DDoSFlowStats *stats)
{
    if (!attackersResolved)
        resolveAttackers();

    std::string switchId = "sw";
    if (openflow::Switch_Info *info = controller->findSwitchInfoFor(stats))
        switchId = info->getMacAddress();

    const size_t n = stats->getFlowsArraySize();
    for (size_t i = 0; i < n; i++) {
        const FlowRecord& r = stats->getFlows(i);
        flowsSeen++;

        // Feature order is fixed by ml/schema.py and by the generated headers.
        // Do not reorder without regenerating both.
        const double f[6] = {
            r.pktRate,
            r.byteRate,
            r.avgPktSize,
            r.duration,
            r.pairFlow,
            r.portSrcCount
        };

        const bool isAttacker = attackerIps.count(r.srcIp) > 0;
        if (isAttacker && firstAttackFlowSeen < SIMTIME_ZERO)
            firstAttackFlowSeen = simTime();

        int verdict = 0;
        switch (mode) {
            case MODE_DT:     verdict = dtClassify(f); break;
            case MODE_KMEANS: verdict = kmClassify(f); break;
            case MODE_COLLECT:
            default:          verdict = 0; break;   // observe only
        }

        if (writeCsv) {
            csv << simTime().dbl() << ','
                << switchId << ','
                << IPv4Address(r.srcIp).str() << ','
                << IPv4Address(r.dstIp).str() << ','
                << r.proto << ','
                << r.srcPort << ','
                << r.dstPort << ','
                << r.inPort << ','
                << r.pktRate << ','
                << r.byteRate << ','
                << r.avgPktSize << ','
                << r.duration << ','
                << r.pairFlow << ','
                << r.portSrcCount << ','
                << (isAttacker ? 1 : 0) << '\n';
            rowsWritten++;
        }

        if (mode == MODE_COLLECT)
            continue;

        // Scoring against ground truth, per flow record.
        if (verdict == 1 && isAttacker)       truePos++;
        else if (verdict == 1 && !isAttacker) falsePos++;
        else if (verdict == 0 && isAttacker)  falseNeg++;
        else                                  trueNeg++;

        if (verdict == 1) {
            detections++;
            if (firstDetection < SIMTIME_ZERO)
                firstDetection = simTime();
            if (isAttacker && firstTrueDetection < SIMTIME_ZERO)
                firstTrueDetection = simTime();
            if (!isAttacker && firstAttackFlowSeen < SIMTIME_ZERO)
                falsePositivesBeforeAttack++;   // fired before any attack existed
            sendBlock(r.inPort, r.srcIp, stats);
        }
    }
}

void DDoSDetectorApp::sendBlock(uint32_t inPort, uint32_t srcIp, cMessage *context)
{
    TCPSocket *socket = controller->findSocketFor(context);
    if (socket == nullptr) {
        EV_WARN << "DDoSDetectorApp: no socket to the reporting switch\n";
        return;
    }

    DDoSBlockCommand *cmd = new DDoSBlockCommand("ddosBlock");
    openflow::ofp_header header = cmd->getHeader();
    header.version = OFP_VERSION;
    header.type = openflow::OFPT_VENDOR;
    cmd->setHeader(header);
    cmd->setInPort(inPort);
    cmd->setSrcIp(srcIp);
    cmd->setDurationSec(blockDuration);
    cmd->setByteLength(24);
    cmd->setKind(TCP_C_SEND);

    socket->send(cmd);
    blocksIssued++;
}

void DDoSDetectorApp::finish()
{
    openflow::AbstractControllerApp::finish();

    if (csv.is_open())
        csv.close();

    recordScalar("flowsSeen", flowsSeen);
    recordScalar("rowsWritten", rowsWritten);
    recordScalar("detections", detections);
    recordScalar("blocksIssued", blocksIssued);

    if (mode != MODE_COLLECT) {
        recordScalar("truePositives", truePos);
        recordScalar("falsePositives", falsePos);
        recordScalar("trueNegatives", trueNeg);
        recordScalar("falseNegatives", falseNeg);

        const double prec = (truePos + falsePos) > 0
                ? (double)truePos / (truePos + falsePos) : 0.0;
        const double rec = (truePos + falseNeg) > 0
                ? (double)truePos / (truePos + falseNeg) : 0.0;
        recordScalar("precision", prec);
        recordScalar("recall", rec);
        recordScalar("f1", (prec + rec) > 0 ? 2 * prec * rec / (prec + rec) : 0.0);
        recordScalar("falsePositiveRate", (falsePos + trueNeg) > 0
                ? (double)falsePos / (falsePos + trueNeg) : 0.0);

        // How long the attack ran before it was correctly identified.
        //
        // Measured from the first attack flow to the first *true* detection.
        // Using any detection instead makes this go negative whenever a model
        // raises a false positive before the attack even starts, which is
        // exactly what K-Means did.
        if (firstTrueDetection >= SIMTIME_ZERO && firstAttackFlowSeen >= SIMTIME_ZERO)
            recordScalar("detectionLatency",
                         (firstTrueDetection - firstAttackFlowSeen).dbl());

        recordScalar("falsePositivesBeforeAttack", falsePositivesBeforeAttack);
    }
}

} // namespace sdnddos
