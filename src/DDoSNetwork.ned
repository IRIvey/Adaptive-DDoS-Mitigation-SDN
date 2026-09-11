package sdnddos;

import inet.common.misc.ThruputMeteringChannel;
import inet.networklayer.configurator.ipv4.IPv4NetworkConfigurator;
import inet.node.ethernet.EtherSwitch;
import inet.node.inet.StandardHost;
import openflow.openflow.controller.Open_Flow_Controller;

//
// SDN topology for the DDoS detection experiment.
//
// One OpenFlow switch, so every flow crosses exactly one decision point and
// the effect of a block is unambiguous.
//
// The one piece of deliberate structure is the access switch. The attackers
// and the first `numSharedNormal` clients sit behind it and therefore all
// arrive on a single OpenFlow port. Two things follow, both wanted:
//
//   - port_src_count becomes a real signal instead of a constant 1, because
//     one ingress port genuinely carries several source addresses;
//   - blocking that whole port would take innocent clients down with the
//     attackers, so mitigation has to act per source. The topology creates
//     the collateral-damage risk that the design is meant to avoid.
//
network DDoSNetwork
{
    parameters:
        int numNormal = default(3);
        int numAttacker = default(2);

        // Normal clients placed behind the shared access switch, alongside the
        // attackers. The remainder connect straight to the OpenFlow switch.
        int numSharedNormal = default(2);

        @display("bgb=900,620");

    types:
        // Access links. Kept modest so a flood can actually saturate them -
        // on a 10Gbps link the attack would be invisible in the throughput.
        channel accessLink extends ThruputMeteringChannel
        {
            delay = 1us;
            datarate = 100Mbps;
            thruputDisplayFormat = "u";
        }
        // Switch-to-controller link. Fast and separate from the data plane:
        // control traffic must not be the thing that breaks under load.
        channel controlLink extends ThruputMeteringChannel
        {
            delay = 1us;
            datarate = 1Gbps;
            thruputDisplayFormat = "u";
        }

    submodules:
        configurator: IPv4NetworkConfigurator {
            @display("p=70,60");
        }

        controller: Open_Flow_Controller {
            @display("p=480,80");
        }

        // DDoSOFSwitch rather than the stock Open_Flow_Switch: it wraps our
        // measuring/blocking relay unit. Identical wiring otherwise.
        sw: DDoSOFSwitch {
            @display("p=480,250");
        }

        // Plain layer-2 switch. Everything behind it shares one OpenFlow port.
        // Centred over the four hosts it serves.
        access: EtherSwitch {
            @display("p=315,390;i=device/switch");
        }

        // Layout: attackers on the left, clients to their right. That keeps the
        // four hosts sharing the access switch side by side, with the one client
        // that has its own switch port (the last) out on its own at the far
        // right. Rows are 170 apart because labels do not shrink when the GUI
        // zooms out - at 110 the names ran into each other.
        attacker[numAttacker]: StandardHost {
            @display("p=60,520,row,170;i=device/laptop;i2=status/excl3");
        }

        normalHost[numNormal]: StandardHost {
            @display("p=400,520,row,170;i=device/laptop");
        }

        victim: StandardHost {
            @display("p=800,250;i=device/server");
        }

    connections:
        sw.gateControlPlane++ <--> controlLink <--> controller.ethg++;

        // Connected first on purpose: this becomes gateDataPlane[0], so the
        // shared port is port 0 and is easy to identify in the results.
        access.ethg++ <--> accessLink <--> sw.gateDataPlane++;

        // Clients sharing the access switch with the attackers.
        for i = 0..numSharedNormal - 1 {
            normalHost[i].ethg++ <--> accessLink <--> access.ethg++;
        }

        // Clients with a port to themselves.
        for i = numSharedNormal..numNormal - 1 {
            normalHost[i].ethg++ <--> accessLink <--> sw.gateDataPlane++;
        }

        // Every attacker is behind the access switch.
        for i = 0..numAttacker - 1 {
            attacker[i].ethg++ <--> accessLink <--> access.ethg++;
        }

        victim.ethg++ <--> accessLink <--> sw.gateDataPlane++;
}
