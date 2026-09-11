package sdnddos;

import openflow.openflow.switch.OF_Switch;

//
// OpenFlow switch that also measures per-flow traffic and can drop a blocked
// source. Inherits every parameter and gate from OF_Switch; the only addition
// is how often it reports.
//
simple DDoSSwitch extends OF_Switch
{
    parameters:
        @class(sdnddos::DDoSSwitch);
        @display("i=block/app;i2=status/asterisk");

        // Detection cadence. Shorter reacts faster but reports more often and
        // makes each rate estimate noisier.
        double statsInterval @unit("s") = default(1s);
}
