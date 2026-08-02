The important takeaway

A PVC does not guarantee that storage is portable.

It only guarantees that the pod is decoupled from the storage implementation.

Whether the data can move with the pod depends on what the PV is backed by:

PV → hostPath → data is stuck on one node.
PV → NFS / Ceph / EBS / Azure Disk / Longhorn → data can generally follow the pod (subject to the storage system and access mode).

So when you see a hostPath inside a PV, remember that the persistence comes from the PV/PVC abstraction, but the storage characteristics still come from the backend (hostPath). A hostPath-backed PV is persistent only as long as that node and its local filesystem remain available.