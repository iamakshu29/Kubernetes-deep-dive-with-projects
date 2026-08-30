# AWS Security Services — SAA Refresh Sheet
> Focused on security-layer services. Basics (VPC, EC2, ELB, ASG, SG, S3, IGW, NAT) skipped.

---

## 1. IAM — Advanced

**Key Points**
- **Policy types** (in priority order): SCP → Resource-based → Identity-based → Permissions boundary → Session policy
- **Explicit Deny always wins**, regardless of any Allow
- `sts:AssumeRole` triggers when a principal *crosses account/service boundary*
- **Permission Boundary** = max permissions an entity CAN have (does not grant by itself)
- **IAM Policy Conditions**: `aws:SourceIp`, `aws:MultiFactorAuthPresent`, `aws:RequestedRegion`, `aws:PrincipalOrgID`
- **IAM Access Analyzer** — finds resources shared *outside your org/account* (S3, IAM roles, KMS, Lambda, SQS)
- **Service Control Policies (SCPs)** apply at OU/Account level in Organizations; do NOT affect management account

**Practice Questions**
1. A policy has both an explicit Deny and an Allow for `s3:PutObject`. What happens?
2. How does a Permission Boundary differ from an SCP?
3. An EC2 instance in Account A needs to read an S3 bucket in Account B. What's the minimum required?
4. `aws:PrincipalOrgID` condition key — where is it most useful?
5. IAM Access Analyzer found an S3 bucket is "externally accessible." What does that mean?

---

## 2. AWS KMS (Key Management Service)

**Key Points**
- **CMK types**: AWS Managed (`aws/service`), Customer Managed, Customer-provided (imported)
- **Key policies** are the *primary* access control (not IAM alone) — the key policy must explicitly grant access
- **Envelope Encryption**: KMS encrypts a *Data Encryption Key (DEK)*; DEK encrypts actual data
- **KMS key rotation**: automatic only for symmetric CMKs (annual), NOT for asymmetric or imported keys
- **Multi-Region Keys**: same key material in multiple regions — useful for DR/replication (NOT global, must be explicitly replicated)
- **KMS Grants**: temporary, programmatic delegation of key use (used by services like EBS, Secrets Manager)
- Default KMS key for a service cannot be deleted/rotated manually
- Cross-account KMS usage requires: key policy allows target account + IAM policy in target account

**Practice Questions**
1. Why can't you enable auto-rotation on an asymmetric KMS key?
2. What is envelope encryption and why is it used instead of KMS encrypting data directly?
3. How do you share a KMS key across accounts?
4. You deleted a CMK. What happens to data encrypted with it?
5. Difference between a KMS Grant and a Key Policy?

---

## 3. AWS CloudHSM

**Key Points**
- **Single-tenant** dedicated HSM — you manage the keys entirely (AWS has NO access)
- Use when: FIPS 140-2 Level 3 required, compliance mandates customer-exclusive key control
- KMS *can* use CloudHSM as a backing store (Custom Key Store)
- Deployed inside your VPC; requires cluster of ≥2 HSMs for HA
- If you lose credentials to CloudHSM → keys are **permanently unrecoverable**

**Practice Questions**
1. When would you choose CloudHSM over KMS?
2. Can AWS recover your keys if you lose CloudHSM credentials?
3. What is a KMS Custom Key Store?

---

## 4. AWS WAF (Web Application Firewall)

**Key Points**
- Protects at **Layer 7** (HTTP/HTTPS) — attach to: CloudFront, ALB, API Gateway, AppSync
- **Web ACL** contains rules and rule groups
- Rule actions: `Allow`, `Block`, `Count`, `CAPTCHA`
- **Managed Rule Groups** (AWS & Marketplace): pre-built rulesets (Core Rule Set, SQLi, XSS, Bot Control, IP Reputation)
- **Rate-based rules**: block IPs exceeding X requests/5 min
- WAF is **NOT attached to NLB or EC2 directly**
- AWS WAF Logs → S3, CloudWatch Logs, Kinesis Firehose

**Practice Questions**
1. You need to block SQL injection at the application layer. What service and where do you attach it?
2. Can WAF be attached to a Network Load Balancer? Why/why not?
3. A specific IP is flooding your API Gateway. What WAF rule type handles this?
4. How do you test a WAF rule without enforcing it?

---

## 5. AWS Shield

