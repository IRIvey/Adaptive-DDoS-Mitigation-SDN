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
        // hybrid  - tree blocks immediately; K-Means must agree with itself
        //           across `confirmations` consecutive reports before blocking
        // cost    - pick the action with the lower expected cost, using the
        //           K-Means distance as a confidence
        string mode = default("collect");

        // Cost mode only. What avoiding one wrongly blocked flow is worth, in
        // bytes of attack traffic. Higher = more cautious about blocking.
        double falseBlockCost = default(200000);

        // Hybrid only. Consecutive reports a flow must stay anomalous before
        // K-Means alone is allowed to block it. Higher = fewer false positives,
        // slower detection. 1 makes hybrid behave like plain kmeans.
        int confirmations = default(3);

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
