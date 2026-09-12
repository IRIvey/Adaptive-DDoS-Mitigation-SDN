#include "DDoSDetectorApp.h"

#include "DDoSMessages_m.h"
#include "DecisionTree.h"
#include "KMeansModel.h"

#include <algorithm>

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
    else if (m == "hybrid")  mode = MODE_HYBRID;
    else if (m == "cost")    mode = MODE_COST;
    else throw cRuntimeError("DDoSDetectorApp: unknown mode '%s' (expected "
                             "collect, dt, kmeans, hybrid or cost)", m.c_str());

    confirmations = par("confirmations").intValue();
    falseBlockCost = par("falseBlockCost").doubleValue();
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

    // A caption on the network canvas, so an audience can see which detector is
    // running and whether it is currently blocking anything.
    banner = new cTextFigure("ddosStatus");
    banner->setPosition(cFigure::Point(14, 14));
    banner->setAnchor(cFigure::ANCHOR_NW);
    banner->setFont(cFigure::Font("Arial", 14, cFigure::FONT_BOLD));
    banner->setColor(cFigure::Color("#0F6E7A"));
    banner->setText("DDoS detector ready");
    getSimulation()->getSystemModule()->getCanvas()->addFigure(banner);

    // Attacker addresses are resolved lazily, not here: interface tables are
    // still empty during initialization, and L3AddressResolver throws.
}

const char *DDoSDetectorApp::modeName() const
{
    switch (mode) {
        case MODE_DT:     return "Decision Tree";
        case MODE_KMEANS: return "K-Means";
        case MODE_HYBRID: return "Hybrid";
        case MODE_COST:   return "Expected cost";
        default:          return "Collecting data";
    }
}

void DDoSDetectorApp::updateBanner()
{
    if (banner == nullptr)
        return;

    // "Under attack" means something was flagged recently, not ever - so the
    // caption goes back to calm once the network settles.
    const bool active = (lastDetection >= SIMTIME_ZERO)
                        && (simTime() - lastDetection < 5.0);

    char buf[200];
    if (mode == MODE_COLLECT) {
        snprintf(buf, sizeof(buf), "COLLECTING DATA  -  %ld rows written",
                 rowsWritten);
    }
    else {
        snprintf(buf, sizeof(buf),
                 "%s  -  %s   |   blocks issued: %ld   |   false alarms: %ld",
                 modeName(), active ? "ATTACK DETECTED" : "traffic normal",
                 blocksIssued, falsePos);
    }
    banner->setText(buf);
    banner->setColor(active ? cFigure::Color("#A3402F")
                            : cFigure::Color("#0F6E7A"));
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
        bool viaTree = false;
        switch (mode) {
            case MODE_DT:
                verdict = dtClassify(f);
                viaTree = (verdict == 1);
                break;

            case MODE_KMEANS:
                verdict = kmClassify(f);
                break;

            case MODE_HYBRID: {
                const auto key = std::make_pair(r.inPort, r.srcIp);
                if (dtClassify(f) == 1) {
                    // A shape the tree was trained on. It has not produced a
                    // single false positive in any run, so act immediately -
                    // waiting would only let the flood through for longer.
                    verdict = 1;
                    viaTree = true;
                    suspicion.erase(key);
                }
                else if (kmClassify(f) == 1) {
                    // Unfamiliar to the tree, but it does not look like normal
                    // traffic. Require the anomaly to persist before blocking:
                    // a bursty client is odd for one interval, an attack stays
                    // odd. This is where the false positives get filtered out,
                    // and where the added detection delay comes from.
                    if (++suspicion[key] >= confirmations) {
                        verdict = 1;
                        suspicion.erase(key);
                    }
                }
                else {
                    suspicion.erase(key);   // back to looking normal
                }
                break;
            }

            case MODE_COST: {
                // Expectimax at depth one: score both actions by expected cost
                // and take the cheaper, instead of thresholding a yes/no.
                //
                // K-Means gives a distance rather than a verdict, so it can act
                // as a confidence. d/(d+threshold) is 0.5 exactly at the
                // threshold and approaches 1 as the flow gets stranger. The
                // tree is trusted when it fires, because it has never been
                // wrong in any run.
                const double d = kmDistance(f);
                double p = d / (d + kmeans::THRESHOLD);
                const bool treeSaysAttack = (dtClassify(f) == 1);
                if (treeSaysAttack)
                    p = std::max(p, 0.99);

                // Letting an attack through costs the bytes it delivers to the
                // victim; blocking a legitimate flow costs a fixed penalty.
                const double costOfAllowing = p * r.byteRate;
                const double costOfBlocking = (1.0 - p) * falseBlockCost;

                verdict = (costOfAllowing > costOfBlocking) ? 1 : 0;
                viaTree = (verdict == 1 && treeSaysAttack);
                break;
            }

            case MODE_COLLECT:
            default:
                verdict = 0;                // observe only
                break;
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
            if (viaTree) blocksFromTree++; else blocksFromKMeans++;
            if (firstDetection < SIMTIME_ZERO)
                firstDetection = simTime();
            lastDetection = simTime();
            if (isAttacker && firstTrueDetection < SIMTIME_ZERO)
                firstTrueDetection = simTime();
            if (!isAttacker && firstAttackFlowSeen < SIMTIME_ZERO)
                falsePositivesBeforeAttack++;   // fired before any attack existed
            sendBlock(r.inPort, r.srcIp, stats);
        }
    }

    updateBanner();
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

        if (mode == MODE_HYBRID) {
            // Which half of the hybrid did the work.
            recordScalar("blocksFromTree", blocksFromTree);
            recordScalar("blocksFromKMeans", blocksFromKMeans);
        }
    }
}

} // namespace sdnddos
