/**
    ---- OUTLINE ----
    1. SETUP
        1a. Initial Setup
        1b. User Input
        1c. Load and Filter Data
        1d. Check that there are enough sites to permit cAIC
        1e. Baseline fit on entire alignment
        1f. Set up some book keeping
        1g. Set general and baseline info to json
    2. MAIN ANALYSIS
        2a. Evaluation of single break points with brute force
            2a1. Loop over every valid single break point 
            2a2. Report the status of the sinlge break point analysis
            2a3. Evaluate if the analyis should continue to the multi break point stage
        2b. Evaluation of multiple break points with genetic algorithm
            GA.1: Setup global parameters
            GA.2: Loop over increasing number of break points
                GA.2.a Setup for n number of break points
                GA.2.b Loop over increasing generations for particular number of break points
                    GA.2.b.1 Produce the next generation of models with recombination. 
                    GA.2.b.2 Select the fittest models. 
                    GA.2.b.3 Evaluate convergence for this modelSet initialization
                    GA.2.b.4 Evaluate convergence for this number of break points
                GA.2.c Report status of n-break point analysis.
                GA.2.d Evaluate if the analysis should conclude or if the GA should run with breakpoints + 1
    3. Conclude Analysis (run the gard.concludeAnalysis function)

    FUNCTIONS
        - General GARD Functions
        - Genetic Algorithm Functions
        - Helper Functions
*/

/* 1. SETUP
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++*/

/* 1a. Initial Setup
------------------------------------------------------------------------------*/
RequireVersion ("2.4.0");

LoadFunctionLibrary ("libv3/all-terms.bf");
LoadFunctionLibrary ("libv3/convenience/regexp.bf");
LoadFunctionLibrary ("libv3/convenience/math.bf");
LoadFunctionLibrary ("libv3/IOFunctions.bf");
LoadFunctionLibrary ("libv3/UtilityFunctions.bf");
LoadFunctionLibrary ("libv3/tasks/trees.bf");
LoadFunctionLibrary ("libv3/tasks/alignments.bf");
LoadFunctionLibrary ("libv3/tasks/estimators.bf");
LoadFunctionLibrary ("SelectionAnalyses/modules/io_functions.ibf");
LoadFunctionLibrary ("libv3/tasks/mpi.bf");
LoadFunctionLibrary ("libv3/convenience/random.bf");


gard.analysisDescription = {terms.io.info : "GARD : Genetic Algorithms for Recombination Detection. Implements a heuristic
    approach to screening alignments of sequences for recombination, by using the CHC genetic algorithm to search for phylogenetic
    incongruence among different partitions of the data. The number of partitions is determined using a step-up procedure, while the
    placement of breakpoints is searched for with the GA. The best fitting model (based on c-AIC) is returned; and additional post-hoc
    tests run to distinguish topological incongruence from rate-variation.",
                           terms.io.version : "0.1",
                           terms.io.reference : "**Automated Phylogenetic Detection of Recombination Using a Genetic Algorithm**, _Mol Biol Evol 23(10), 1891–1901",
                           terms.io.authors : "Sergei L Kosakovsky Pond",
                           terms.io.contact : "spond@temple.edu",
                           terms.io.requirements : "A sequence alignment."
                          };

namespace terms.gard {
    nucleotide = "Nucleotide";
    protein    = "Protein";
    codon      = "Codon";
};

gard.json = {   terms.json.analysis: gard.analysisDescription,
                terms.json.input: {},
            };


/* 1b. User Input
------------------------------------------------------------------------------*/
io.DisplayAnalysisBanner (gard.analysisDescription);

KeywordArgument ("type",        "The type of data to perform screening on", "Nucleotide");
KeywordArgument ("code",        "Genetic code to use (for codon alignments)", "Universal", "Choose Genetic Code");
KeywordArgument ("alignment",   "Sequence alignment to screen for recombination");

/* TODO:
ChoiceList (rvChoice, "Rate variation options", 1, SKIP_NONE,
                      "None",                     "Homogeneous rates across sites (fastest)",
                      "General Discrete",         "General discrete distribution on N-bins",
                      "Beta-Gamma",             "Adaptively discretized gamma N-bins. Try is GDD doesn't converge well, or if you suspect a lot of rate classes and do not want to overparameterize the model");

if (rvChoice)
{
    rateClasses = 0;
    while (rateClasses < 2 || rateClasses > 32)
    {
        fprintf (stdout, "How many distribution bins [2-32]?:");
        fscanf  (stdin,  "Number", rateClasses);
        rateClasses = rateClasses $ 1;
    }
    fprintf (stdout, "\nUsing ", rateClasses, " distribution bins\n");
}
*/

gard.dataType = io.SelectAnOption  ({terms.gard.nucleotide : "A nucleotide (DNA/RNA) alignment",
                                      terms.gard.protein : "A protein alignment",
                                      terms.gard.codon : "An in-frame codon alignment"},
                                      "The type of data to perform screening on");
// Output key word argument is after data is loaded

/* 1c. Load and Filter Data
------------------------------------------------------------------------------*/
if (gard.dataType == terms.gard.nucleotide) {
    LoadFunctionLibrary ("libv3/models/DNA/GTR.bf");
    gard.model.generator = "models.DNA.GTR.ModelDescription";
    gard.alignment = alignments.ReadNucleotideDataSet ("gard.sequences", null);
    DataSetFilter gard.filter = CreateFilter (gard.sequences, 1);
} else {
    // TODO: implement these branches
    if (gard.dataType == terms.gard.protein) {
        gard.alignment = alignments.ReadProteinDataSet ("gard.sequences", null);
        DataSetFilter gard.filter = CreateFilter (gard.sequences, 1);
    } else {
        gard.alignment = alignments.LoadGeneticCodeAndAlignment ("gard.sequences", "gard.filter", null);
    }
}