**Key Points**
- **Shield Standard**: free, automatic, protects against L3/L4 DDoS (SYN floods, UDP reflection)
- **Shield Advanced**: paid (~$3,000/month), adds:
  - L7 DDoS detection with WAF integration
  - **DDoS cost protection** (credits for scaling charges during attack)
  - **24/7 DRT** (DDoS Response Team) access
  - Near real-time visibility + attack forensics
  - Protects: EC2, ELB, CloudFront, Route 53, Global Accelerator
- Shield Advanced must be explicitly subscribed and resources must be added to *protection group*

**Practice Questions**
1. What does Shield Standard protect against that Shield Advanced adds to?
2. A company got a huge AWS bill after a DDoS attack. Which feature of Shield Advanced addresses this?
3. Shield Standard is free — what is it NOT protecting against?

---

## 6. AWS GuardDuty

**Key Points**
- **Threat detection service** — analyzes: VPC Flow Logs, CloudTrail, DNS Logs, S3 data events, EKS audit logs, RDS login activity, Lambda network activity
- **No infrastructure to manage** — fully managed, ML-based
- Findings classified by severity: Low / Medium / High
- Common findings: `UnauthorizedAccess:EC2/SSHBruteForce`, `CryptoCurrency:EC2/BitcoinTool`, `Recon:IAMUser/UserPermissions`
- **Multi-account**: delegate a GuardDuty admin account via Organizations
- **NOT a prevention tool** — detection only; integrate with EventBridge + Lambda/SNS to auto-remediate
- Suppression rules: mute known-benign findings
- **Malware Protection**: scans EBS volumes on suspicious EC2/container findings

**Practice Questions**
1. GuardDuty detected `Recon:IAMUser/UserPermissions`. What does this mean?
2. You have 50 accounts in AWS Organizations. How do you centralize GuardDuty findings?
3. GuardDuty vs. Security Hub — what's the fundamental difference?
4. Can GuardDuty automatically block a suspicious IP?

---

## 7. AWS Inspector

**Key Points**
- **Vulnerability assessment** for: EC2 (via SSM agent), ECR container images, Lambda functions
- Checks: CVEs (software vulnerabilities), network reachability, CIS benchmarks
- Continuously scans — rescans when new CVEs are published or packages change
- Inspector v2 (current) = event-driven, integrated with Organizations
- Findings sent to **Security Hub** automatically
- **Does NOT need agent for ECR** — scans images on push

**Practice Questions**
1. Inspector vs. GuardDuty — which one detects a known unpatched vulnerability on an EC2?
2. What agent does Inspector v2 require for EC2 scanning?
3. You push a container image to ECR. How do you ensure it's scanned for CVEs automatically?

---

## 8. AWS Macie

**Key Points**
- **Data security service for S3** — discovers and protects sensitive data (PII, PHI, credentials, financial data)
- Uses ML + pattern matching
- Generates findings: Policy findings (S3 config issues) + Sensitive Data findings
- Policy finding examples: `Policy:IAMUser/S3BucketPubliclyAccessible`, `Policy:IAMUser/S3BucketSharedExternally`
- Multi-account support via Organizations
- **Only works on S3** (not other storage services)

**Practice Questions**
1. A developer accidentally pushed a file with credit card numbers to S3. Which service would alert on this?
2. Macie found `Policy:IAMUser/S3BucketPubliclyAccessible`. What triggered this?
3. Can Macie scan data in DynamoDB or EFS?

---

## 9. AWS Security Hub

**Key Points**
- **Centralized security findings aggregator** — ingests from: GuardDuty, Inspector, Macie, Firewall Manager, IAM Access Analyzer, Config, third-party tools
- Runs **security standards checks**: CIS AWS Foundations, AWS Foundational Security Best Practices, PCI DSS
- **Security Score** per account/standard
- Consolidated findings in ASFF (Amazon Security Finding Format)
- Requires GuardDuty/Inspector/Macie to be enabled separately — Security Hub aggregates, not replaces
- Cross-region aggregation supported
- **Administrator account** manages member accounts via Organizations

**Practice Questions**
1. What is the relationship between Security Hub and GuardDuty?
2. How do you get a "security posture score" across your AWS accounts?
3. Security Hub vs. AWS Config — what's the difference?

---

## 10. AWS Config

