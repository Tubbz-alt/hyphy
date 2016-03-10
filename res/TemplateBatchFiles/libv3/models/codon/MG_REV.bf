LoadFunctionLibrary ("../codon.bf");
LoadFunctionLibrary ("../DNA.bf");
LoadFunctionLibrary ("../parameters.bf");
LoadFunctionLibrary ("../frequencies.bf");
LoadFunctionLibrary ("../../UtilityFunctions.bf");

lfunction models.codon.MG_REV.modelDescription (type, code) {

    codons = models.codon.map_code (code);
    
    return {"alphabet" : codons["sense"],
            "bases" : ^"models.DNA.alphabet",
            "stop" : codons["stop"],
            "type" : type,
            "translation-table" : codons["translation-table"],
    		"description" : "The Muse-Gaut 94 codon-substitution model coupled with the general time reversible (GTR) model of nucleotide substitution",
    		"canonical"   : 0, // is NOT of the r_ij \times \pi_j form
    		"reversible"  : 1,
    		^"terms.efv_estimate_name": ^"terms.freqs.CF3x4",
    		"parameters" : 	{
    				"global" : {},
    				"local" : {}
    			},
    		"get-branch-length" : "",
    		"set-branch-length" : "models.codon.MG_REV.set_branch_length",
    		"constrain-branch-length" : "models.generic.constrain_branch_length",
    		"frequency-estimator" : "frequencies.empirical.corrected.CF3x4",
    		"q_ij" : "models.codon.MG_REV.generateRate",
    		"time" : "models.DNA.generic.time",
    		"defineQ" : "models.codon.MG_REV.defineQ",
    		"post-definition" : "models.generic.post.definition"
    		};
}


function models.codon.MG_REV.generateRate (fromChar, toChar, namespace, model_type, _tt) {

	models.codon.MG_REV.generateRate.p = {};
 	models.codon.MG_REV.generateRate.diff = models.codon.diff (fromChar, toChar);


	if (None != models.codon.MG_REV.generateRate.diff) {
        models.codon.MG_REV.generateRate.p [model_type]   = {};
        models.codon.MG_REV.generateRate.p [terms.global] = {};

        if (models.codon.MG_REV.generateRate.diff["from"] > models.codon.MG_REV.generateRate.diff["to"]) {
            models.codon.MG_REV.nuc_rate = "theta_" + models.codon.MG_REV.generateRate.diff["to"] + models.codon.MG_REV.generateRate.diff["from"];
        } else {
            models.codon.MG_REV.nuc_rate = "theta_" + models.codon.MG_REV.generateRate.diff["from"] + models.codon.MG_REV.generateRate.diff["to"];
        }

        models.codon.MG_REV.nuc_rate = parameters.applyNameSpace (models.codon.MG_REV.nuc_rate, namespace);
        (models.codon.MG_REV.generateRate.p [terms.global])[terms.nucleotideRate (models.codon.MG_REV.generateRate.diff["from"], models.codon.MG_REV.generateRate.diff["to"])]
                = models.codon.MG_REV.nuc_rate;

        if (_tt [fromChar] != _tt[toChar]) {
            if (model_type == terms.global) {
               models.codon.MG_REV.aa_rate  = parameters.applyNameSpace ("omega", namespace);
               (models.codon.MG_REV.generateRate.p [model_type]) [terms.omega_ratio] = models.codon.MG_REV.aa_rate;
            } else {
               models.codon.MG_REV.aa_rate = "beta";
               (models.codon.MG_REV.generateRate.p [model_type]) [terms.nonsynonymous_rate] = models.codon.MG_REV.aa_rate;
            }
            models.codon.MG_REV.generateRate.p [terms.rate_entry] = models.codon.MG_REV.nuc_rate + "*" + models.codon.MG_REV.aa_rate;
       } else {
            if (model_type == terms.local) {
                (models.codon.MG_REV.generateRate.p [model_type]) [terms.synonymous_rate] = "alpha";
                models.codon.MG_REV.generateRate.p [terms.rate_entry] = models.codon.MG_REV.nuc_rate + "*alpha";
            } else {
                models.codon.MG_REV.generateRate.p [terms.rate_entry] = models.codon.MG_REV.nuc_rate;
            }
       }
 	}

	return models.codon.MG_REV.generateRate.p;
}

function models.codon.MG_REV.defineQ (mg_rev, namespace) {
	models.codon.generic.defineQMatrix (mg_rev, namespace);
	parameters.setConstraint (((mg_rev["parameters"])[terms.global])[terms.nucleotideRate ("A","G")], "1", "");
	return mg_rev;
}

