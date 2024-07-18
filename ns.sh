#!/bin/bash

url="www.mes-demarches.gov.pf"

# Intervalle de temps entre les tests (en secondes)
interval=.2

# Nombre de tests à effectuer
iterations=1000

for i in $(seq 1 $iterations); do
    # Mesurer le temps de résolution DNS
    start_time=$(date +%s%3N) # En millisecondes
    output=$(dig +short $url)
    end_time=$(date +%s%3N) # En millisecondes

    # Calculer le temps écoulé
    elapsed_time=$((end_time - start_time))
    elapsed_seconds=$(echo "scale=3; $elapsed_time / 1000" | bc)

    # Vérifier si le DNS a répondu
    if [ -z "$output" ]; then
        echo "$(date): DNS query for $url failed" | tee -a dns_test_results.txt
    else if (( $(echo "$elapsed_seconds > 1" | bc -l) )); then
        echo "$(date): DNS query took more than 1s - Time: ${elapsed_seconds}s" | tee -a dns_test_results.txt
    else 
        echo "Time : ${elapsed_seconds}s" >> trace.txt
    fi
    fi

    # Pause avant le prochain test
    sleep $interval
done