**Key Points**
- **Configuration tracking and compliance** — records configuration history of AWS resources
- **Config Rules**: evaluate if resources comply with desired config
  - **AWS Managed Rules** (pre-built): `s3-bucket-public-read-prohibited`, `encrypted-volumes`, `mfa-enabled-for-iam-console-access`
  - **Custom Rules**: Lambda-backed
- **Remediation**: trigger SSM Automation when non-compliant (manual or auto)
- **Config Aggregator**: multi-account/region compliance view
- **NOT real-time prevention** — it detects after the fact (with EventBridge you can get near-real-time)
- Stores config snapshots in S3; config history retained per your settings

**Practice Questions**
1. How do you auto-remediate an unencrypted EBS volume detected by Config?
2. What's the difference between Config and CloudTrail?
3. A Config rule `restricted-ssh` is non-compliant. What does that mean?
4. Can Config prevent a misconfiguration from happening?

---

## 11. AWS CloudTrail

**Key Points**
- **API call auditing** — records who did what, when, from where across all AWS services
- Events: **Management events** (default, free) vs. **Data events** (S3 object-level, Lambda invokes — extra cost)
- **Insight events**: detect unusual API activity (bursts, anomalous patterns)
- Trail logs stored in **S3** (can also send to CloudWatch Logs)
- **Multi-region trail**: single trail covering all regions (best practice)
- **Organization trail**: single trail for all accounts in an org
- Log file **integrity validation**: SHA-256 hash chaining — detect if logs are tampered
- CloudTrail is **NOT real-time** (up to ~15 min delay); EventBridge is faster for real-time triggers
- **90-day event history** available in console without a trail

**Practice Questions**
1. You need to audit all S3 `GetObject` calls. What do you need to enable?
2. CloudTrail vs. VPC Flow Logs — what does each capture?
3. How do you prove CloudTrail logs haven't been tampered with?
4. An IAM user's credentials were compromised. How do you find what they did?

---

## 12. AWS Secrets Manager

**Key Points**
- Stores and **auto-rotates** secrets (DB credentials, API keys, OAuth tokens)
- Native rotation support for: RDS, Redshift, DocumentDB, other via Lambda custom rotation
- Rotation = Lambda function updates secret + updates the service (e.g., RDS password)
- **Versioning**: `AWSCURRENT`, `AWSPENDING`, `AWSPREVIOUS` stages
- Secrets are **encrypted by KMS CMK** (customer or AWS managed)
- Cross-account access via resource-based policy + KMS key policy
- **Secrets Manager vs. SSM Parameter Store**:
  | Feature | Secrets Manager | SSM Parameter Store |
  |---|---|---|
  | Auto rotation | Yes (built-in) | No (custom Lambda needed) |
  | Cost | ~$0.40/secret/month | Free (Standard), paid (Advanced) |
  | Size limit | 65KB | 4KB (Standard), 8KB (Advanced) |
  | Cross-account | Yes | Limited |
  | Primary use | Secrets/credentials | Config + secrets |

**Practice Questions**
1. Your app connects to RDS. Credentials are hardcoded. What's the AWS best practice fix?
2. What happens to an application during Secrets Manager secret rotation?
3. When would you use SSM Parameter Store over Secrets Manager?
4. How is a secret protected at rest in Secrets Manager?

---

## 13. AWS Certificate Manager (ACM)

**Key Points**
- Provisions and manages **TLS/SSL certificates** (free for public certs)
- Public certs auto-renew (60 days before expiry)
- **ACM certificates cannot be exported** (private key never leaves ACM)
- Use with: ALB, CloudFront, API Gateway, Elastic Beanstalk
- **NOT usable directly on EC2** — must be behind ALB/CloudFront
- **Private CA (ACM PCA)**: issue private certs for internal services (paid)
- DNS validation (recommended) vs. Email validation for cert issuance
- For CloudFront, cert must be in **us-east-1** region

**Practice Questions**
1. You want to use an ACM cert on an EC2 instance directly. Is this possible?
2. Why do ACM public certs need to be in us-east-1 for CloudFront?
3. What's ACM Private CA used for?
4. What are the two validation methods for ACM cert issuance?

---

## 14. AWS Cognito

**Key Points**
- **User Pools**: user directory — sign-up, sign-in, MFA, social IdP federation (Google, Facebook), SAML/OIDC
  - Returns: JWT tokens (ID token, Access token, Refresh token)