function models.codon.MG_REV.set_branch_length (model, value, parameter) {
    if (model["type"] == terms.global) {
        return models.generic.set_branch_length (model, value, parameter);
    }


    models.codon.MG_REV.set_branch_length.beta  = model.generic.get_local_parameter (model, terms.nonsynonymous_rate);
    models.codon.MG_REV.set_branch_length.alpha = model.generic.get_local_parameter (model, terms.synonymous_rate);

    models.codon.MG_REV.set_branch_length.alpha.p = parameter + "." + models.codon.MG_REV.set_branch_length.alpha;
    models.codon.MG_REV.set_branch_length.beta.p  = parameter + "." + models.codon.MG_REV.set_branch_length.beta;

    if (Type (value) == "AssociativeList") {
        if (value [terms.branch_length_scaler] == terms.branch_length_constrain) {
            if (parameters.isIndependent (models.codon.MG_REV.set_branch_length.alpha.p)) {
                  if (Abs (model [terms.synonymous_rate]) == 0) {
                     bl_string = model ["branch-length-string"];

                     models.codon.MG_REV.set_branch_length.sub = {};
                     models.codon.MG_REV.set_branch_length.sub [models.codon.MG_REV.set_branch_length.alpha] = 1;
                     models.codon.MG_REV.set_branch_length.sub [models.codon.MG_REV.set_branch_length.beta]  = 0;
                     model [terms.synonymous_rate]   = Simplify (bl_string, models.codon.MG_REV.set_branch_length.sub);

                     models.codon.MG_REV.set_branch_length.sub [models.codon.MG_REV.set_branch_length.alpha] = 0;
                     models.codon.MG_REV.set_branch_length.sub [models.codon.MG_REV.set_branch_length.beta]  = 1;
                     model [terms.nonsynonymous_rate] = Simplify (bl_string, models.codon.MG_REV.set_branch_length.sub);
                  }

                  //fprintf (stdout, models.codon.MG_REV.set_branch_length.alpha.p, "\n");

                  parameters.setConstraint (models.codon.MG_REV.set_branch_length.beta.p, "(" + 3*value[terms.branch_length] + " - " + models.codon.MG_REV.set_branch_length.alpha.p + "*(" +  model [terms.synonymous_rate] + "))/(" +  model [terms.nonsynonymous_rate] + ")", "");
                  return 1;
    
                } else {
                    assert (0, "TBA in models.codon.MG_REV.set_branch_length");
                }
        } else {
            
            models.codon.MG_REV.set_branch_length.lp = 0;
            if (parameters.isIndependent (models.codon.MG_REV.set_branch_length.alpha.p)) {
                Eval (models.codon.MG_REV.set_branch_length.alpha.p + ":=(" + value[terms.branch_length_scaler] + ")*" + value[terms.branch_length]);
                models.codon.MG_REV.set_branch_length.lp += 1;
            }
            if (parameters.isIndependent (models.codon.MG_REV.set_branch_length.beta.p)) {
                Eval (models.codon.MG_REV.set_branch_length.beta.p + ":=(" + value[terms.branch_length_scaler] + ")*" + value[terms.branch_length]);
                models.codon.MG_REV.set_branch_length.lp += 1;
            }
            return models.codon.MG_REV.set_branch_length.lp;
        }
    } else {
        if (parameters.isIndependent (models.codon.MG_REV.set_branch_length.alpha.p)) {
            if (parameters.isIndependent (models.codon.MG_REV.set_branch_length.beta.p)) {
                models.codon.MG_REV.set_branch_length.lp = parameters.normalize_ratio (Eval (models.codon.MG_REV.set_branch_length.beta), Eval (models.codon.MG_REV.set_branch_length.alpha));
                parameters.setConstraint (models.codon.MG_REV.set_branch_length.beta, models.codon.MG_REV.set_branch_length.alpha + "*" + models.codon.MG_REV.set_branch_length.lp, "");
                ExecuteCommands ("FindRoot (models.codon.MG_REV.set_branch_length.lp,(" + model ["branch-length-string"] + ")-" + value + "," + models.codon.MG_REV.set_branch_length.alpha + ",0,10000)");
                parameters.removeConstraint (models.codon.MG_REV.set_branch_length.beta);
                Eval ("`models.codon.MG_REV.set_branch_length.alpha.p` =" + models.codon.MG_REV.set_branch_length.lp);
                Eval ("`models.codon.MG_REV.set_branch_length.beta.p` =" + Eval (models.codon.MG_REV.set_branch_length.beta.p));
            } else {
                ExecuteCommands ("FindRoot (models.codon.MG_REV.set_branch_length.lp,(" + model ["branch-length-string"] + ")-" + value + "," + models.codon.MG_REV.set_branch_length.alpha + ",0,10000)");
                Eval ("`models.codon.MG_REV.set_branch_length.alpha.p` =" + models.codon.MG_REV.set_branch_length.lp);
            }
        }
    }
    
    return 0;
 }