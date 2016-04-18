LoadFunctionLibrary ("../terms-json.bf");

mpi.job_id = 0;


lfunction mpi.create_queue (nodesetup) {
    /** create and return an empty FIFO queue for MPI jobs */
    mpi_node_count = utility.getEnvVariable ("MPI_NODE_COUNT");
    
    queue = {};
    send_to_nodes = ""; 
    if (mpi_node_count > 1) {
    
    
        if (None != nodesetup) {
            if (Abs (nodesetup)) {
                
                utility.setEnvVariable ("LF_NEXUS_EXPORT_EXTRA", 
                                        'PRESERVE_SLAVE_NODE_STATE = TRUE; MPI_NEXUS_FILE_RETURN = "None";');
                
                send_to_nodes * 128;
                
                utility.forEach (nodesetup["LikelihoodFunctions"], "_value_", 
                                 '
                                    ExecuteCommands ("Export (mpi.create_queue.temp, " + _value_ + ")");
                                    for (`&k` = 1; `&k` < `mpi_node_count`; `&k` += 1) {
                                    
                                        MPISend (`&k`, mpi.create_queue.temp);
                                        MPIReceive (-1, ignore, ignore);
                                    }
                                    
                                 
                                 ');
                
                send_to_nodes * 0;
            }
        }
    
        for (k = 1; k < mpi_node_count; k += 1) {
            queue [k] = {"job_id" : None, "callback" : None, "arguments": None};
        }
    }
    return queue;
}

function mpi.queue_export_function (func_id) {
    ExecuteCommands ("Export (complete_function_dump, `func_id`)");
    return complete_function_dump;
}

lfunction mpi.queue_job (queue, job, arguments, result_callback) {
    /** 
        send the job function with provided arguments to 
        the first available node.
        
        When the job is finished; call the "result_callback" function 
        
    */
    
    mpi_node_count = utility.getEnvVariable ("MPI_NODE_COUNT");
    
    if (mpi_node_count > 1) {    
        for (node = 1; node < mpi_node_count; node += 1) {
            if (None == (queue [node])["job_id"]) {
                break;
            }
        }
    
        if (node == mpi_node_count) {
            node = mpi._handle_receieve (queue);        
        }

        
        complete_function_dump = mpi.queue_export_function (job);
        ^"mpi.job_id" += 1;    
        queue [node] = {"job_id" : ^"mpi.job_id", "callback" : result_callback, "arguments" : arguments};
        MPISend (node, complete_function_dump + "; return " + job + '(' + Join (",",utility.map (arguments,"_value_", "utility.convertToArgumentString (_value_)")) + ')');    
    } else {
        Call (result_callback, 0, Eval (job + '(' + Join (",",utility.map (arguments,"_value_", "utility.convertToArgumentString (_value_)")) + ')'), arguments);
    }
}

lfunction mpi.queue_complete (queue) {
       
    mpi_node_count = utility.getEnvVariable ("MPI_NODE_COUNT");
    
    if (mpi_node_count > 1) {
        do {
    
            for (node = 1; node < mpi_node_count; node += 1) {
                if (None != (queue [node])["job_id"]) {
                    break;
                }
            }
    
            if (node < mpi_node_count) {
                node = mpi._handle_receieve (queue);        
            }
        } while (node < mpi_node_count);
    }
}

lfunction mpi._handle_receieve (queue) {
    MPIReceive (-1,from,result);
    Call ((queue [from])["callback"], from, Eval(result), (queue [from])["arguments"]);
    queue [from] = {"job_id" : None, "callback" : None};
    return from; 
}