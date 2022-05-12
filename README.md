# ProConScheduler

Overview:

While scheduling the containers on the clusters, usual placement schemes doesn't really consider the fact that short lived containers will release the used resources once they are completed. So, the estimated completion time plays an important role while scheduling the incoming containers. So, Progress based container scheduler assigns the incoming pods to the worker nodes so that it balances the contention rate across the worker nodes.

Steps to run ProCon SCheduler:

Step 1: Step up Google Kubernetes Engine

Step 2:
On GKE first create nfs server for creating persistent volume:
gcloud filestore instances create nfs-server --project={PROJECT_ID} --zone={ZONE} --tier=STANDARD --file-share=name="vol1",capacity=1TB --network=name="default",reserved-ip-range="10.0.0.0/29"

Step 3:
Upload the daemonSet.yaml file into local file system of GKE
Run the daemon jobs that act like log Analyst on the batch applications:
kubectl apply -f daemonSet.yaml

Step 4: Run kubectl proxy in one terminal
kubectl proxy

Step 5: 
Upload the bashScheduler.sh file into local file system of GKE
In another terminal run the bashScheduler
./bashScheduler.sh

Step 6: Now run any job with the custom scheduler
