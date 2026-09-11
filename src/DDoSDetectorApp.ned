package sdnddos;

import openflow.controllerApps.AbstractControllerApp;

//
// Controller app that consumes flow statistics, classifies each flow and
// blocks the ones it judges hostile.
//
simple DDoSDetectorApp like AbstractControllerApp
{
    parameters:
        @class(sdnddos::DDoSDetectorApp);
        @display("i=block/control");

        // collect - label from ground truth and write the training CSV, no blocking
        // dt      - classify with the exported Decision Tree
        // kmeans  - classify with the exported K-Means detector
        string mode = default("collect");

        bool writeCsv = default(false);
        string csvFile = default("../data/flows.csv");

        // How long a block lasts. Bounded on purpose: a false positive should
        // cost a few seconds of one host's traffic, not the whole run.
        double blockDuration @unit("s") = default(10s);

        // Ground truth for labelling and scoring only - never a model input.
        // Space-separated full module paths.
        string attackerModules = default("");

        int priority = default(1);
}
