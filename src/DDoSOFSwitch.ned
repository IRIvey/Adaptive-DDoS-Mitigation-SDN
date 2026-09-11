package sdnddos;

import inet.linklayer.contract.IWiredNic;
import inet.linklayer.ethernet.EthernetInterface;
import inet.networklayer.common.InterfaceTable;
import inet.networklayer.contract.INetworkLayer;
import inet.networklayer.contract.IRoutingTable;
import inet.transportlayer.contract.ITCP;

//
// Switch node wrapping DDoSSwitch instead of the stock OF_Switch.
//
// This is a near-copy of openflow.openflow.switch.Open_Flow_Switch. It exists
// only because that module hardcodes its relay submodule as `OF_Switch: OF_Switch`
// rather than declaring it `like IOpenFlowRelayUnit`, so the type cannot be
// swapped from the ini file.
//
// The submodule keeps the name `OF_Switch` on purpose, so every `**.OF_Switch.*`
// parameter pattern from the upstream scenarios still applies unchanged.
//
module DDoSOFSwitch
{
    parameters:
        @networkNode();
        @OF_Switch();
        @labels(node,ethernet-node);
        @display("i=device/switch;i2=openflow/OpenFlow-Logo-small");
        bool sendCompletePacket = default(false);
        double serviceTime @unit("s") = default(0s);
        bool csmacdSupport = default(true);
        string macType = default(csmacdSupport ? "EtherMAC" : "EtherMACFullDuplex");

        string networkLayerType = default("IPv4NetworkLayer");
        string routingTableType = default("IPv4RoutingTable");

        string tcpType = default("TCP");
        bool forwarding = default(false);
        bool multicastForwarding = default(false);
        string routingFile = default("");

        routingTable.forwarding = this.forwarding;
        routingTable.multicastForwarding = this.multicastForwarding;
        *.routingTableModule = default(absPath(".routingTable"));
        *.interfaceTableModule = default(absPath(".interfaceTable"));
        etherMAC[*].encapType = default("EtherEncapDummy");
        etherMAC[*].csmacdSupport = this.csmacdSupport;
        etherMAC[*].macType = this.macType;
        networkLayer.proxyARP = default(false);

    gates:
        inout gateControlPlane[] @labels(ControlPlane);
        inout gateDataPlane[] @labels(DataPlane);

    submodules:
        interfaceTable: InterfaceTable {
            parameters:
                @display("p=446,203");
        }
        tcp: <tcpType> like ITCP {
            parameters:
                @display("p=315,90");
        }
        routingTable: <routingTableType> like IRoutingTable if routingTableType != "" {
            parameters:
                @display("p=200,203");
        }
        networkLayer: <networkLayerType> like INetworkLayer {
            parameters:
                @display("p=200,90;q=queue");
            gates:
                ifIn[sizeof(parent.gateControlPlane)];
                ifOut[sizeof(parent.gateControlPlane)];
        }
        eth[sizeof(this.gateControlPlane)]: EthernetInterface {
            parameters:
                @display("p=75,90,row,90;q=txQueue");
        }
        etherMAC[sizeof(gateDataPlane)]: <default("EthernetInterface")> like IWiredNic {
            parameters:
                mac.promiscuous = default(true);
                @display("p=633,90,c,70");
        }

        OF_Switch: DDoSSwitch {
            @display("p=446,90");
            sendCompletePacket = parent.sendCompletePacket;
            gates:
                dataPlaneOut[sizeof(parent.gateDataPlane)];
                dataPlaneIn[sizeof(parent.gateDataPlane)];
        }

    connections allowunconnected:
        for i=0..sizeof(this.gateControlPlane)-1 {
            eth[i].phys <--> gateControlPlane[i];
            eth[i].upperLayerOut --> networkLayer.ifIn[i];
            eth[i].upperLayerIn <-- networkLayer.ifOut[i];
        }

        for i=0..sizeof(gateDataPlane)-1 {
            etherMAC[i].phys <--> gateDataPlane[i];
            OF_Switch.dataPlaneOut[i] --> etherMAC[i].upperLayerIn;
            etherMAC[i].upperLayerOut --> OF_Switch.dataPlaneIn[i];
        }
        tcp.ipOut --> networkLayer.transportIn++;
        tcp.ipIn <-- networkLayer.transportOut++;

        tcp.appOut++ --> OF_Switch.controlPlaneIn;
        OF_Switch.controlPlaneOut --> tcp.appIn++;
}