- **Identity Pools (Federated Identities)**: grant **temporary AWS credentials** to authenticated/unauthenticated users via STS
- Flow: User Pool authenticates → Identity Pool exchanges JWT for AWS credentials (`sts:AssumeRoleWithWebIdentity`)
- **Cognito Sync** (legacy) → replaced by AppSync
- User Pools ≠ IAM — they're for app user authentication, not AWS service access
- Triggers: Pre-signup, Post-confirmation, Pre-token generation, etc. (Lambda functions)

**Practice Questions**
1. What's the difference between User Pool and Identity Pool?
2. A mobile app needs to call an S3 bucket as an authenticated user. Which Cognito component provides AWS credentials?
3. Where are JWTs issued — User Pool or Identity Pool?
4. How does Cognito integrate with SAML providers (e.g., Active Directory)?

---

## 15. AWS STS (Security Token Service)

**Key Points**
- Issues **temporary security credentials** (Access Key ID + Secret + Session Token)
- Key APIs:
  - `AssumeRole` — assume a role in same/cross account
  - `AssumeRoleWithWebIdentity` — for web/mobile app users (Cognito, OIDC)
  - `AssumeRoleWithSAML` — for enterprise SSO via SAML 2.0
  - `GetSessionToken` — for MFA-protected API calls
  - `GetFederationToken` — legacy, for custom identity broker
- **ExternalId**: used in cross-account role assumption to prevent *confused deputy attack*
- Session duration: 15 min to 12 hours (or 36 hours for some)

**Practice Questions**
1. What is the "confused deputy" problem in cross-account role assumption?
2. How does ExternalId prevent the confused deputy problem?
3. `AssumeRoleWithWebIdentity` vs. `AssumeRoleWithSAML` — when to use each?
4. You need an EC2 instance to access DynamoDB without hardcoding credentials. What STS API is implicitly used?

---

## 16. AWS Organizations & SCPs

**Key Points**
- **SCPs** (Service Control Policies): allow/deny at OU/account level — sets *maximum permissions*
- SCP does NOT grant permissions; it just restricts what IAM can grant
- SCPs don't affect: management account, service-linked roles
- **Deny list strategy** (default): `FullAWSAccess` SCP attached + explicit denies added
- **Allow list strategy**: remove `FullAWSAccess`, explicitly allow only what's needed (more restrictive)
- **Guardrails**: preventive (SCPs) vs. detective (Config rules via Control Tower)

**Practice Questions**
1. An SCP denies `ec2:TerminateInstances`. An IAM policy allows it. Can the user terminate instances?
2. Does an SCP affect the management (root) account?
3. You want to prevent any account in your org from disabling CloudTrail. How?
4. Difference between SCP deny list strategy and allow list strategy?

---

## 17. AWS Control Tower

**Key Points**
- Automates **multi-account setup** using AWS Organizations best practices
- Sets up: Landing Zone, baseline OU structure, mandatory guardrails
- **Guardrails**:
  - *Preventive*: implemented via SCPs (e.g., "Disallow root user actions")
  - *Detective*: implemented via AWS Config rules (e.g., "Detect public S3 buckets")
- **Account Factory**: provision new accounts with pre-approved baseline config
- Integrates with: AWS SSO, Config, CloudTrail, Organizations

**Practice Questions**
1. Control Tower vs. Organizations — what does Control Tower add?
2. What is a Landing Zone in the context of Control Tower?
3. What's the difference between preventive and detective guardrails?

---

## 18. AWS Network Firewall

**Key Points**
- Managed **stateful/stateless network firewall** at the VPC level
- Deployed in a **dedicated firewall subnet** per AZ
- Supports: stateless rules (5-tuple), stateful rules (Suricata-compatible IDS/IPS rules), domain-based filtering
- Use case: inspect/filter traffic between VPCs, to internet, from internet (deeper than SG/NACL)
- **Firewall policy** → rule groups (stateless + stateful)
- Traffic routing: route tables must point to firewall endpoint
- Centralized deployment: use AWS Transit Gateway + inspection VPC pattern

**Practice Questions**
1. SG vs. NACL vs. Network Firewall — when do you use Network Firewall?
2. You need to block outbound traffic to specific malicious domains. What Network Firewall feature handles this?
3. How is Network Firewall integrated into VPC routing?

---