// Where to save the json
gard.defaultJsonFilePath = (gard.alignment[terms.data.file] + '.GARD.json');
KeywordArgument ("output", "Write the resulting JSON to this file (default is to save to the same path as the alignment file + 'GARD.json')", gard.defaultJsonFilePath);
gard.jsonFileLocation = io.PromptUserForFilePath ("Save the resulting JSON file to");

gard.defaultFitFilePath = = (gard.alignment[terms.data.file] + '.best-gard');
KeywordArgument ("output-lf", "Write the best fitting HyPhy analysis snapshot to (default is to save to the same path as the alignment file + 'best-gard')", gard.defaultFitFilePath);
gard.lfFileLocation = io.PromptUserForFilePath ("Save the HyPhy analysis snapshot to");


// Define model to be used in each fit
gard.model = model.generic.DefineModel (gard.model.generator, "gard.overallModel", {"0" : "terms.global"}, "gard.filter", null);

gard.numSites               = gard.alignment[terms.data.sites];
gard.numSeqs                = gard.alignment[terms.data.sequences];

// Get a matrix of the variable sites {"0": site index, "1": site index ...}
gard.variableSiteMap = {};
utility.ForEach (alignments.Extract_site_patterns ("gard.filter"), "_pattern_", "
    if (_pattern_[terms.data.is_constant]==FALSE) {
        utility.ForEachPair (_pattern_[terms.data.sites], '_key_', '_value_',
        '
            gard.variableSiteMap + _value_;
        ');
    }
");
gard.variableSiteMap = Transpose (utility.DictToArray (gard.variableSiteMap)) % 0; // sort by 1st column
gard.variableSites = Rows (gard.variableSiteMap);
gard.inverseVariableSiteMap = unility.SwapKeysAndValues(gard.variableSiteMap);
gard.numberOfPotentialBreakPoints = gard.variableSites - 1;

io.ReportProgressMessage ("", ">Loaded a `gard.dataType` multiple sequence alignment with **`gard.numSeqs`** sequences, **`gard.numSites`** sites (`gard.variableSites` of which are variable) from \`" +
                                gard.alignment[utility.getGlobalValue("terms.data.file")] + "\`");

gard.baselineParameters     = (gard.model[terms.parameters])[terms.model.empirical] + // empirical parameters
                              utility.Array1D ((gard.model[terms.parameters])[terms.global]) + // global parameters
                              utility.Array1D ((gard.model[terms.parameters])[terms.local]) * (2*gard.numSeqs-5) * 2; // local parameters X number of branches x at least 2 partitions

gard.minExpectedSites     = (gard.baselineParameters + 2);
gard.minPartitionSize       = 2*gard.numSeqs-3;
/** gard.minPartitionSize:
    a simple heuristic that requires that there c-AIC makes sense for each individual
    partition i.e. there are at least 2 more sites than branch lengths
**/

io.ReportProgressMessage ("", ">Minimum size of a partition is set to be `gard.minPartitionSize` sites");

/* 1d. Check that there are enough sites to permit cAIC
------------------------------------------------------------------------------*/
io.CheckAssertion("gard.minExpectedSites <= gard.numSites", "The alignment is too short to permit c-AIC based model comparison. Need at least `gard.minExpectedSites` sites for `gard.numSeqs` sequences to fit a two-partiton model.");


/* 1e. Baseline fit on entire alignment
------------------------------------------------------------------------------*/
io.ReportProgressMessageMD('GARD', 'baseline-fit', 'Fitting the baseline (single-partition; no breakpoints) model');
gard.startTime = Time(1);
// Infer NJ tree, estimting rate parameters (branch-lengths, frequencies and substitution rate matrix)

gard.baseLikelihoodInfo = gard.fitPartitionedModel (null, gard.model, null, null, FALSE);
gard.initialValues = gard.baseLikelihoodInfo;
gard.globalParameterCount = utility.Array1D (estimators.fixSubsetOfEstimates(gard.initialValues, gard.initialValues[terms.global]));
// Set branch lenth = null in intialValues (need to have a null entry for each partition so just setting a bunch of them here)
maxExpectedBreakPoints = 200;
for(i=0; i<maxExpectedBreakPoints; i=i+1) {
    (gard.initialValues [terms.branch_length])[i] = null;
}

gard.baseline_cAIC = math.GetIC (gard.baseLikelihoodInfo[terms.fit.log_likelihood], gard.baseLikelihoodInfo[terms.parameters], gard.numSites);
io.ReportProgressMessageMD("GARD", "baseline-fit", "* " + selection.io.report_fit (gard.baseLikelihoodInfo, 0, gard.numSites));


/* 1f. Set up some book keeping
------------------------------------------------------------------------------*/
// Setup mpi variableSiteMap
gard.createLikelihoodFunctionForExport ("gard.exportedModel", gard.model);
gard.queue = mpi.CreateQueue (
                            {
                            "LikelihoodFunctions" : {{"gard.exportedModel"}},
                            "Headers" : {{"libv3/all-terms.bf"}},
                            "Variables" : {{"gard.globalParameterCount", "gard.numSites", "gard.variableSiteMap"}}
                            }
                        );

// Setup master list of evaluated models.
gard.masterList = {};
/** gard.masterList:
    "model string": "model fitness (cAIC score)"
    model string is in the format: "{\n{bp1} \n{bp2} ...\n}"
    model fitness is either infinity (if not evaluated) or the numeric cAIC score
**/

gard.masterList [{{}}] = gard.baseline_cAIC;
gard.bestOverall_cAIC_soFar = gard.baseline_cAIC;
gard.bestOverallModelSoFar = {{}};


/* 1g. Set general and baseline info to json
------------------------------------------------------------------------------*/
gard.json[terms.json.input] = { terms.json.file: gard.alignment[terms.data.file],
                                terms.json.sequences: gard.alignment[terms.data.sequences],
                                terms.json.sites: gard.alignment[terms.data.sites],
                                terms.json.partition_count: Rows(gard.alignment[terms.data.partitions])
                              };
gard.json['potentialBreakpoints'] = gard.numberOfPotentialBreakPoints;
gard.json['baselineScore'] = gard.baseline_cAIC;


/* 2. MAIN ANALYSIS
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++*/

/* 2a. Evaluation of single break points with brute force
------------------------------------------------------------------------------*/
io.ReportProgressMessageMD('GARD', 'single-breakpoint', 'Performing an exhaustive single breakpoint analysis');

namespace gard {

    // 2a1. Loop over every valid single break point 
    singleBreakPointBest_cAIC = ^"math.Infinity";
   
    for (breakPointIndex = 0; breakPointIndex <variableSites - 1; breakPointIndex += 1) {
        siteIndex = variableSiteMap [breakPointIndex];

        if (singleBreakPointBest_cAIC < baseline_cAIC) {
            io.ReportProgressBar ("GARD", "Breakpoint " +  Format (1+breakPointIndex, 10, 0) + " of " + (variableSites-1) + ". Best cAIC = " + Format (singleBreakPointBest_cAIC, 12, 4) + " [delta = " + Format (baseline_cAIC - singleBreakPointBest_cAIC, 12, 4) + "] with breakpoint at site " + Format (singleBreakPointBestLocation, 10, 0));
        } else {
            io.ReportProgressBar ("GARD", "Breakpoint " +  Format (1+breakPointIndex, 10, 0) + " of " + (variableSites-1) + ". Best cAIC = " + Format (baseline_cAIC, 12, 4) + " with no breakpoints");       
        }


        if (gard.validatePartititon ({{siteIndex}}, minPartitionSize, numSites) == FALSE)  {
            continue;
        }

        mpi.QueueJob (queue, "gard.obtainModel_cAIC", {"0" : {{siteIndex__}},
                                                     "1" : model,
                                                     "2" : baseLikelihoodInfo},
                                                     "gard.storeSingleBreakPointModelResults");
                                                    
    }

    mpi.QueueComplete (queue);
    io.ClearProgressBar();

    // 2a2. Report the status of the sinlge break point analysis
    io.ReportProgressMessageMD('GARD', 'single-breakpoint', 'Done with single breakpoint analysis.');
    io.ReportProgressMessageMD('GARD', 'single-breakpoint', ("   Best sinlge break point location: " + singleBreakPointBestLocation));
    io.ReportProgressMessageMD('GARD', 'single-breakpoint', ("   c-AIC  = " + singleBreakPointBest_cAIC));
}

// 2a3. Evaluate if the analyis should continue to the multi break point stage
if (gard.singleBreakPointBest_cAIC < gard.bestOverall_cAIC_soFar) {
    gard.bestOverall_cAIC_soFar = gard.singleBreakPointBest_cAIC;
    gard.bestOverallModelSoFar = {{gard.singleBreakPointBestLocation}};
    gard.improvements = {'0': {
                                "deltaAICc": gard.baseline_cAIC - gard.bestOverall_cAIC_soFar,
                                "breakpoints": gard.bestOverallModelSoFar
                              }
                        };
} else {
    gard.concludeAnalysis(gard.bestOverallModelSoFar);
    return 0;
}


/* 2b. Evaluation of multiple break points with genetic algorithm
------------------------------------------------------------------------------*/
io.ReportProgressMessageMD('GARD', 'multi-breakpoint', 'Performing multi breakpoint analysis using a genetic algorithm');

namespace gard {
    // GA.1: Setup global parameters
    populationSize = 20; // the GARD paper used: (numberOfMpiNodes*2 - 2) with 17 mpi nodes
    if(populationSize < mpi.NodeCount()) {
        populationSize = mpi.NodeCount();
    }
    mutationRate = 0.8; // the GARD paper said "15% of randomly selected bits were toggled"...
    rateOfMutationsTharAreSmallShifts = 0.4; // some mutations are a new random break point; some are small shifts of the break point to an adjacent location.
    maxFailedAttemptsToMakeNewModel = 5;
    cAIC_diversityThreshold = 0.001;
    cAIC_improvementThreshold = 0.1; // I think this was basically 0 in the gard paper
    maxGenerationsAllowedWithNoNewModelsAdded = 10; // TODO: Not in the GARD paper. use 10?
    maxGenerationsAllowedAtStagnent_cAIC = 50; // TODO: this is set to 100 in the GARD paper
    
    // GA.2: Loop over increasing number of break points
    addingBreakPointsImproves_cAIC = TRUE;
    numberOfBreakPointsBeingEvaluated = 1;
    while(addingBreakPointsImproves_cAIC) {
        // GA.2.a Setup for n number of break points
        numberOfBreakPointsBeingEvaluated+=1;
        generationsAtCurrentBest_cAIC = 0;
        generationsNoNewModelsAdded = 0;
        parentModels = gard.GA.initializeModels(numberOfBreakPointsBeingEvaluated, populationSize, numberOfPotentialBreakPoints, bestOverallModelSoFar);
        
        // GA.2.b Loop over increasing generations for particular number of break points
        terminationCondition = FALSE;
        generation = 0;
        while(terminationCondition == FALSE) {

            // GA.2.b.1 Produce the next generation of models with recombination. 
            childModels = gard.GA.recombineModels(parentModels, populationSize);
            
            // GA.2.b.2 Select the fittest models. 
            interGenerationalModels = parentModels;
            interGenerationalModels * childModels;
            gard.GA.evaluateModels(interGenerationalModels);
            selectedModels = gard.GA.selectModels(interGenerationalModels, populationSize);

            // GA.2.b.3 Evaluate convergence for this modelSet initialization 
            // If converged, produce a new parent modelSet (keeping the current fitest)
            if (gard.GA.modelSetsAreTheSame(selectedModels, parentModels)) {
                generationsNoNewModelsAdded += 1;
            } else {
                generationsNoNewModelsAdded = 0;
            }
            if ( (math.minNormalizedRange(selectedModels) < cAIC_diversityThreshold) || (generationsNoNewModelsAdded > maxGenerationsAllowedWithNoNewModelsAdded) ) {
                parentModels = gard.GA.generateNewGenerationOfModelsByMutatingModelSet(parentModels, numberOfPotentialBreakPoints, mutationRate, rateOfMutationsTharAreSmallShifts);
                if (Abs(parentModels) == 1) {
                    parentModels = gard.GA.initializeModels(numberOfBreakPointsBeingEvaluated, populationSize, numberOfPotentialBreakPoints);
                }
                differenceThreshold = numberOfBreakPointsBeingEvaluated / 4;
            } else {
                parentModels = selectedModels;
            }

            // GA.2.b.4 Evaluate convergence for this number of break points
            // If converged, move on to n+1 break points or end analysis
            currentBest_individual = Min(interGenerationalModels,1);
            currentBest_cAIC  = currentBest_individual["value"];
            currentBest_model = Eval(currentBest_individual["key"]);
            
            if (previousBest_cAIC - currentBest_cAIC < cAIC_improvementThreshold) {
                generationsAtCurrentBest_cAIC += 1;
                if (generationsAtCurrentBest_cAIC >= maxGenerationsAllowedAtStagnent_cAIC) {
                    terminationCondition = TRUE;
                }
            } else {
                generationsAtCurrentBest_cAIC = 0;
            }
            previousBest_cAIC = currentBest_cAIC;

            generation += 1;
            
            if (bestOverall_cAIC_soFar-currentBest_cAIC > 0) {
                 io.ReportProgressBar ("GARD", Format (numberOfBreakPointsBeingEvaluated,3,0) + ' breakpoints [ generation ' +  Format (generation, 6, 0) + ", total models " + Format (Abs (masterList), 8, 0) + "]" 
                                        + ". Min (c-AIC) = " + Format (currentBest_cAIC, 12,4) + " [ delta = " + Format (bestOverall_cAIC_soFar-currentBest_cAIC, 8, 2) + "], breakpoints at " + Join (", ", currentBest_model));
           
            } else {            
                io.ReportProgressBar ("GARD", Format (numberOfBreakPointsBeingEvaluated,3,0) + ' breakpoints [ generation ' +  Format (generation, 6, 0) + ", total models " + Format (Abs (masterList), 8, 0) + "]" 
                                        + ". Min (c-AIC) = " + Format (currentBest_cAIC, 12,4) + " [no improvement], breakpoints at " + Join (", ", bestOverallModelSoFar));
            }
        }

        io.ClearProgressBar();
        // GA.2.c Report status of n-break point analysis.
        statusString = ("Done with " + numberOfBreakPointsBeingEvaluated + " breakpoint analysis.\n" + gard.GA.getMultiBreakPointStatusString(selectedModels, variableSiteMap));
        io.ReportProgressMessageMD('GARD', 'multi-breakpoint', statusString);

        // GA.2.d Evaluate if the analysis should conclude or if the GA should run with breakpoints + 1
        if (previousBest_cAIC < bestOverall_cAIC_soFar) {
            bestModel = gard.Helper.convertMatrixStringToMatrix(utility.Keys(selectedModels)[Min(utility.Values(selectedModels),1)[1]]);
            improvements[numberOfBreakPointsBeingEvaluated-1] = {
                                                                    "deltaAICc": bestOverall_cAIC_soFar - previousBest_cAIC,
                                                                    "breakpoints": bestModel
                                                                };
            bestOverall_cAIC_soFar = previousBest_cAIC;
            bestModel = gard.Helper.convertMatrixStringToMatrix(utility.Keys(selectedModels)[Min(utility.Values(selectedModels),1)[1]]);
            bestOverallModelSoFar = bestModel;
        } else {
            addingBreakPointsImproves_cAIC = FALSE;
            gard.concludeAnalysis(bestOverallModelSoFar);
        }
    }

}


//--------------------------------------------------------------------------------------------------------------------

/* FUNCTIONS
++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++*/

// ---- General GARD Functions ----

/**
 * @name gard.fitPartitionedModel
 * Given a list of partitions, specified as increasing breakpoint locations,
   fit the specified model to said partitions, using neighbor joining trees on each partition
   return the likelihood information object

 * @param {Matrix} breakPoints : sorted, 0-based breakpoints, e.g.
    {{100,200}} -> 3 partitions : 0-100, 101-200, 201-end
 * @param {Dict} model : an instantiated model to be used for all partitions
 * @param {Dict/null} initialValues : if provided, use as initial values
 * @param {String/null} saveToFile: if provided, save the resulting nexus file to this file location
 * @param {Bolean} constrainToOneTopology: if provided, allow the branch lengths to vary across partitions but constrain the topology to the overall tree

 * @returns a {likelihood information object}

 */

lfunction gard.fitPartitionedModel (breakPoints, model, initialValues, saveToFile, constrainToOneTopology) {

    currentIndex = 0;
    currentStart = 0;
    breakPointsCount = utility.Array1D (breakPoints);
    partCount = breakPointsCount + 1;
    lfComponents = {2 * (partCount), 1};
    trees = {};
    
    if (constrainToOneTopology == TRUE) {
        overall_tree = trees.ExtractTreeInfo (tree.infer.NJ ( "gard.filter", null));
    }

    for (p = 0; p < partCount; p += 1) {
        lastPartition = p >= breakPointsCount;
        if (!lastPartition) {
            currentEnd = breakPoints[p];
        } else {
            currentEnd = ^"gard.filter.sites" - 1;
        }
        lfComponents [2*p] = "gard.filter.part_" + p;
        lfComponents [2*p+1] = "gard.tree.part_" + p;
        DataSetFilter ^(lfComponents[2*p]) = CreateFilter (^"gard.filter", 1, "" + currentStart + "-" + currentEnd);
        if (constrainToOneTopology == TRUE) {
            trees[p] = overall_tree;
        } else {
            trees[p] = trees.ExtractTreeInfo (tree.infer.NJ ( lfComponents[2*p], null));
        }
        model.ApplyModelToTree(lfComponents[2 * p + 1], trees[p], {
            "default": model
        }, None);
        // Increment the current starting point
        if (!lastPartition) {
            currentStart = breakPoints[p];
        }
    }

    lf_id = &likelihoodFunction;
    utility.ExecuteInGlobalNamespace ("LikelihoodFunction `lf_id` = (`&lfComponents`)");

    modelObjects = {
        "gard.overallModel" : model
    };

    df = 0;
    if (Type(initialValues) == "AssociativeList") {
        utility.ToggleEnvVariable("USE_LAST_RESULTS", 1);
        df = estimators.ApplyExistingEstimates(&likelihoodFunction, modelObjects, initialValues, None);
    }

    res = estimators.FitExistingLF (&likelihoodFunction, modelObjects);
    
    if (Type (saveToFile) == "String") {
        io.SpoolLF (&likelihoodFunction, saveToFile, "");
    }

    DeleteObject (likelihoodFunction, :shallow);

    res[^"terms.parameters"] += df + (model[^"terms.parameters"])[^"terms.model.empirical"];
    return res;

}

/**
 * @name gard.obtainModel_cAIC
 * Wrap a call to gard.fitPartitionedModel to compute c-AIC

   @returns c-AIC

 */
lfunction gard.obtainModel_cAIC (breakPoints, model, initialValues) {
    fit = gard.fitPartitionedModel (breakPoints, model, initialValues, null, FALSE);
    c_AIC = math.GetIC (fit[^"terms.fit.log_likelihood"], fit[^"terms.parameters"] + ^"gard.globalParameterCount", ^"gard.numSites");
    //console.log ("\n" + breakPoints + "=>" + c_AIC);
    return c_AIC;
}

function gard.storeSingleBreakPointModelResults (node, result, arguments) {
    result = Eval (result);
    gard.masterList[arguments[0]] = result;
    if (result < gard.singleBreakPointBest_cAIC) {
        gard.singleBreakPointBest_cAIC = result;
        gard.singleBreakPointBestLocation = Eval(arguments[0])[0];
    }
}

lfunction gard.createLikelihoodFunctionForExport (id,  model) {
    overall_tree = trees.ExtractTreeInfo (tree.infer.NJ ( "gard.filter", null));
    model.ApplyModelToTree("gard._ignore_tree",overall_tree, {
        "default": model
    }, None);

    utility.ExecuteInGlobalNamespace ("LikelihoodFunction `id` = (gard.filter, gard._ignore_tree)");

}

/**
    definition is assumed to contain a SORTED list of 0-based
    breakpoint locations

    If any of the individual partitions is < minSize, the function
    returns FALSE, otherwise it returns TRUE
*/
lfunction gard.validatePartititon (definition, minSize, totalSites) {
    lastBP = 0;
    bpCount = utility.Array1D (definition);
    for (i = 0; i < bpCount; i+=1) {
        if (definition[i] - lastBP + 1 < minSize) {
            return FALSE;
        }
        lastBP = definition[i];
    }
    if (totalSites - lastBP < minSize) {
        return FALSE;
    }
    return TRUE;
}

/**
   @name gard.modelIsNotInMasterList
   @params {Matrix || Dictonary} breakPoints
   @returns {Bolean}

 */
lfunction gard.modelIsNotInMasterList(masterList, breakPoints) {
    if (Type(breakPoints) == "Matrix") {
        breakPointString = '';
        Eval("breakPoints = breakPointString + breakPoints"); 
    }
    if (utility.KeyExists(masterList, breakPoints)) {
        return FALSE;
    } else {
        return TRUE;
    }
}

function gard.concludeAnalysis(bestOverallModel) {
    (gard.json)['timeElapsed'] = Time(1) - gard.startTime;
    (gard.json)['siteBreakPointSupport'] = gard.getSiteBreakPointSupport(gard.masterList, gard.bestOverall_cAIC_soFar);
    (gard.json)['singleTreeAICc'] = gard.getSingleTree_cAIC(bestOverallModel);
    (gard.json)['totalModelCount'] = Abs(gard.masterList);
    
    gard.setBestModelTreeInfoToJson(bestOverallModel);

    if(Abs((gard.json)['trees']) > 1) {
        (gard.json)['improvements'] = gard.improvements;
    }
    
    io.SpoolJSON (gard.json, gard.jsonFileLocation);

    console.log('The cAIC score was not improved by adding additional break points; the anlysis is complete.');
}

function gard.setBestModelTreeInfoToJson(bestModel) {
    gard.bestModelNumberBreakPoints = Columns(bestModel);

    if(gard.bestModelNumberBreakPoints == 0) {
        gard.json['breakpointData'] = { 'tree': (gard.baseLikelihoodInfo["Trees"])[0],
                                        'bps': {{1,gard.numSites}}
                                      };
        gard.json['trees'] = {"newickString": (gard.baseLikelihoodInfo["Trees"])[0] };
    } 

    if (gard.bestModelNumberBreakPoints > 0) {
        // bestModel is a 1xn matrix with the the site index of the break points
        gard.bestModelBreakPoints = bestModel;
        gard.bestModelMultiBreakpointLikelihoodInfo = gard.fitPartitionedModel(gard.bestModelBreakPoints, gard.model, gard.baseLikelihoodInfo, gard.lfFileLocation, FALSE);
        
        gard.bestModelTrees = {};
        gard.bestModelBps = {};
        gard.bestModelBreakpointData = {};
        for(i=0; i<gard.bestModelNumberBreakPoints + 1; i += 1) {
            gard.bestModelTrees[i] = {"newickString": (gard.bestModelMultiBreakpointLikelihoodInfo['Trees'])[i]};
             gard.bestModelBps[i] = {1,2};
            if(i == 0){
                (gard.bestModelBps[i])[0] = 1;
                (gard.bestModelBps[i])[1] = gard.bestModelBreakPoints[i];
             } else {
                if(i < gard.bestModelNumberBreakPoints) {
                    (gard.bestModelBps[i])[0] = gard.bestModelBreakPoints[i-1]+1;
                    (gard.bestModelBps[i])[1] = gard.bestModelBreakPoints[i];
                } else {
                    (gard.bestModelBps[i])[0] = gard.bestModelBreakPoints[i-1]+1;
                    (gard.bestModelBps[i])[1] = gard.numSites;
                }
            }
            gard.bestModelBreakpointData[i] = ({
                                                "tree": (gard.bestModelMultiBreakpointLikelihoodInfo['Trees'])[i],
                                                "bps": gard.bestModelBps[i]
                                             });
        }
        gard.json['trees'] = gard.bestModelTrees;
        gard.json['breakpointData'] = gard.bestModelBreakpointData;
    }
    return ;
}

lfunction gard.getSingleTree_cAIC(bestOverallModel) {
    gard.singleTreeLikelihoodInfo = gard.fitPartitionedModel (bestOverallModel, ^"gard.model", ^"gard.initialValues", null, TRUE);
    gard.singleTree_cAIC = math.GetIC (gard.singleTreeLikelihoodInfo[^"terms.fit.log_likelihood"], gard.singleTreeLikelihoodInfo[^"terms.parameters"] + ^"gard.globalParameterCount", ^"gard.numSites");
    return gard.singleTree_cAIC;
}

lfunction gard.getSiteBreakPointSupport(modelMasterList, best_cAIC_score) {
    gard.masterListModels = utility.Keys(modelMasterList);
    gard.masterList_cAIC_values = utility.Values(modelMasterList);
    gard.numberOfModels = Columns(gard.masterList_cAIC_values);

    gard.siteAkaikeWeights = {};
    for(modelIndex=0; modelIndex<gard.numberOfModels; modelIndex=modelIndex+1) {
        gard.cAIC_delta = best_cAIC_score - gard.masterList_cAIC_values[modelIndex];
        gard.akaikeWeight = Exp(gard.cAIC_delta * 0.5);

        if( Abs(gard.masterListModels[modelIndex]) > 3) {
            gard.breakPointMatrix = gard.Helper.convertMatrixStringToMatrix(gard.masterListModels[modelIndex]);
        } else {
            gard.breakPointMatrix = 0;
        }
        gard.numberOfBreakPoints = Columns(gard.breakPointMatrix);

        for(breakPointIndex=0; breakPointIndex<gard.numberOfBreakPoints; breakPointIndex=breakPointIndex+1) {
            gard.siteAkaikeWeights[gard.breakPointMatrix[breakPointIndex]] += gard.akaikeWeight;
        }
    }
    
    gard.akaikeWeightScallingFactor = 1 / (Max(gard.siteAkaikeWeights)['value']);
    gard.normalizedSiteAkaikeWeights = {};

    gard.potentialBreakPointList = utility.Keys(gard.siteAkaikeWeights);
    gard.numberOfPotentialBreakPoints = Abs(gard.siteAkaikeWeights);
    for(breakPointIndex=0; breakPointIndex<gard.numberOfPotentialBreakPoints; breakPointIndex+=1) {
        siteIndex = gard.potentialBreakPointList[breakPointIndex];
        gard.normalizedSiteAkaikeWeights[siteIndex] = gard.siteAkaikeWeights[siteIndex]*gard.akaikeWeightScallingFactor;
    }
    
    return gard.normalizedSiteAkaikeWeights;
}


// ---- Genetic Algorithm (GA) Functions ----

/**
 * @name gard.GA.initializeModels
 * @param {Number} numberOfBreakPoints
 * @param {Number} populationSize
 * @param {Number} numberOfPotentialBreakPoints
 * @returns a {Dictonary} initializedModels
 */
lfunction gard.GA.initializeModels (numberOfBreakPoints, populationSize, numberOfPotentialBreakPoints, seed) {

    initializedModels = {};
    modelNumber       = 0;
    
    if (null != seed) {
       for (; modelNumber < populationSize$2; modelNumber += 1) {
         do {
            breakPoints = {numberOfBreakPoints,1};
            for (breakpoint.index = 0; breakpoint.index < numberOfBreakPoints - 1; breakpoint.index += 1) {
                breakPoints[breakpoint.index] = seed[breakpoint.index];
            }
            breakPoints [breakpoint.index] = (^"gard.variableSiteMap") [Random(0, numberOfPotentialBreakPoints)$1];
            breakPoints = Transpose(breakPoints % 0);
            
        } while (gard.validatePartititon (breakPoints, ^"gard.minPartitionSize", ^"gard.numSites") == FALSE);
      
        initializedModels[breakPoints] = ^"math.Infinity";
       }
    } 
    for (; modelNumber < populationSize; modelNumber += 1) {
        // TODO : make sure that feasible solutions exist, i.e. that gard.validatePartititon doesn't just keep rejecting all models
        do {
            breakPoints = Transpose(utility.Map (({numberOfBreakPoints,1} ["Random(0, numberOfPotentialBreakPoints)$1"]) % 0, "_pattern_", "gard.variableSiteMap[_pattern_]"));
        } while (gard.validatePartititon (breakPoints, ^"gard.minPartitionSize", ^"gard.numSites") == FALSE);

        initializedModels[breakPoints] = ^"math.Infinity";
    }
    return initializedModels;
}

/**
 * @name gard.GA.recombineModels
 Given a set of models create a new generation of models by iteratively recombining two random parent models.
 The child model will have a random subset of the breakpoints from the parents

 * @param {Matrix} parentModels
 * @param {Number} populationSize
 * @returns a {Dictonary} childModels
 */
lfunction gard.GA.recombineModels (parentModels, populationSize) {
    parentModelIds = utility.Keys(parentModels);
    numberOfParentModels = Columns(parentModelIds);
    firstModel = gard.Helper.convertMatrixStringToMatrix(parentModelIds[0]);
    numberOfBreakPoints = Columns(firstModel);

    childModels = {};
    for(modelIndex=0; modelIndex<populationSize; modelIndex+=1) {

        modelIsValid = FALSE;
        failedAttempts = 0;
        while(modelIsValid == FALSE && failedAttempts < ^"gard.maxFailedAttemptsToMakeNewModel") {
            parentModel1 = gard.Helper.convertMatrixStringToMatrix(parentModelIds[Random(0, numberOfParentModels-.0001)$1]);
            parentModel2 = gard.Helper.convertMatrixStringToMatrix(parentModelIds[Random(0, numberOfParentModels-.0001)$1]);

            while(parentModel1 == parentModel2) {
                parentModel2 = gard.Helper.convertMatrixStringToMatrix(parentModelIds[Random(0, numberOfParentModels-.0001)$1]);
            }

            breakPoints = {1, numberOfBreakPoints};
            for (breakPointNumber=0; breakPointNumber < numberOfBreakPoints; breakPointNumber=breakPointNumber+1) {
                if (random.TRUE_or_FALSE()) {
                    parentModel = parentModel1;
                } else {
                    parentModel = parentModel2;
                }
                breakPoint = parentModel[Random(0, numberOfBreakPoints-.0001)$1];
                
                breakPoints[breakPointNumber] = breakPoint;
            }
            breakPoints = gard.Helper.sortedMatrix(breakPoints);
            if ( (gard.modelIsNotInMasterList(^"gard.masterList", breakPoints)) && (gard.validatePartititon(breakPoints, ^"gard.minPartitionSize", ^"gard.numSites")) ) {
                modelIsValid = TRUE;
            } else {
                failedAttempts+=1;
            }

        }
        if (modelIsValid) {
            childModels[breakPoints] = ^"math.Infinity";
        }

    }

    return childModels;
}

/**
 * @name gard.GA.evaluateModels
 * @param {Dictonary} models (some models may have cAIC scores already)
 * @returns nothing... the gard.GA.storeMultiBreakPointModelResults function gets called which updates the intergenerationalModels object
 */
function gard.GA.evaluateModels (models) {
    modelIds = utility.Keys(models);
    numberOfModels = Columns(modelIds);

    for(modelIndex=0; modelIndex<numberOfModels; modelIndex += 1) {
        modelId = modelIds[modelIndex];
        cAIC = models[modelId];

        if (cAIC == math.Infinity) {
            breakPoints = gard.Helper.convertMatrixStringToMatrix(modelId);
            mpi.QueueJob (gard.queue, "gard.obtainModel_cAIC", {"0" : breakPoints__,
                                                     "1" : gard.model,
                                                     "2" : gard.baseLikelihoodInfo},
                                                     "gard.GA.storeMultiBreakPointModelResults");
        }
        mpi.QueueComplete (gard.queue);

    }

}

/**
 * @name gard.GA.storeMultiBreakPointModelResults
 // The call back function passed to mpi.QueueJob in the gard.GA.evaluateModels function
 * @param {Dictonary} evaluatedModels: the set of models at the end of the analysis
 * @returns a {String} the markdown string to log to console
 */
function gard.GA.storeMultiBreakPointModelResults(node, result, arguments) {
    result = Eval (result);
    gard.masterList[arguments[0]] = result;
    gard.interGenerationalModels[arguments[0]] = result;
}

/**
 * @name gard.GA.selectModels
 * @param {Dictionary} evaluatedModels
 * @param {Number} numberOfModelsToKeep
 * @returns a {Matrix} selectedModels
 */
lfunction gard.GA.selectModels (evaluatedModels, numberOfModelsToKeep) {
    modelIds = utility.Keys(evaluatedModels);
    cAIC_scores = utility.Values(evaluatedModels);


    selectedModels = {};
    for(i=0; i<numberOfModelsToKeep; i+=1) {
        lowest_cAIC_index = Min(cAIC_scores,1)[1];
        selectedModelId = modelIds[lowest_cAIC_index];
        selectedModels[selectedModelId] = cAIC_scores[lowest_cAIC_index];

        cAIC_scores[lowest_cAIC_index] = ^"math.Infinity";
    }
    return selectedModels;
}

/**
 * @name gard.GA.modelSetsAreTheSame
 * @param {Dictionary} modelSet1
 * @param {Dictionary} modelSet2
 * @returns a {Bolean} 
 */
lfunction gard.GA.modelSetsAreTheSame(modelSet1, modelSet2) {
    if(Abs(modelSet1) != Abs(modelSet2)){
        return FALSE;
    }

    IdSet1 = utility.Keys(modelSet1);
    for(i=0; i<Abs(modelSet1); i=i+1) {
        if(utility.KeyExists(modelSet2, IdSet1[i]) == FALSE) {
            return FALSE;
        }
    }

    return TRUE;
}

/**
 * @name gard.GA.generateNewGenerationOfModelsByMutatingModelSet
 Keeps the current best performing model
 Generates new models for the rest of the population by randomly mutating some of the parent models break points
 // TODO: decide if we want some logic in here to more meaningfully mutate.
 * @param {Dictonary} parentModels
 * @param {Number} numberOfPotentialBreakPoints
 * @param {Number} mutationRate
 * @param {Number} rateOfMutationsThatAreSmallShifts
 * @returns a {Dictonary} the new generation of models
 */
lfunction gard.GA.generateNewGenerationOfModelsByMutatingModelSet(parentModels, numberOfPotentialBreakPoints, mutationRate, rateOfMutationsThatAreSmallShifts) {
    modelIds = utility.Keys(parentModels);
    populationSize = Columns(modelIds);
    firstModel = gard.Helper.convertMatrixStringToMatrix(modelIds[0]);
    numberOfBreakPoints = Columns(firstModel);

    // Generate a new set of models
    nextGenOfModels = {};
    for(i=0; i<populationSize-1; i += 1) {
        
        modelIsValid = FALSE;
        failedAttempts = 0;
        while(modelIsValid == FALSE && failedAttempts < ^"gard.maxFailedAttemptsToMakeNewModel") {
            parentModel = gard.Helper.convertMatrixStringToMatrix(modelIds[i]);
            breakPoints = {1,numberOfBreakPoints};
            for(breakPointIndex=0; breakPointIndex<numberOfBreakPoints; breakPointIndex=breakPointIndex+1) {

                if(Random(0,1) < mutationRate) { // keep the break point the same
                    breakPoints[breakPointIndex] = parentModel[breakPointIndex];
                } else {

                    if(Random(0,1) < rateOfMutationsThatAreSmallShifts) { // move the break point by a random small amount
                        distanceOfStep = random.poisson(2);
                        if (random.TRUE_or_FALSE()) { // randomly decide if the break point moves right or left
                            distanceOfStep = - distanceOfStep;
                        }
                        variableSiteMapIndexOfParentBreakPoint = utility.Find(^"gard.variableSiteMap", parentModel[breakPointIndex]);
                        newBreakPoint = (^"gard.variableSiteMap")[variableSiteMapIndexOfParentBreakPoint + distanceOfStep];
                        breakPoints[breakPointIndex] = newBreakPoint;
                    } else { // select a completely new random break point
                        breakPoints[breakPointIndex] = (^"gard.variableSiteMap")[Random(0,numberOfPotentialBreakPoints)$1];
                    }

                }
            }

            if ((gard.modelIsNotInMasterList(^"gard.masterList", breakPoints)) && (gard.validatePartititon(breakPoints, ^"gard.minPartitionSize", ^"gard.numSites")) ) {
                modelIsValid = TRUE;
            } else {
                failedAttempts+=1;
            }

        }

        if (modelIsValid) {
            nextGenOfModels[breakPoints] = ^"math.Infinity";
        }

    }

    // Add the most fit model from the previous set
    cAIC_scores = utility.Values(parentModels);
    lowest_cAIC_index = Min(cAIC_scores,1)[1];
    selectedModelId = modelIds[lowest_cAIC_index];
    nextGenOfModels[selectedModelId] = cAIC_scores[lowest_cAIC_index];

    return nextGenOfModels;
}

/**
 * @name gard.GA.getMultiBreakPointStatusString
 get the string to print out after the GA has finished n-breakpoint analysis
 * @param {Dictonary} evaluatedModels: the set of models at the end of the analysis
 * @returns a {String} the markdown string to log to console
 */
lfunction gard.GA.getMultiBreakPointStatusString(evaluatedModels, variableSiteMap) {
    best_cAIC_index = Min(utility.Values(evaluatedModels),1)[1];
    bestModel = gard.Helper.convertMatrixStringToMatrix(utility.Keys(evaluatedModels)[best_cAIC_index]);
    best_cAIC = Min(utility.Values(evaluatedModels),1)[0];
    bestBreakPointsString = gard.GA.convertModelMatrixToCommaSeperatedString(bestModel);
    statusString = "    Best break point locations: " + bestBreakPointsString + "\n" +
                   "    c-AIC = " + best_cAIC;
    
    return statusString;
}

lfunction gard.GA.convertModelMatrixToCommaSeperatedString(matrix){
    return Join (", ", matrix);
}


// ---- Helper Functions ----
// TODO: replace these helper functions with a more HBL way of dealing with matrices

lfunction gard.Helper.convertMatrixStringToMatrix(matrixString){
    return Eval(matrixString);
}

//sort numeric 1xn matrix into assending order.
lfunction gard.Helper.sortedMatrix(matrix) {
    sortedMatrix = {1,Columns(matrix)};

    for (i=0; i<Columns(matrix); i+=1) {
        minElementLeft=Min(matrix, 1);
        sortedMatrix[i] = minElementLeft[0];
        matrix[minElementLeft[1]] = ^"math.Infinity";
    }

    return sortedMatrix;
}
