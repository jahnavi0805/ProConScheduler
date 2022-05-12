#!/usr/bin/env bash

set -eo pipefail
# uncomment to see all commands in stdout
# set -x

SERVER="${SERVER:-localhost:8001}"
SCHEDULER="${SCHEDULER:-bashScheduler}"
while true; do
    for TARGET_POD in $(kubectl --server ${SERVER} get pods \
                --output jsonpath='{.items..metadata.name}' \
                --all-namespaces \
                --field-selector=status.phase==Pending); do
        SCHEDULER_NAME=$(kubectl get pod ${TARGET_POD} \
                        --output jsonpath='{.spec.schedulerName}')
        if [ "${SCHEDULER_NAME}" == "${SCHEDULER}" ]; then
        # Get the pod namespace
            NAMESPACE=$(kubectl get pod ${POD} \
                        --output jsonpath='{.metadata.namespace}')
            
            declare -A NODES_ALLOCATABLE_MEMORY
            declare -A NODES_ALLOCATABLE_CPU
            IFS=' '
            NODES_ALLOCATABLE=$(kubectl get no -o json |   jq -r '.items | sort_by(.status.capacity.memory)[]|[.metadata.name,.status.allocatable.memory,.status.allocatable.cpu]| @tsv')
            readarray -t NODES_ALLOCATABLE <<<"$NODES_ALLOCATABLE"
            for DETAILS in "${NODES_ALLOCATABLE[@]}";do
                DETAILS=$(echo "$DETAILS" | sed -e "s/[[:space:]]\+/;/g")
                NODE=$(echo $DETAILS | cut -d ";" -f 1)
                memory=$(echo $DETAILS | cut -d ";" -f 2)
                cpu=$(echo $DETAILS | cut -d ";" -f 3)  
                if [[ $memory == *"K"* ]] || [[ $memory == *"k"* ]]; then
                    memory=$(echo "$memory" | sed 's/K//g; s/k//g; s/i//g')
                    memory=$((memory * 1000))
                elif [[ $memory == *"M"* ]] || [[ $memory == *"m"* ]]; then
                    memory=$(echo "$memory" | sed 's/M//g; s/m//g; s/i//g')
                    memory=$((memory * 1000000))
                elif [[ $memory == *"G"* ]] || [[ $memory == *"g"* ]]; then
                    memory=$(echo "$memory" | sed 's/G//g; s/g//g; s/i//g')
                    memory=$((memory * 1000000000))
                fi
                NODES_ALLOCATABLE_MEMORY[$NODE]=$memory    
                if [[ $cpu == *"m"* ]]; then
                    cpu=$(echo "$cpu" | sed 's/m//g')
                    NODES_ALLOCATABLE_CPU[$NODE]=$cpu
                else
                    NODES_ALLOCATABLE_CPU[$NODE]=$((cpu*1000))
                fi
            done

            NODES=($(kubectl --server ${SERVER} get nodes \
                    --output jsonpath='{.items..metadata.name}'))
            
            declare -A NODES_REMAINING_MEM
            declare -A NODES_REMAINING_CPU
            declare -A NODES_CPU_RESOURCE_USAGE; 
            declare -A NODES_MEM_RESOURCE_USAGE;     
            declare -a delete_nodes=()
            declare -a pods_available=()
            declare -A PODS_CPU_USAGE
            declare -A PODS_MEM_USAGE
            declare -A NUM_PODS_IN_NODES
            temp=0
            for NODE in ${NODES[@]}
            do 
                NODES_REMAINING_MEM[$NODE]=${NODES_ALLOCATABLE_MEMORY[$NODE]}
                NODES_REMAINING_CPU[$NODE]=${NODES_ALLOCATABLE_CPU[$NODE]}
                NODES_CPU_RESOURCE_USAGE[$NODE]=1
                NODES_MEM_RESOURCE_USAGE[$NODE]=1
                PODS=$(kubectl get pods --output jsonpath='{.items..metadata.name}' --field-selector=status.phase==Running,spec.nodeName==$NODE)
                PODS_ARRAY=(`echo $PODS | tr ' ' ' '`)
                PODS_LENGTH=${#PODS_ARRAY[@]}
                NUM_PODS_IN_NODES[$NODE]=$PODS_LENGTH
                for POD in ${PODS_ARRAY[@]} 
                do
                    pods_available+=($POD)
                    val=$(kubectl top pod $POD)
                    val=$(echo $val | sed ':a;N;$!ba;s/\n/,/g' | cut -d "," -f 2 )
                    cpu=$(echo $val | cut -d " " -f 2)
                    memory=$(echo $val | cut -d " " -f 3)
                    rem_mem=${NODES_REMAINING_MEM[$NODE]}
                    rem_cpu=${NODES_REMAINING_CPU[$NODE]}
                    if [[ $memory == *"K"* ]] || [[ $memory == *"k"* ]]; then
                        memory=$(echo "$memory" | sed 's/K//g; s/k//g; s/i//g')
                        memory=$((memory * 1000))
                    elif [[ $memory == *"M"* ]] || [[ $memory == *"m"* ]]; then
                        memory=$(echo "$memory" | sed 's/M//g; s/m//g; s/i//g')
                        memory=$((memory * 1000000))
                    elif [[ $memory == *"G"* ]] || [[ $memory == *"g"* ]]; then
                        memory=$(echo "$memory" | sed 's/G//g; s/g//g; s/i//g')
                        memory=$((memory * 1000000000))
                    fi
                    NODES_REMAINING_MEM[$NODE]=$((rem_mem-memory))
                    if [[ $cpu == *"m"* ]]; then
                        cpu=$(echo "$cpu" | sed 's/m//g')
                        NODES_REMAINING_CPU[$NODE]=$((rem_cpu-cpu))
                    else
                        cpu=$((cpu*1000))
                        NODES_REMAINING_CPU[$NODE]=$((rem_cpu-cpu))
                    fi
                    if [[ $POD != "test"* ]]; then
                        temp_cpu=${NODES_CPU_RESOURCE_USAGE[$NODE]}
                        temp_mem=${NODES_MEM_RESOURCE_USAGE[$NODE]}
                        NODES_CPU_RESOURCE_USAGE[$NODE]=$((temp_cpu+cpu))
                        NODES_MEM_RESOURCE_USAGE[$NODE]=$((temp_mem+memory))
                    fi  
                    PODS_CPU_USAGE[$POD]=$cpu
                    PODS_MEM_USAGE[$POD]=$memory                      
                done  
                limit=20
                if [ "${NODES_REMAINING_CPU[$NODE]}" -lt "$limit" ] || [ "${NODES_REMAINING_MEM[$NODE]}" -lt "$temp" ]; then
                    delete_nodes+=($NODE)
                fi
            done 

            PODS=$(kubectl --server ${SERVER} get pods \
                        --output jsonpath='{.items..metadata.name}')
            
            PODS_ARRAY=(`echo $PODS | tr ' ' ' '`)
            
            for POD in ${PODS_ARRAY[@]}; do
                mkdir -p /home/jahnaviswethap/logs
                if [[ $POD == "test"* ]]; then
                    for NODE in "${NODES[@]}"; do 
                    outFile="/home/jahnaviswethap/logs/$NODE.txt"
                        if [ -f "$outFile" ] ; then
                            rm "$outFile"
                        fi
                        kubectl cp $POD:/var/tmp/logs/$NODE.txt $outFile
                    done
                    break;
                fi
            done

            for value in "${delete_nodes[@]}"
            do
                NODES=("${NODES[@]/$value}")
            done

            NODES_LENGTH=${#NODES[@]}
            if [ "$NODES_LENGTH" -eq "$temp" ]; then
                break;
            fi        

            TARGET_NODE=""
            

            min_node_contention=-1
            neg_val=-1

            for NODE in "${NODES[@]}"; do
                n=0
                while read -n1 character; do
                    n=$((n+1)); 
                done < <(echo -n "$NODE")
                if [[ $n == 0 ]]; then
                    continue;
                fi                
                outFile="/home/jahnaviswethap/logs/$NODE.txt"
                node_cpu_usage=${NODES_CPU_RESOURCE_USAGE[$NODE]}
                node_mem_usage=${NODES_MEM_RESOURCE_USAGE[$NODE]}
                node_cpu_usage=$((node_cpu_usage+1))
                node_mem_usage=$((node_mem_usage+1))
                max_contention=0
                while read line; do  
                    n=0
                    while read -n1 character; do
                        n=$((n+1)); 
                    done < <(echo -n "$line")
                    if [[ $n == 0 ]]; then
                        break;
                    fi              
                    pod_name=$(echo $line | cut -d ":" -f 1)
                    time_taken=$(echo $line | cut -d ":" -f 2)
                    for pod in ${pods_available[@]}; do
                        if [[ "$pod_name" == "$pod"* ]]; then
                            pod_name=$pod
                            break;
                        fi
                    done
                    pod_cpu_usage=${PODS_CPU_USAGE[$POD]}
                    pod_mem_usage=${PODS_MEM_USAGE[$POD]}            
                    cpu_percentage=$((8*pod_cpu_usage))
                    cpu_percentage=$((cpu_percentage/node_cpu_usage))
                    mem_percentage=$((2*pod_mem_usage))
                    mem_percentage=$((mem_percentage/node_mem_usage))
                    pod_res_percentage=$((cpu_percentage+mem_percentage))
                    pod_res_percentage=$((pod_res_percentage*100))
                    pod_res_percentage=$((pod_res_percentage+1))
                    pod_contention_rate=$((time_taken/pod_res_percentage))
                    if [ "$pod_contention_rate" -gt "$max_contention" ]; then
                        max_contention=$pod_contention_rate
                    fi            
                done < $outFile
                if [ "$TARGET_NODE" = "" ]; then
                    TARGET_NODE=$NODE
                fi
                echo ${NUM_PODS_IN_NODES[$NODE]} ${NUM_PODS_IN_NODES[$TARGET_NODE]} $min_node_contention $max_contention
                if [ "$min_node_contention" -eq "$neg_val" ] ; then
                    min_node_contention=$max_contention
                    echo "Starting" $NODE $min_node_contention $max_contention
                    TARGET_NODE=$NODE
                elif [ "$min_node_contention" -gt "$max_contention" ]; then
                    min_node_contention=$max_contention
                    TARGET_NODE=$NODE
                    echo "Greater" $NODE $min_node_contention $max_contention
                elif [ "$min_node_contention" -eq "$max_contention" ] && [ "${NUM_PODS_IN_NODES[$NODE]}" -lt "${NUM_PODS_IN_NODES[$TARGET_NODE]}" ] ; then
                    min_node_contention=$max_contention
                    TARGET_NODE=$NODE
                    echo "Equal" $NODE $min_node_contention $max_contention
                fi
            done
            if [ "$TARGET_NODE" = "" ]; then
                echo "Didn't find suitable node"
                continue;
            fi
            curl --silent --fail \
                --header "Content-Type:application/json" \
                --request POST \
                --data '{"apiVersion":"v1",
                        "kind": "Binding", 
                        "metadata": {
                        "name": "'${TARGET_POD}'"
                        }, 
                        "target": {
                        "apiVersion": "v1", 
                        "kind": "Node", 
                        "name": "'${TARGET_NODE}'"
                        }
                        }' \
                http://${SERVER}/api/v1/namespaces/${NAMESPACE}/pods/${TARGET_POD}/binding/ >/dev/null \
                && echo "Assigned ${TARGET_POD} to ${TARGET_NODE}" \
                || echo "Failed to assign ${TARGET_POD} to ${TARGET_NODE}"
        fi
    done
    echo "Nothing to do...sleeping."
    sleep 6s
done