## 19. AWS Firewall Manager

**Key Points**
- **Centrally manage firewall rules across accounts/regions** in AWS Organizations
- Manages: WAF policies, Shield Advanced, SG policies, Network Firewall policies, Route 53 Resolver DNS Firewall
- **Requires**: AWS Organizations, Firewall Manager admin account, AWS Config enabled
- Automatically applies policies to new accounts joining the org
- Use Firewall Manager when you have WAF rules that must be consistent across 10s of accounts

**Practice Questions**
1. You have 100 accounts and need the same WAF rules on all ALBs. What service simplifies this?
2. What are the prerequisites for Firewall Manager?
3. Firewall Manager vs. WAF — what's the relationship?

---

## 20. AWS Detective

**Key Points**
- **Security investigation tool** — builds a graph of relationships between AWS resources, IP addresses, user agents using ML
- Data sources: GuardDuty findings, CloudTrail, VPC Flow Logs
- Helps answer: "What resources did this compromised IAM role touch? What IP was involved?"
- NOT a detection tool — complements GuardDuty for **deep dive investigation**
- Automatically retains data for **up to 1 year**

**Practice Questions**
1. GuardDuty detected a compromised EC2 instance. What service helps you investigate the blast radius?
2. Detective vs. GuardDuty — detection vs. investigation?
3. What data sources does Detective analyze?

---

## 21. Route 53 Resolver DNS Firewall

**Key Points**
- Filters **outbound DNS queries** from VPC resources
- Block domains associated with malware, C2 servers, or custom deny lists
- **Managed domain lists** (AWS): botnet command-and-control, malware domains
- Works with Firewall Manager for org-wide deployment
- Logs to CloudWatch, S3, Kinesis Firehose

**Practice Questions**
1. An EC2 instance is potentially beaconing to a C2 domain. What prevents the DNS lookup?
2. How does DNS Firewall differ from Network Firewall?

---

## Quick Reference: Detection vs. Prevention

| Scenario | Service |
|---|---|
| Block SQL injection on ALB | WAF |
| DDoS protection (L3/L4) | Shield Standard |
| DDoS protection + SLA + DRT | Shield Advanced |
| Threat detection (unusual activity) | GuardDuty |
| Vulnerability scanning (EC2, ECR, Lambda) | Inspector |
| Sensitive data in S3 (PII) | Macie |
| API call audit trail | CloudTrail |
| Resource compliance/drift | AWS Config |
| Centralized findings dashboard | Security Hub |
| Investigate a breach | Detective |
| Encrypt keys, secrets | KMS |
| Store/rotate DB credentials | Secrets Manager |
| App user authentication | Cognito User Pool |
| App user → AWS credentials | Cognito Identity Pool |
| Cross-account access | STS AssumeRole |
| Org-wide service restrictions | SCP (Organizations) |
| Org-wide WAF/firewall policy | Firewall Manager |
| Block malicious DNS | Route 53 DNS Firewall |
| Deep packet inspection in VPC | Network Firewall |

---

## Common Exam Traps

- **KMS key rotation does NOT change the key ARN** — existing ciphertext decryptable with old key material
- **CloudTrail is not real-time** — EventBridge is faster; CloudTrail has ~15 min lag
- **GuardDuty does NOT prevent** — it detects; pair with EventBridge + Lambda to remediate
- **Config does NOT prevent** — it flags after the fact; SCPs/SGs prevent
- **ACM certs can't be used on bare EC2** — must be behind ALB/CloudFront/API GW
- **Shield Advanced covers cost protection** — Standard does not
- **SCPs don't affect the management account** — common trick question
- **Secrets Manager auto-rotation** rotates in place (AWSPENDING → AWSCURRENT) — apps using `GetSecretValue` with no version stage get the latest automatically
- **IAM Permission Boundary ≠ SCP** — both limit max permissions but apply at different scopes (entity vs. account)
- **Inspector scans for CVEs; GuardDuty detects runtime threats** — different signals entirely

---

# DevOps-Specific Sections

---

## 22. CloudWatch — Monitoring & Observability

