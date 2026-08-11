These are the topics which are new for me, Some of those I know as concept but never did hands-on and while I am deep diving K8s..I need the notes of those topics inside a specific notes folder I created in each task_0 folder
This is the list of new topics below.. I want you to add topicwise summary below for quick review.

TASK_01
    Context
    
TASK_02
    PDB
    Pod AntiAffinity and Topology
    GraceFul Shutodwn Zero Downtime Rolling Updates   

NOTE - Also need to specify tha delete old cluster and delte the calico cluster for Task_03
TASK_03
    Ingress - Code side not theory
    Networking Policies
        1. some notes on nginx-ingress that the default IP is the hostPort define while creating K8s Cluster, 
    CoreDNS
    Certs
    Service Type = LB, ExternalName, External Traffic
    Gateway API

TASK_04
  StorageClass
  emptyDir
  VolumeSnapshots , How we do on Cloud ?
  Velero
  
TASK_05
  ServiceAccount
  PSA
  Kyverno

TASK_06

TASK_07

TASK_08


K8s-Company-Level-References
PHASE-3
    RBAC - like it is deny all type except the reosurce mentioned when created
    Again need to write a difference between ServiceAccount and Users


Ingress Successor is Gateway API (More feature rich thatn Ingress)
Volume Snapshot Successor is Velero (Can use to take backup of complete Namespace instead of just PV)
PSA Successor is Kyverno (Can add more custom rules and policies, along with default Ones)



---------------------------- NEVER LEARNED BEFORE --------------------------------
Should TRY
Service Mesh (Istio/Linkerd)
Multi-cluster/multi-region

Can skip 
Kyverno
Keycloak/AD