**Key Points**
- **Metrics**: numeric time-series data; default resolution = 1 min, high-resolution = 1 sec (custom metrics)
- **Namespaces**: logical groupings (`AWS/EC2`, `AWS/EKS`, custom namespace)
- **Dimensions**: key-value pairs that filter metrics (e.g., `InstanceId`, `ClusterName`)
- **Alarms** → states: `OK`, `ALARM`, `INSUFFICIENT_DATA`
  - Actions: SNS, Auto Scaling, EC2 action, Systems Manager OpsItem
  - **Composite Alarms**: combine multiple alarms with AND/OR (reduce alert noise)
- **CloudWatch Logs**:
  - **Log Groups** → **Log Streams** → log events
  - **Retention**: set per log group (default = never expire — costs money, always set a policy)
  - **Metric Filters**: extract numeric values from logs → creates a CloudWatch metric
  - **Subscription Filters**: stream logs in near-real-time → Lambda, Kinesis, Firehose
  - **Log Insights**: ad-hoc query language (`fields`, `filter`, `stats`, `sort`, `limit`)
- **CloudWatch Agent**: push OS-level metrics (memory, disk — NOT default EC2 metrics) + custom logs from EC2/on-prem
- **Embedded Metric Format (EMF)**: write structured JSON logs → auto-creates metrics (used in Lambda)
- **Container Insights**: cluster/pod/task level metrics for EKS and ECS (requires CloudWatch agent as DaemonSet)
- **Application Insights**: ML-based anomaly detection for .NET/Java apps, RDS, ELB
- **Dashboards**: cross-account, cross-region; shareable; can embed in external portals
- **EventBridge** (formerly CloudWatch Events): react to AWS events or schedule cron jobs → triggers Lambda, Step Functions, SNS, etc.
  - Rule types: Event Pattern (react to state changes) vs. Schedule (cron/rate)

**Practice Questions**
1. Memory utilization is not showing in default EC2 CloudWatch metrics. Why, and how do you fix it?
2. You want to trigger a Lambda when an EC2 instance changes to `stopped` state. What service/feature?
3. How do you extract error count from application logs and alarm on it?
4. What's the difference between a Metric Filter and a Subscription Filter?
5. You have 10 alarms for a single service. How do you avoid being paged when only 1 of 10 fires (known flap)?
6. How do you get pod-level CPU/memory metrics from an EKS cluster?

---

## 23. Amazon EKS — Elastic Kubernetes Service

**Key Points**
- **Control plane** managed by AWS (HA across 3 AZs); you manage worker nodes
- **Node types**:
  - Managed Node Groups: EC2, AWS handles provisioning/lifecycle
  - Self-managed nodes: you control AMI, lifecycle
  - Fargate: serverless pods — no node management, pod-level isolation
- **IRSA (IAM Roles for Service Accounts)**: pods assume IAM roles without node-level credentials
  - Flow: pod annotated with service account → OIDC provider → STS `AssumeRoleWithWebIdentity` → temp credentials
  - Replaces: node instance profiles (over-permissive, applies to ALL pods on node)
  - Setup: create OIDC provider for cluster → create IAM role with OIDC trust policy → annotate K8s service account
- **EKS Pod Identity** (newer, simpler alternative to IRSA): EKS manages OIDC token exchange automatically, no need to create OIDC provider manually
- **Cluster access entry**: EKS API-based IAM principal mapping (replaces editing `aws-auth` ConfigMap)
- **aws-auth ConfigMap** (legacy): maps IAM users/roles to Kubernetes RBAC groups
- **Networking**:
  - **VPC CNI plugin**: each pod gets a real VPC IP (from ENI secondary IPs) — enables SG for Pods
  - **SG for Pods**: assign security groups directly to pods (not just nodes)
  - **AWS Load Balancer Controller**: provisions ALB (Ingress) or NLB (Service type LoadBalancer)
- **EKS Add-ons**: CoreDNS, kube-proxy, VPC CNI, EBS CSI driver — managed lifecycle via EKS
- **Fargate profiles**: select which pods run on Fargate via namespace + label selectors
- **EKS Anywhere**: run EKS on-premises (bare metal / VMware)
- **ECR integration**: use IAM roles; `ecr:GetAuthorizationToken` + `ecr:BatchGetImage` needed on node/pod role
- **Cluster logging**: API server, audit, authenticator, controller manager, scheduler logs → CloudWatch Logs

**Practice Questions**
1. All pods on a node share the node's IAM instance profile. Why is this a security problem, and what fixes it?
2. Walk through the IRSA setup steps end-to-end.
3. Your pod needs to read from S3. What's the most secure way to grant that permission?
4. How does EKS Pod Identity differ from IRSA?
5. You need to assign a security group to a specific pod (not the whole node). How?
6. How do you give a developer `kubectl exec` access to pods in one namespace only?
7. What logs does EKS send to CloudWatch, and how do you enable them?
8. Fargate vs. Managed Node Groups — when would you choose Fargate?

---

## 24. AWS Systems Manager (SSM)

**Key Points**
- **Session Manager**: browser/CLI shell access to EC2/on-prem **without SSH, bastion hosts, or open port 22**
  - Requires: SSM Agent + IAM role with `AmazonSSMManagedInstanceCore` policy
  - Sessions logged to S3 / CloudWatch Logs for audit
  - Works with VPC endpoints — traffic never leaves AWS network
- **Parameter Store**: key-value config/secrets store
  - **Standard** (free): 4KB, no rotation
  - **Advanced**: 8KB, parameter policies (expiry/notification), higher throughput
  - Tiers: String, StringList, **SecureString** (encrypted with KMS)
  - Hierarchy: `/app/prod/db/password` — IAM policies can use path-based conditions
  - **vs Secrets Manager**: no auto-rotation, cheaper, good for non-secret config values
- **Run Command**: run scripts/commands across fleets of instances without SSH
  - Uses SSM Documents (AWS-RunShellScript, AWS-RunPowerShellScript, etc.)
  - Target by: tag, instance ID, resource group, all managed instances
  - Output to S3 or CloudWatch Logs
- **Patch Manager**: automate OS/app patching across EC2 and on-prem
  - Patch Baselines: define approved/blocked patches per OS
  - Maintenance Windows: define when patching runs
  - Patch Compliance reports → visible in SSM Compliance dashboard
- **Automation**: runbooks (SSM Documents) for common operational tasks (stop/start EC2, create AMI, etc.)
  - Triggered by: EventBridge, Config remediation, manual
- **OpsCenter**: aggregates operational issues (OpsItems) from CloudWatch, Config, GuardDuty
- **Inventory**: collects software/config metadata from managed instances
- **SSM Agent**: pre-installed on most AWS AMIs; required for all SSM features
- **Hybrid Activations**: register on-prem servers as managed instances

**Practice Questions**
1. A security policy says no port 22 or 3389 should be open. How do you still get shell access to EC2?
2. What IAM permissions does an EC2 instance need for Session Manager?
3. How do you store a database password in SSM Parameter Store securely and retrieve it in a shell script?
4. You need to run a patching script across 200 EC2 instances. How?
5. How do you ensure Session Manager sessions are audited?
6. Parameter Store SecureString vs. Secrets Manager — decision criteria?

---

## 25. Networking for DevOps — VPC Endpoints & PrivateLink

**Key Points**
- **VPC Endpoints**: allow resources in private subnets to reach AWS services **without IGW, NAT, or public IP**
- **Gateway Endpoints** (free):
  - Only for **S3** and **DynamoDB**
  - Added as a route in route table (not an ENI)
  - Does NOT use a DNS name; uses route table prefix lists
- **Interface Endpoints (PrivateLink)** (paid per hour + data):
  - ENI with private IP in your subnet
  - Works for most AWS services (SSM, KMS, Secrets Manager, ECR, CloudWatch Logs, STS, etc.)
  - Creates private DNS name — overrides public endpoint when enabled
  - Required when: private subnet → SSM/KMS/Secrets Manager without NAT
- **VPC Endpoint Policies**: resource-based policy attached to the endpoint — restricts which principals/actions are allowed through it
- **PrivateLink for custom services**: expose your service (via NLB) to other VPCs/accounts privately
- **VPC Peering**: direct private connectivity between 2 VPCs; NOT transitive
- **Transit Gateway**: hub-and-spoke for connecting many VPCs + on-prem; IS transitive; supports route tables per attachment
- **AWS PrivateLink vs. VPC Peering**:
  | | VPC Peering | PrivateLink |
  |---|---|---|
  | CIDR overlap | Not allowed | Allowed |
  | Transitive routing | No | No (by design) |
  | Use case | Full VPC access | Expose single service |
- **Route 53 Resolver**: DNS resolution between VPC and on-prem
  - Inbound endpoints: on-prem → AWS DNS
  - Outbound endpoints: VPC → on-prem DNS
- **Network Access Analyzer**: identifies unintended network access paths in your VPC

**Practice Questions**
1. An EKS pod in a private subnet needs to pull images from ECR. No NAT Gateway. What do you configure?
2. Difference between Gateway Endpoint and Interface Endpoint?
3. You want to ensure EC2 instances can only reach S3 within your account (not other accounts' buckets). How?
4. When would you use Transit Gateway instead of VPC Peering?
5. Your Jenkins pipeline runs in a private subnet and calls `aws secretsmanager get-secret-value`. It times out. Why?

---

## 26. Cost & Tagging Governance

**Key Points**
- **Cost Allocation Tags**: key-value tags on resources that appear as columns in Cost Explorer / billing reports
  - Must be **activated** in Billing console to show in reports (up to 48-hour delay after activation)
  - Two types: AWS-generated (`aws:createdBy`) and user-defined
- **Tag Policies** (via Organizations): enforce tag key/value standards across accounts
  - Non-compliant resources flagged — does NOT prevent creation (unlike SCPs)
- **Cost Explorer**:
  - Visualize spend by service, account, region, tag
  - **Rightsizing Recommendations**: EC2 instance type suggestions based on utilization
  - **Savings Plans / Reserved Instance recommendations**
  - Data available for up to 12 months historical + 12 months forecast
- **AWS Budgets**:
  - Set spend/usage/RI coverage/Savings Plan coverage thresholds
  - Actions: notify via SNS/email OR auto-apply IAM policy / SCP / target EC2/RDS when budget breaches
  - **Budget Actions**: e.g., attach a deny-all SCP to an account when its budget is exceeded
- **AWS Cost and Usage Report (CUR)**: most granular billing data → S3 → Athena/QuickSight for custom analysis
- **AWS Compute Optimizer**: rightsizing recommendations for EC2, Lambda, EBS, ECS on Fargate, Auto Scaling groups (uses ML on 14 days of metrics)
- **Savings Plans vs. Reserved Instances**:
  | | Reserved Instances | Savings Plans |
  |---|---|---|
  | Commitment | Specific instance type/region | Compute spend ($/hr) |
  | Flexibility | Low (Standard RI) / Medium (Convertible RI) | High (applies across EC2, Lambda, Fargate) |
  | EC2-specific plan | Yes | EC2 Savings Plan (region-locked) |
- **AWS Trusted Advisor**: checks across 5 categories: Cost Optimization, Performance, Security, Fault Tolerance, Service Limits
  - Full checks require Business/Enterprise Support plan
- **Service Quotas**: view and request increases for service limits; set CloudWatch alarms on quota usage

**Practice Questions**
1. You need to see cost breakdown by team. What's the minimum setup required?
2. Tag Policy says `Environment` must be `prod`, `staging`, or `dev`. A developer creates an EC2 with `Environment=production`. What happens?
3. How do you automatically stop all EC2 in an account when monthly spend hits $500?
4. Compute Optimizer vs. Trusted Advisor — what's the difference in rightsizing recommendations?
5. What's the most granular billing data source in AWS, and how do you query it at scale?
6. Savings Plans vs. Reserved Instances — when would you choose Compute Savings Plans?

---

## DevOps Quick Reference

| Need | Service / Feature |
|---|---|
| Shell access without SSH/bastion | SSM Session Manager |
| Run scripts across 100s of instances | SSM Run Command |
| OS patching at scale | SSM Patch Manager |
| Store config/non-secret params | SSM Parameter Store (Standard) |
| Store secrets with auto-rotation | Secrets Manager |
| Pod-level IAM permissions on EKS | IRSA or EKS Pod Identity |
| K8s pod → S3/DynamoDB without NAT | VPC Interface/Gateway Endpoint |
| Metrics for memory/disk on EC2 | CloudWatch Agent |
| Pod/container metrics in EKS | Container Insights |
| Alarm on log pattern | CloudWatch Metric Filter + Alarm |
| Stream logs to Lambda/Kinesis | CloudWatch Subscription Filter |
| React to AWS state changes | EventBridge |
| Cost breakdown by team/project | Cost Allocation Tags + Cost Explorer |
| Auto-enforce budget | AWS Budgets Actions |
| Rightsizing EC2/Lambda | Compute Optimizer |
| Org-wide tag standards | Organizations Tag Policies |
